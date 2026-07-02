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

/// Map the relay's declared security to a MailKit transport mode, case-insensitive:
///   "TLS"/"SSL" -> implicit TLS on connect; "STARTTLS" -> in-band upgrade;
///   anything else -> Auto (MailKit negotiates from the port).
let secureSocketOptionsFor (security: string) : SecureSocketOptions =
  match
    (if isNull security then
       ""
     else
       security.Trim().ToLowerInvariant())
  with
  | "tls"
  | "ssl" -> SecureSocketOptions.SslOnConnect
  | "starttls" -> SecureSocketOptions.StartTls
  | _ -> SecureSocketOptions.Auto

/// SMTP sender. `securityOverride` exists ONLY as a test seam (a loopback fake
/// SMTP sink speaks plaintext); production constructs `EmailSender(cfg)` and gets
/// the security implied by `smtp.Security`.
type EmailSender(smtp: SmtpConfig, ?securityOverride: SecureSocketOptions) =
  let security = defaultArg securityOverride (secureSocketOptionsFor smtp.Security)

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
