module Musync.Email

open System
open MailKit.Net.Smtp
open MailKit.Security
open MimeKit
open Musync.Config

// Reusable SMTP sender (MailKit). Deliberately NOT specific to the calendar
// path: Phase 4's `INotifier` (setlist nudges) sends through the same component.
// It knows nothing about musync's error DU — it returns `Result<unit, string>`
// so each port (ICalendarTarget -> CalendarError, INotifier -> NotifyError) maps
// the raw message onto its own case at the seam.

/// Choose transport security from the port, matching real relays:
///   465 -> implicit TLS (SSL on connect); 587 (and anything else) -> STARTTLS.
/// STARTTLS is REQUIRED (not "when available") so a relay that fails to offer it
/// fails loud rather than silently sending in cleartext.
let private securityForPort (port: int) : SecureSocketOptions =
  if port = 465 then
    SecureSocketOptions.SslOnConnect
  else
    SecureSocketOptions.StartTls

/// SMTP sender. `securityOverride` exists ONLY as a test seam (a loopback fake
/// SMTP sink speaks plaintext); production constructs `EmailSender(cfg)` and gets
/// the strict port-based choice above.
type EmailSender(smtp: SmtpConfig, ?securityOverride: SecureSocketOptions) =
  let security = defaultArg securityOverride (securityForPort smtp.Port)

  /// Send a prepared message. Any MailKit/socket failure is caught and returned
  /// on the error channel (as its message) rather than thrown across the seam.
  member _.Send(message: MimeMessage) : Async<Result<unit, string>> =
    async {
      try
        use client = new SmtpClient()
        do! client.ConnectAsync(smtp.Host, smtp.Port, security) |> Async.AwaitTask

        // An empty username means "no auth" (used by the loopback test sink).
        if not (String.IsNullOrEmpty smtp.Username) then
          do! client.AuthenticateAsync(smtp.Username, smtp.Password) |> Async.AwaitTask

        // SendAsync returns the SMTP server's response string; discard it.
        let! _ = client.SendAsync message |> Async.AwaitTask
        do! client.DisconnectAsync true |> Async.AwaitTask
        return Ok()
      with ex ->
        return Error ex.Message
    }
