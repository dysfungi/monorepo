module Musync.Tests.CalendarTests

open System
open System.IO
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

// A fixed Id makes the UID deterministic; a known LA instant fixes the show date
// (midnight 2026-05-11 America/Los_Angeles == 07:00Z).
let private sampleId = Guid.Parse "11111111-1111-1111-1111-111111111111"
// Phase 4 recipient split: ORGANIZER/From = the musync SEND address; ATTENDEE/To
// = the user's own mailbox (the invite lands in THIS calendar).
let private fromAddress = "musync@frank.sh"
let private userAddress = "user@frank.sh"

let private sampleUrl =
  "https://www.songkick.com/concerts/11111-puscifer-at-golden-gate-theatre"

// LA is PDT (-07:00) in May, so these instants are the venue-local wall times below.
let private laOffset = TimeSpan.FromHours -7.0
let private doorsInstant = DateTimeOffset(2026, 5, 11, 18, 0, 0, laOffset) // 6 PM
let private showInstant = DateTimeOffset(2026, 5, 11, 20, 0, 0, laOffset) // 8 PM

/// Base concert: page URL known, but NOT yet enriched (times/openers/vendor
/// unknown => "?" and the 19:00 DTSTART fallback).
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
  SongkickEventUrl = Some sampleUrl
  EventStartAt = None
  DoorsAt = None
  ShowAt = None
  Openers = []
  TicketVendor = None
  EnrichedAt = None
  CalendarUid = None
  ContentHash = None
  CalendarSequence = 2
  CalendarSentAt = None
  CalendarAttempts = 0
  CalendarLastError = None
  CalendarFirstFailedAt = None
  CalendarAlertedAt = None
  ProbableSetlist = None
  ProbableSetlistComputedAt = None
  SetlistNotifiedAt = None
  SetlistFoundAt = None
  SetlistAttempts = 0
  SetlistLastError = None
  SetlistFirstFailedAt = None
  SetlistAlertedAt = None
  CreatedAt = DateTimeOffset.MinValue
  UpdatedAt = DateTimeOffset.MinValue
}

/// Fully enriched: doors 6 PM, show 8 PM, two openers, an AXS ticket vendor. The
/// resolved event start is doors (mirrors Persistence.storeEnrichment).
let private makeEnriched () : Concert = {
  makeConcert () with
      EventStartAt = Some doorsInstant
      DoorsAt = Some doorsInstant
      ShowAt = Some showInstant
      Openers = [
        "Support A"
        "Support B"
      ]
      TicketVendor =
        Some {
          Name = "AXS"
          Url = "https://www.axs.com/x"
        }
      EnrichedAt = Some(DateTimeOffset(2026, 4, 1, 0, 0, 0, TimeSpan.Zero))
}

let private expectedUid =
  "concert-11111111-1111-1111-1111-111111111111@musync.frank.sh"

let private expectedMaps =
  "https://www.google.com/maps/search/?api=1&query="
  + Uri.EscapeDataString "Golden Gate Theatre, San Francisco"

/// Parse ICS text back into the first VEVENT for field assertions.
let private firstEvent (ics: string) =
  let cal = Calendar.Load ics
  cal, Seq.head cal.Events

/// Normalize CRLF so DESCRIPTION comparisons are line-ending agnostic.
let private lf (s: string) = s.Replace("\r\n", "\n")

/// Pull the text/calendar part out of a (re-parsed) MIME message.
let rec private findCalendarPart (entity: MimeEntity) : TextPart option =
  match entity with
  | :? Multipart as mp -> mp |> Seq.tryPick findCalendarPart
  | :? TextPart as tp when tp.ContentType.MimeType = "text/calendar" -> Some tp
  | _ -> None

[<Tests>]
let calendarTests =
  testList "calendar" [
    // ── VEVENT field projection ──────────────────────────────────────────────
    testList "VEVENT" [
      testCase "UID / SEQUENCE / METHOD:REQUEST are the musync-owned values"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeEnriched ()) fromAddress userAddress
        let cal, evt = firstEvent ics
        Want.equal "REQUEST" cal.Method
        Want.equal expectedUid evt.Uid
        Want.equal 2 evt.Sequence

      testCase "SUMMARY is '<artist> @ <venue>'"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeEnriched ()) fromAddress userAddress
        let _, evt = firstEvent ics
        Want.equal "Puscifer @ Golden Gate Theatre" evt.Summary

      testCase "LOCATION is a Google Maps link for '<venue>, <city>'"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeEnriched ()) fromAddress userAddress
        let _, evt = firstEvent ics
        Want.equal expectedMaps evt.Location

      testCase "timed DTSTART;TZID at doors; DTEND at 23:30 venue-local"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeEnriched ()) fromAddress userAddress
        let _, evt = firstEvent ics
        // Timed (not all-day), zoned to the venue IANA tz, starting at doors (6 PM).
        Want.equal false evt.IsAllDay
        Want.equal true evt.Start.HasTime
        Want.equal "America/Los_Angeles" evt.Start.TzId
        Want.equal (DateTime(2026, 5, 11, 18, 0, 0)) evt.Start.Value
        Want.equal (DateTime(2026, 5, 11, 23, 30, 0)) evt.End.Value

        Want.equal
          true
          (ics.Contains "DTSTART;TZID=America/Los_Angeles:20260511T180000")

        Want.equal true (ics.Contains "DTEND;TZID=America/Los_Angeles:20260511T233000")

      testCase "no page time => DTSTART falls back to 19:00 venue-local"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeConcert ()) fromAddress userAddress
        let _, evt = firstEvent ics
        Want.equal true evt.Start.HasTime
        Want.equal (DateTime(2026, 5, 11, 19, 0, 0)) evt.Start.Value

      testCase "ORGANIZER = musync send addr; ATTENDEE = the user (recipient split)"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeEnriched ()) fromAddress userAddress
        let _, evt = firstEvent ics
        Want.equal ("mailto:" + fromAddress) (evt.Organizer.Value.ToString())
        Want.equal 1 evt.Attendees.Count
        Want.equal ("mailto:" + userAddress) (evt.Attendees.[0].Value.ToString())
    ]

    // ── DESCRIPTION (literal user template) ──────────────────────────────────
    testList "DESCRIPTION" [
      testCase "enriched fields render into the exact template"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeEnriched ()) fromAddress userAddress
        let _, evt = firstEvent ics

        let expected =
          "App: AXS\n\
           Openers: Support A, Support B\n\
           Seats: ?\n\
           Doors: 6 PM\n\
           Show: 8 PM\n\
           \n"
          + sampleUrl

        Want.equal expected (lf evt.Description)

      testCase "all unknowns render as '?' (Songkick URL still present)"
      <| fun _ ->
        let ics = Musync.Calendar.buildIcs (makeConcert ()) fromAddress userAddress
        let _, evt = firstEvent ics

        let expected =
          "App: ?\n\
           Openers: ?\n\
           Seats: ?\n\
           Doors: ?\n\
           Show: ?\n\
           \n"
          + sampleUrl

        Want.equal expected (lf evt.Description)

      testCase "missing Songkick URL renders the trailing line as '?'"
      <| fun _ ->
        let noUrl = { makeConcert () with SongkickEventUrl = None }
        let ics = Musync.Calendar.buildIcs noUrl fromAddress userAddress
        let _, evt = firstEvent ics
        Want.equal true ((lf evt.Description).EndsWith "\n\n?")
    ]

    // ── content_hash = material identity ONLY (clobber-safety) ───────────────
    testList "content_hash" [
      testCase "identical concert => identical hash (deterministic)"
      <| fun _ ->
        Want.equal
          (Musync.Calendar.contentHash (makeEnriched ()))
          (Musync.Calendar.contentHash (makeEnriched ()))

      testCase "material change (date / venue / artist) => different hash"
      <| fun _ ->
        let baseHash = Musync.Calendar.contentHash (makeConcert ())

        let dateChanged = {
          makeConcert () with
              StartsAt = DateTimeOffset(2026, 5, 12, 7, 0, 0, TimeSpan.Zero)
        }

        let venueChanged = { makeConcert () with Venue = "The Fillmore" }

        let artistChanged = {
          makeConcert () with
              Artist = ArtistName.create "Tool" |> Want.ok
        }

        Want.equal false (baseHash = Musync.Calendar.contentHash dateChanged)
        Want.equal false (baseHash = Musync.Calendar.contentHash venueChanged)
        Want.equal false (baseHash = Musync.Calendar.contentHash artistChanged)

      testCase "enrichment / template / location change => SAME hash (no clobber)"
      <| fun _ ->
        // The user hand-edits the event after creation, so late enrichment and
        // template/location text must NEVER move the hash (which would resend and
        // clobber those edits). Only artist/date/venue may.
        let baseHash = Musync.Calendar.contentHash (makeConcert ())

        // times / openers / vendor (the whole enrichment payload)
        Want.equal baseHash (Musync.Calendar.contentHash (makeEnriched ()))
        // the Songkick URL line in the DESCRIPTION
        Want.equal
          baseHash
          (Musync.Calendar.contentHash { makeConcert () with SongkickEventUrl = None })
        // the LOCATION maps link (city is part of it but not the material identity)
        Want.equal
          baseHash
          (Musync.Calendar.contentHash { makeConcert () with City = "Oakland" })
        // downstream calendar/setlist state
        Want.equal
          baseHash
          (Musync.Calendar.contentHash {
            makeConcert () with
                CalendarSequence = 9
                SetlistAttempts = 5
          })
    ]

    // ── MIME ─────────────────────────────────────────────────────────────────
    testCase "MIME calendar part is text/calendar;method=REQUEST and re-parses"
    <| fun _ ->
      use message =
        Musync.Calendar.buildMessage (makeEnriched ()) fromAddress userAddress

      use ms = new MemoryStream()
      message.WriteTo ms
      ms.Position <- 0L
      let reparsed = MimeMessage.Load ms

      // From = musync send address; To = the user's mailbox (recipient split).
      Want.equal fromAddress (reparsed.From.Mailboxes |> Seq.head).Address
      Want.equal userAddress (reparsed.To.Mailboxes |> Seq.head).Address

      match findCalendarPart reparsed.Body with
      | None -> failtest "no text/calendar part found"
      | Some part ->
        Want.equal "text/calendar" part.ContentType.MimeType
        Want.equal "REQUEST" (part.ContentType.Parameters.["method"])
        let _, evt = firstEvent part.Text
        Want.equal expectedUid evt.Uid
        Want.equal "Puscifer @ Golden Gate Theatre" evt.Summary

    // ── SMTP send against a loopback fake sink (netDumbster) ──────────────────
    testCase "EmailSender delivers the MIME to a fake SMTP server"
    <| fun _ ->
      // Auto-bind a random free port (no TOCTOU race with the nudge fake-SMTP
      // test under Expecto's parallel runner).
      let server = SimpleSmtpServer.Start()

      try
        let smtp: SmtpConfig = {
          Host = "127.0.0.1"
          Port = server.Configuration.Port
          Username = "" // empty => EmailSender skips AUTH (the sink has none)
          Password = ""
          From = userAddress
          Security = ""
        }
        // The fake sink speaks plaintext, so override the (strict) transport
        // security that production would pick for this port.
        let sender = EmailSender(smtp, SecureSocketOptions.None)

        use message =
          Musync.Calendar.buildMessage (makeEnriched ()) fromAddress userAddress

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
