module Musync.Persistence

open System
open Npgsql
open Npgsql.FSharp
open Musync.Errors
open Musync.Domain

// Postgres is the source of truth. This module is the only writer/reader of the
// `concerts` table. All calls are UNPREPARED (Npgsql.FSharp's default `Sql.query`
// path) so they are safe behind a transaction-mode connection pool (e.g. pgbouncer)
// — prepared statements would break there. Mirrors AutoMate/Database.fs's
// `Sql.parameters` + `RowReader` style; exceptions are mapped onto the closed
// `MusyncError` channel so failures never leak Npgsql types across the port seam.

/// Convert a `postgres://user:pw@host:port/db?sslmode=...` URL (the `DATABASE_URL`
/// shape used by dbmate/compose) into an Npgsql key/value connection string.
/// WHY: Npgsql does not parse URI-form connection strings; dbmate (Go) does, so
/// the two tools share one env var but the F# side must translate.
let toConnectionString (databaseUrl: string) : string =
  let uri = Uri(databaseUrl)
  let userInfo = uri.UserInfo.Split(':')
  let username = Uri.UnescapeDataString(userInfo.[0])

  let password =
    if userInfo.Length > 1 then
      Uri.UnescapeDataString(userInfo.[1])
    else
      ""

  let builder = NpgsqlConnectionStringBuilder()
  builder.Host <- uri.Host
  builder.Port <- (if uri.Port <= 0 then 5432 else uri.Port)
  builder.Username <- username
  builder.Password <- password
  builder.Database <- uri.AbsolutePath.TrimStart('/')

  uri.Query.TrimStart('?').Split('&')
  |> Array.tryPick (fun kv ->
    match kv.Split('=') with
    | [| k; v |] when k.Equals("sslmode", StringComparison.OrdinalIgnoreCase) -> Some v
    | _ -> None)
  |> Option.iter (fun v ->
    // Qualify: `open Npgsql.FSharp` re-exports a `SslMode` that shadows the
    // `Npgsql.SslMode` the connection-string builder's property expects.
    match v.ToLowerInvariant() with
    | "disable" -> builder.SslMode <- Npgsql.SslMode.Disable
    | "allow" -> builder.SslMode <- Npgsql.SslMode.Allow
    | "prefer" -> builder.SslMode <- Npgsql.SslMode.Prefer
    | "require" -> builder.SslMode <- Npgsql.SslMode.Require
    | "verify-ca" -> builder.SslMode <- Npgsql.SslMode.VerifyCA
    | "verify-full" -> builder.SslMode <- Npgsql.SslMode.VerifyFull
    | _ -> ())

  builder.ConnectionString

/// A read projection of a `concerts` row. Intentionally NOT the domain `Concert`:
/// it surfaces the calendar/setlist *state* columns as raw scalars so tests can
/// assert the upsert never clobbers them, and reads `probable_setlist` as text
/// (cast in SQL) to avoid a JSON dependency in Phase 2.
type ConcertRow = {
  Id: Guid
  AccountId: string
  SongkickUid: string
  Artist: string
  Venue: string
  City: string
  Country: string
  StartsAt: DateTimeOffset
  Tz: string
  PlanStatus: string
  CalendarUid: string option
  ContentHash: string option
  CalendarSequence: int
  CalendarSentAt: DateTimeOffset option
  CalendarAttempts: int
  ProbableSetlist: string option
  SetlistAttempts: int
  CreatedAt: DateTimeOffset
  UpdatedAt: DateTimeOffset
}

let private readConcertRow (read: RowReader) : ConcertRow = {
  Id = read.uuid "id"
  AccountId = read.text "account_id"
  SongkickUid = read.text "songkick_uid"
  Artist = read.text "artist"
  Venue = read.text "venue"
  City = read.text "city"
  Country = read.text "country"
  StartsAt = read.datetimeOffset "starts_at"
  Tz = read.text "tz"
  PlanStatus = read.text "plan_status"
  CalendarUid = read.textOrNone "calendar_uid"
  ContentHash = read.textOrNone "content_hash"
  CalendarSequence = read.int "calendar_sequence"
  CalendarSentAt = read.datetimeOffsetOrNone "calendar_sent_at"
  CalendarAttempts = read.int "calendar_attempts"
  ProbableSetlist = read.textOrNone "probable_setlist"
  SetlistAttempts = read.int "setlist_attempts"
  CreatedAt = read.datetimeOffset "created_at"
  UpdatedAt = read.datetimeOffset "updated_at"
}

// jsonb is cast to ::text so the reader can pull it as a string without a JSON lib.
let private selectColumns =
  "SELECT id, account_id, songkick_uid, artist, venue, city, country, starts_at, tz, \
   plan_status, calendar_uid, content_hash, calendar_sequence, calendar_sent_at, \
   calendar_attempts, probable_setlist::text AS probable_setlist, setlist_attempts, \
   created_at, updated_at FROM concerts"

/// Upsert a concert keyed on `songkick_uid`. The `ON CONFLICT ... DO UPDATE` set
/// touches ONLY the show/plan columns (artist/venue/city/country/starts_at/tz/
/// plan_status/account_id). It deliberately omits every calendar_* and setlist_*
/// column plus content_hash, so re-ingesting an unchanged feed is idempotent and
/// never resets downstream delivery state. `updated_at` is refreshed by the table
/// trigger; `id`/`created_at` are DB-assigned and untouched on conflict.
let upsert (databaseUrl: string) (concert: Concert) : Result<unit, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "INSERT INTO concerts \
         (account_id, songkick_uid, artist, venue, city, country, starts_at, tz, plan_status) \
       VALUES \
         (@account_id, @songkick_uid, @artist, @venue, @city, @country, @starts_at, @tz, @plan_status) \
       ON CONFLICT (songkick_uid) DO UPDATE SET \
         account_id = EXCLUDED.account_id, \
         artist = EXCLUDED.artist, \
         venue = EXCLUDED.venue, \
         city = EXCLUDED.city, \
         country = EXCLUDED.country, \
         starts_at = EXCLUDED.starts_at, \
         tz = EXCLUDED.tz, \
         plan_status = EXCLUDED.plan_status ;"
    |> Sql.parameters [
      "@account_id", Sql.text concert.AccountId
      "@songkick_uid", Sql.text (SongkickUid.value concert.SongkickUid)
      "@artist", Sql.text (ArtistName.value concert.Artist)
      "@venue", Sql.text concert.Venue
      "@city", Sql.text concert.City
      "@country", Sql.text concert.Country
      "@starts_at", Sql.timestamptz concert.StartsAt
      "@tz", Sql.text concert.Tz
      "@plan_status", Sql.text (PlanStatus.serialize concert.PlanStatus)
    ]
    |> Sql.executeNonQuery
    |> ignore

    Ok()
  with ex ->
    Error(PersistenceError ex.Message)

/// Read a single concert by its Songkick UID (the natural key), or None.
let getBySongkickUid
  (databaseUrl: string)
  (songkickUid: string)
  : Result<ConcertRow option, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query (selectColumns + " WHERE songkick_uid = @songkick_uid ;")
    |> Sql.parameters [ "@songkick_uid", Sql.text songkickUid ]
    |> Sql.execute readConcertRow
    |> List.tryHead
    |> Ok
  with ex ->
    Error(PersistenceError ex.Message)

/// Read all concerts, soonest first.
let listConcerts (databaseUrl: string) : Result<ConcertRow list, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query (selectColumns + " ORDER BY starts_at ASC ;")
    |> Sql.execute readConcertRow
    |> Ok
  with ex ->
    Error(PersistenceError ex.Message)

/// Rehydrate a validated domain `Concert` from a raw row. Setlist fields are not
/// needed by the calendar path, so they carry `None`/defaults — the DB row is
/// untouched, this is only the transient in-memory value the calendar step reads.
/// Validation failure here means our own persisted data drifted; it fails loud on
/// the `MusyncError` channel rather than being silently coerced.
let toConcert (row: ConcertRow) : Result<Concert, MusyncError> =
  SongkickUid.create row.SongkickUid
  |> Result.bind (fun uid ->
    ArtistName.create row.Artist
    |> Result.bind (fun artist ->
      PlanStatus.parse row.PlanStatus
      |> Result.map (fun plan -> {
        Id = row.Id
        AccountId = row.AccountId
        SongkickUid = uid
        Artist = artist
        Venue = row.Venue
        City = row.City
        Country = row.Country
        StartsAt = row.StartsAt
        Tz = row.Tz
        PlanStatus = plan
        CalendarUid = row.CalendarUid
        ContentHash = row.ContentHash
        CalendarSequence = row.CalendarSequence
        CalendarSentAt = row.CalendarSentAt
        CalendarAttempts = row.CalendarAttempts
        CalendarLastError = None
        ProbableSetlist = None
        ProbableSetlistComputedAt = None
        SetlistNotifiedAt = None
        SetlistFoundAt = None
        SetlistAttempts = row.SetlistAttempts
        SetlistLastError = None
        CreatedAt = row.CreatedAt
        UpdatedAt = row.UpdatedAt
      })))

// ── Calendar state machine (Tx A / send / Tx B) ──────────────────────────────
// The invite send sits BETWEEN two transactions. The stable UID is the
// correctness boundary (same UID+SEQUENCE is idempotent in the user's calendar);
// `calendar_sent_at` is resend-SUPPRESSION only. So a crash between Tx A and Tx B
// leaves sent_at NULL and the NEXT run recomputes the same hash and resends the
// same UID+SEQUENCE — safe.

/// The Tx-A verdict: whether to (re)send, at which SEQUENCE, under which UID.
type CalendarDecision = {
  NeedsSend: bool
  Sequence: int
  Uid: string
}

/// Tx A (a single atomic UPDATE...RETURNING). Sets the stable `calendar_uid`
/// (once), stores the new `content_hash`, and:
///   • new-to-calendar (old hash NULL)      -> keep sequence (first send == 0)
///   • hash changed                          -> sequence++ and clear sent_at
///   • hash unchanged                        -> leave sequence + sent_at as-is
/// `NeedsSend` = "sent_at is NULL after the update", which is true for new/changed
/// rows AND for the crash-recovery case (unchanged hash but never delivered).
/// All CASE conditions read the OLD column values (single-statement UPDATE), so
/// the change test is evaluated before `content_hash` is overwritten.
let prepareCalendarInvite
  (databaseUrl: string)
  (id: Guid)
  (uid: string)
  (newHash: string)
  : Result<CalendarDecision, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         calendar_uid = COALESCE(calendar_uid, @uid), \
         content_hash = @hash, \
         calendar_sequence = CASE \
             WHEN content_hash IS NULL THEN calendar_sequence \
             WHEN content_hash <> @hash THEN calendar_sequence + 1 \
             ELSE calendar_sequence END, \
         calendar_sent_at = CASE \
             WHEN content_hash IS DISTINCT FROM @hash THEN NULL \
             ELSE calendar_sent_at END \
       WHERE id = @id \
       RETURNING calendar_sequence, calendar_uid, (calendar_sent_at IS NULL) AS needs_send ;"
    |> Sql.parameters [
      "@id", Sql.uuid id
      "@uid", Sql.text uid
      "@hash", Sql.text newHash
    ]
    |> Sql.execute (fun read -> {
      Sequence = read.int "calendar_sequence"
      Uid = read.text "calendar_uid"
      NeedsSend = read.bool "needs_send"
    })
    |> List.tryHead
    |> function
      | Some decision -> Ok decision
      | None ->
        Error(PersistenceError(sprintf "concert %O not found for calendar prepare" id))
  with ex ->
    Error(PersistenceError ex.Message)

/// Tx B (success): stamp `calendar_sent_at`, bump attempts, clear the last error.
let markCalendarSent
  (databaseUrl: string)
  (id: Guid)
  (now: DateTimeOffset)
  : Result<unit, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         calendar_sent_at = @now, \
         calendar_attempts = calendar_attempts + 1, \
         calendar_last_error = NULL \
       WHERE id = @id ;"
    |> Sql.parameters [
      "@now", Sql.timestamptz now
      "@id", Sql.uuid id
    ]
    |> Sql.executeNonQuery
    |> ignore

    Ok()
  with ex ->
    Error(PersistenceError ex.Message)

/// Tx B (failure): bump attempts and record the error. `calendar_sent_at` stays
/// NULL so the next run retries the SAME UID+SEQUENCE.
let recordCalendarError
  (databaseUrl: string)
  (id: Guid)
  (error: string)
  : Result<unit, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         calendar_attempts = calendar_attempts + 1, \
         calendar_last_error = @error \
       WHERE id = @id ;"
    |> Sql.parameters [
      "@error", Sql.text error
      "@id", Sql.uuid id
    ]
    |> Sql.executeNonQuery
    |> ignore

    Ok()
  with ex ->
    Error(PersistenceError ex.Message)
