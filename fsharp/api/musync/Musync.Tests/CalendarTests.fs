module Musync.Tests.CalendarTests

open System
open System.IO
open System.Net
open System.Net.Sockets
open Expecto
open Ical.Net
open MimeKit
open MailKit.Security
open netDumbster.smtp
open Musync.Domain
open Musync.Config
open Musync.Email

// Unit + in-process integration tests for the calendar path. Everything here is
// deterministic: the VEVENT/MIME/hash builders are pure, and the SMTP test uses a
// loopback fake sink (netDumbster) — no real network, no DB.

// A fixed Id makes the UID deterministic; a known LA instant fixes the all-day
// date (midnight 2026-05-11 America/Los_Angeles == 07:00Z).
let private sampleId = Guid.Parse "11111111-1111-1111-1111-111111111111"
let private userAddress = "user@frank.sh"

let private makeConcert () : Concert = {
  Id = sampleId
  AccountId = "default"
  SongkickUid = SongkickUid.create "songkick-event-11111@songkick.com" |> Want.ok
  Artist = ArtistName.create "Puscifer" |> Want.ok
  Venue = "Golden Gate Theatre"
  City = "San Francisco"
  Country = "US"
  StartsAt = DateTimeOffset(2026, 5, 11, 7, 0, 0, TimeSpan.Zero)
  Tz = "America/Los_Angeles"
  PlanStatus = PlanStatus.Going
  CalendarUid = None
  ContentHash = None
  CalendarSequence = 2
  CalendarSentAt = None
  CalendarAttempts = 0
  CalendarLastError = None
  ProbableSetlist = None
  ProbableSetlistComputedAt = None
  SetlistNotifiedAt = None
  SetlistFoundAt = None
  SetlistAttempts = 0
  SetlistLastError = None
  CreatedAt = DateTimeOffset.MinValue
  UpdatedAt = DateTimeOffset.MinValue
}

let private expectedUid =
  "concert-11111111-1111-1111-1111-111111111111@musync.frank.sh"

/// Parse ICS text back into the first VEVENT for field assertions.
let private firstEvent (ics: string) =
  let cal = Calendar.Load ics
  cal, Seq.head cal.Events

/// Pull the text/calendar part out of a (re-parsed) MIME message.
let rec private findCalendarPart (entity: MimeEntity) : TextPart option =
  match entity with
  | :? Multipart as mp -> mp |> Seq.tryPick findCalendarPart
  | :? TextPart as tp when tp.ContentType.MimeType = "text/calendar" -> Some tp
  | _ -> None

let private freePort () =
  let listener = new TcpListener(IPAddress.Loopback, 0)
  listener.Start()
  let port = (listener.LocalEndpoint :?> IPEndPoint).Port
  listener.Stop()
  port

[<Tests>]
let calendarTests =
  testList "calendar" [
    // ── VEVENT field projection ──────────────────────────────────────────────
    testList "VEVENT" [
      testCase "UID / SEQUENCE / METHOD:REQUEST are the musync-owned values"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeConcert ()) userAddress
        let cal, evt = firstEvent ics
        Want.equal "REQUEST" cal.Method
        Want.equal expectedUid evt.Uid
        Want.equal 2 evt.Sequence

      testCase "all-day DTSTART/DTEND are date-only (no invented showtime)"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeConcert ()) userAddress
        let _, evt = firstEvent ics
        Want.equal true evt.IsAllDay
        Want.equal false evt.Start.HasTime
        // Venue-local date, and DTEND is the exclusive next day.
        Want.equal (DateTime(2026, 5, 11)) evt.Start.Value.Date
        Want.equal (DateTime(2026, 5, 12)) evt.End.Value.Date
        // Raw text carries the VALUE=DATE marker.
        Want.equal true (ics.Contains "DTSTART;VALUE=DATE:20260511")
        Want.equal true (ics.Contains "DTEND;VALUE=DATE:20260512")

      testCase "SUMMARY / LOCATION carry the show fields"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeConcert ()) userAddress
        let _, evt = firstEvent ics
        Want.equal "Puscifer" evt.Summary
        Want.equal "Golden Gate Theatre, San Francisco, US" evt.Location

      testCase "ORGANIZER == ATTENDEE == the user (self-invite)"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeConcert ()) userAddress
        let _, evt = firstEvent ics
        Want.equal ("mailto:" + userAddress) (evt.Organizer.Value.ToString())
        Want.equal 1 evt.Attendees.Count
        Want.equal ("mailto:" + userAddress) (evt.Attendees.[0].Value.ToString())
    ]

    // ── content_hash ─────────────────────────────────────────────────────────
    testList "content_hash" [
      testCase "identical concert => identical hash (deterministic)"
      <| fun _ ->
        Want.equal
          (Musync.Calendar.contentHash (makeConcert ()))
          (Musync.Calendar.contentHash (makeConcert ()))

      testCase "a VEVENT-projected change (venue) => different hash"
      <| fun _ ->
        let baseHash = Musync.Calendar.contentHash (makeConcert ())
        let changed = { makeConcert () with Venue = "The Fillmore" }
        Want.equal false (baseHash = Musync.Calendar.contentHash changed)

      testCase "a NON-projected change (setlist/calendar state) => SAME hash"
      <| fun _ ->
        let baseHash = Musync.Calendar.contentHash (makeConcert ())
        // None of these are projected onto the VEVENT, so the hash must not move.
        let churned = {
          makeConcert () with
              SetlistAttempts = 5
              CalendarSentAt = Some(DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero))
              CalendarSequence = 9
              CalendarAttempts = 3
        }

        Want.equal baseHash (Musync.Calendar.contentHash churned)
    ]

    // ── MIME ─────────────────────────────────────────────────────────────────
    testCase "MIME calendar part is text/calendar;method=REQUEST and re-parses"
    <| fun _ ->
      use message = Musync.Calendar.buildMessage (makeConcert ()) userAddress
      use ms = new MemoryStream()
      message.WriteTo ms
      ms.Position <- 0L
      let reparsed = MimeMessage.Load ms

      match findCalendarPart reparsed.Body with
      | None -> failtest "no text/calendar part found"
      | Some part ->
        Want.equal "text/calendar" part.ContentType.MimeType
        Want.equal "REQUEST" (part.ContentType.Parameters.["method"])
        // The embedded ICS parses back to the same VEVENT identity.
        let _, evt = firstEvent part.Text
        Want.equal expectedUid evt.Uid
        Want.equal "Puscifer" evt.Summary

    // ── SMTP send against a loopback fake sink (netDumbster) ──────────────────
    testCase "EmailSender delivers the MIME to a fake SMTP server"
    <| fun _ ->
      let port = freePort ()
      let server = SimpleSmtpServer.Start port

      try
        let smtp: SmtpConfig = {
          Host = "127.0.0.1"
          Port = port
          Username = "" // empty => EmailSender skips AUTH (the sink has none)
          Password = ""
          From = userAddress
        }
        // The fake sink speaks plaintext, so override the (strict) transport
        // security that production would pick for this port.
        let sender = EmailSender(smtp, SecureSocketOptions.None)

        use message = Musync.Calendar.buildMessage (makeConcert ()) userAddress

        sender.Send message |> Async.RunSynchronously |> Want.isOk

        // Give the async sink a beat to record the message.
        Threading.Thread.Sleep 250
        Want.equal 1 server.ReceivedEmailCount
        let raw = server.ReceivedEmail.[0].Data
        Want.equal true (raw.Contains "text/calendar")
        Want.equal true (raw.Contains "METHOD:REQUEST")
        Want.equal true (raw.Contains expectedUid)
      finally
        server.Stop()
  ]
