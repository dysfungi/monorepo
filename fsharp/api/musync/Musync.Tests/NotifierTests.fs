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

let private stuckItems: StuckItem list = [
  {
    ConcertId = Guid.NewGuid()
    Artist = ArtistName.create "Radiohead" |> Want.ok
    Step = StuckStep.Calendar
    LastError = Some "smtp timeout"
    FirstFailedAt = fixedNow
  }
  {
    ConcertId = Guid.NewGuid()
    Artist = ArtistName.create "The Beatles" |> Want.ok
    Step = StuckStep.Setlist
    LastError = None
    FirstFailedAt = fixedNow
  }
]

[<Tests>]
let notifierTests =
  testList "notifier (setlist nudge)" [
    // ── SMTP transport-security selection (pure) ─────────────────────────────
    testCase "secureSocketOptionsFor maps the declared security (case-insensitive)"
    <| fun _ ->
      Want.equal SecureSocketOptions.SslOnConnect (secureSocketOptionsFor "TLS")
      Want.equal SecureSocketOptions.SslOnConnect (secureSocketOptionsFor "ssl")
      Want.equal SecureSocketOptions.StartTls (secureSocketOptionsFor "STARTTLS")
      Want.equal SecureSocketOptions.Auto (secureSocketOptionsFor "")

    // ── stuck-alert message builder (pure) ───────────────────────────────────
    testCase "buildStuckAlertMessage: To = user, subject counts items, lists each"
    <| fun _ ->
      use msg = buildStuckAlertMessage fromAddress userEmail stuckItems
      Want.equal fromAddress (msg.From.Mailboxes |> Seq.head).Address
      Want.equal userEmail (msg.To.Mailboxes |> Seq.head).Address
      Want.equal true (msg.Subject.Contains "2 item(s) stuck")
      Want.equal true (msg.TextBody.Contains "Radiohead")
      Want.equal true (msg.TextBody.Contains "[calendar]")
      Want.equal true (msg.TextBody.Contains "smtp timeout")
      Want.equal true (msg.TextBody.Contains "The Beatles")
      Want.equal true (msg.TextBody.Contains "[setlist]")

    // ── stuck-alert delivery to a loopback fake SMTP sink ────────────────────
    testCase "SmtpNotifier delivers the stuck alert to the user via fake SMTP"
    <| fun _ ->
      let server = SimpleSmtpServer.Start()

      try
        let smtp: SmtpConfig = {
          Host = "127.0.0.1"
          Port = server.Configuration.Port
          Username = ""
          Password = ""
          From = fromAddress
          Security = ""
        }

        let sender = EmailSender(smtp, SecureSocketOptions.None)
        use message = buildStuckAlertMessage smtp.From userEmail stuckItems
        sender.Send message |> Async.RunSynchronously |> Want.isOk

        Threading.Thread.Sleep 250
        Want.equal 1 server.ReceivedEmailCount

        let raw = server.ReceivedEmail.[0].Data
        use ms = new MemoryStream(Encoding.UTF8.GetBytes raw)
        let parsed = MimeMessage.Load ms
        Want.equal userEmail (parsed.To.Mailboxes |> Seq.head).Address
        Want.equal true (parsed.TextBody.Contains "Radiohead")
      finally
        server.Stop()

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
          Security = ""
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
