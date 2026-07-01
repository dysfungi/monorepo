module Musync.Config

open FsConfig

// FsConfig maps nested records to prefixed env vars, e.g. `Smtp.Host` reads
// `SMTP_HOST` and `Smtp.Security` reads `SMTP_SECURITY`. The whole env surface is
// validated at startup — EnvConfig.Get fails loud on a missing var.

/// SMTP relay used both for iCal calendar invites and setlist nudges.
type SmtpConfig = {
  Host: string
  [<DefaultValue("587")>]
  Port: int
  Username: string
  Password: string
  /// The From address on outgoing mail. For Proton this MUST equal the
  /// authenticated username, so it is sourced from `SMTP_FROM` (= the username).
  From: string
  /// Transport security declared by the relay: "TLS"/"SSL" => implicit TLS on
  /// connect, "STARTTLS" => in-band upgrade, anything else => Auto.
  Security: string
}

type AppConfig = {
  /// Full Postgres connection URL (e.g. "postgres://user:pw@host:5432/musync_app").
  DatabaseUrl: string
  /// Songkick "Going" calendar ICS feed (secret; per-user).
  SongkickIcsUrl: string
  /// Setlist.fm API key (secret).
  SetlistFmApiKey: string
  /// The user's own mailbox (their Proton address). This is the RECIPIENT of
  /// everything musync delivers: the calendar self-invite's ATTENDEE + `To:` AND
  /// the pre-show setlist-nudge `To:`. `Smtp.From` stays the musync SEND address
  /// (ORGANIZER / `From:`). Reads env `USER_EMAIL` (compose maps the host's
  /// `MUSYNC_USER_EMAIL` onto it, mirroring the other `MUSYNC_*` vars).
  UserEmail: string
  Smtp: SmtpConfig
}

let load () =
  match EnvConfig.Get<AppConfig>() with
  | Ok config -> config
  | Error error ->
    match error with
    | NotFound envVarName -> failwith $"Environment variable {envVarName} not found"
    | BadValue(envVarName, value) ->
      failwith $"Environment variable {envVarName} has invalid value {value}"
    | NotSupported msg -> failwith msg
