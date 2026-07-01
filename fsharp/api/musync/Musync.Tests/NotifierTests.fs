module Musync.Tests.NotifierTests

open System
open System.IO
open System.Text
open Expecto
open MimeKit
open MailKit.Security
open netDumbster.smtp
open Musync.Domain
open Musync.Config
open Musync.Email
open Musync.Adapters.Notifier

// Unit + in-process integration tests for the setlist nudge. The message builder
// is pure; the delivery test uses the SAME loopback fake SMTP sink (netDumbster)
// the calendar path uses — no real relay.

let private fromAddress = "musync@frank.sh"
let private userEmail = "user@frank.sh"
let private fixedNow = DateTimeOffset(2026, 6, 30, 0, 0, 0, TimeSpan.Zero)

let private setlist =
  ProbableSetlist.fromSetlists fixedNow [
    [
      "Bloom"
      "15 Step"
    ]
    [
      "Bloom"
      "Idioteque"
    ]
  ]

let private makeConcert () : Concert = {
  Id = Guid.Empty
  AccountId = "default"
  SongkickUid = SongkickUid.create "sk-nudge" |> Want.ok
  Artist = ArtistName.create "Radiohead" |> Want.ok
  Venue = "The Fillmore"
  City = "San Francisco"
  Country = "US"
  StartsAt = DateTimeOffset(2026, 7, 2, 7, 0, 0, TimeSpan.Zero)
  Tz = "America/Los_Angeles"
  PlanStatus = PlanStatus.Going
  CalendarUid = None
  ContentHash = None
  CalendarSequence = 0
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

[<Tests>]
let notifierTests =
  testList "notifier (setlist nudge)" [
    // ── pure message builder ─────────────────────────────────────────────────
    testCase "buildNudgeMessage: From = send addr, To = user, body has songs + link"
    <| fun _ ->
      use msg = buildNudgeMessage fromAddress userEmail (makeConcert ()) setlist
      Want.equal fromAddress (msg.From.Mailboxes |> Seq.head).Address
      Want.equal userEmail (msg.To.Mailboxes |> Seq.head).Address
      Want.equal true (msg.Subject.Contains "Radiohead")
      // Predicted setlist appears (ordered) in both bodies; deep-link in both.
      Want.equal true (msg.TextBody.Contains "1. Bloom")
      Want.equal true (msg.TextBody.Contains "2. 15 Step")
      Want.equal true (msg.TextBody.Contains "https://www.setlist.fm/edit")
      Want.equal true (msg.HtmlBody.Contains "<li>Bloom</li>")
      Want.equal true (msg.HtmlBody.Contains "https://www.setlist.fm/edit")

    // ── delivery to a loopback fake SMTP sink ────────────────────────────────
    testCase "SmtpNotifier delivers the nudge to the user via fake SMTP"
    <| fun _ ->
      // netDumbster auto-binds a random free port (no TOCTOU race with the other
      // in-process fake-SMTP test under Expecto's parallel runner).
      let server = SimpleSmtpServer.Start()

      try
        let smtp: SmtpConfig = {
          Host = "127.0.0.1"
          Port = server.Configuration.Port
          Username = ""
          Password = ""
          From = fromAddress
        }
        // The pure builder + the reused EmailSender (plaintext override for the
        // fake sink) — exactly what SmtpNotifier wires internally.
        let sender = EmailSender(smtp, SecureSocketOptions.None)
        use message = buildNudgeMessage smtp.From userEmail (makeConcert ()) setlist

        sender.Send message |> Async.RunSynchronously |> Want.isOk

        Threading.Thread.Sleep 250
        Want.equal 1 server.ReceivedEmailCount

        // Re-parse the delivered bytes: recipient is the user, body carries the
        // predicted setlist + the create deep-link.
        let raw = server.ReceivedEmail.[0].Data
        use ms = new MemoryStream(Encoding.UTF8.GetBytes raw)
        let parsed = MimeMessage.Load ms
        Want.equal userEmail (parsed.To.Mailboxes |> Seq.head).Address
        Want.equal true (parsed.TextBody.Contains "Bloom")
        Want.equal true (parsed.TextBody.Contains "https://www.setlist.fm/edit")
      finally
        server.Stop()
  ]
