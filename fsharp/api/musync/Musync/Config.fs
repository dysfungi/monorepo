module Musync.Config

open FsConfig

// FsConfig maps nested records to prefixed env vars, e.g. `Smtp.Host` reads
// `SMTP_HOST`, `Deadman.PollSongkickUrl` reads `DEADMAN_POLL_SONGKICK_URL`.
// Adapters that consume these arrive in later phases; the config is declared
// now so the MVP's env surface is fixed and validated at startup.

/// SMTP relay used both for iCal calendar invites and setlist nudges.
type SmtpConfig = {
  Host: string
  [<DefaultValue("587")>]
  Port: int
  Username: string
  Password: string
  /// The From address on outgoing mail (e.g. "musync@frank.sh").
  From: string
}

/// Deadman-switch ping URLs — one per scheduled command. Pinged after a
/// successful run so a missed run trips an external alert.
type DeadmanConfig = {
  PollSongkickUrl: string
  CuratePreshowUrl: string
}

type AppConfig = {
  /// Full Postgres connection URL (e.g. "postgres://user:pw@host:5432/musync_app").
  DatabaseUrl: string
  /// Songkick "Going" calendar ICS feed (secret; per-user).
  SongkickIcsUrl: string
  /// Setlist.fm API key (secret).
  SetlistFmApiKey: string
  Smtp: SmtpConfig
  Deadman: DeadmanConfig
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
