module Musync.Persistence

open System
open System.Text.Json
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
  SongkickEventUrl: string option
  EventStartAt: DateTimeOffset option
  DoorsAt: DateTimeOffset option
  ShowAt: DateTimeOffset option
  /// Raw comma-joined opener names as stored; `toConcert` splits back to a list.
  Openers: string option
  TicketVendor: string option
  TicketUrl: string option
  EnrichedAt: DateTimeOffset option
  CalendarUid: string option
  ContentHash: string option
  CalendarSequence: int
  CalendarSentAt: DateTimeOffset option
  CalendarAttempts: int
  ProbableSetlist: string option
  ProbableSetlistComputedAt: DateTimeOffset option
  SetlistNotifiedAt: DateTimeOffset option
  SetlistFoundAt: DateTimeOffset option
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
  SongkickEventUrl = read.textOrNone "songkick_event_url"
  EventStartAt = read.datetimeOffsetOrNone "event_start_at"
  DoorsAt = read.datetimeOffsetOrNone "doors_at"
  ShowAt = read.datetimeOffsetOrNone "show_at"
  Openers = read.textOrNone "openers"
  TicketVendor = read.textOrNone "ticket_vendor"
  TicketUrl = read.textOrNone "ticket_url"
  EnrichedAt = read.datetimeOffsetOrNone "enriched_at"
  CalendarUid = read.textOrNone "calendar_uid"
  ContentHash = read.textOrNone "content_hash"
  CalendarSequence = read.int "calendar_sequence"
  CalendarSentAt = read.datetimeOffsetOrNone "calendar_sent_at"
  CalendarAttempts = read.int "calendar_attempts"
  ProbableSetlist = read.textOrNone "probable_setlist"
  ProbableSetlistComputedAt = read.datetimeOffsetOrNone "probable_setlist_computed_at"
  SetlistNotifiedAt = read.datetimeOffsetOrNone "setlist_notified_at"
  SetlistFoundAt = read.datetimeOffsetOrNone "setlist_found_at"
  SetlistAttempts = read.int "setlist_attempts"
  CreatedAt = read.datetimeOffset "created_at"
  UpdatedAt = read.datetimeOffset "updated_at"
}

// jsonb is cast to ::text so the reader can pull it as a string without a JSON lib.
let private selectColumns =
  "SELECT id, account_id, songkick_uid, artist, venue, city, country, starts_at, tz, \
   plan_status, songkick_event_url, event_start_at, doors_at, show_at, openers, \
   ticket_vendor, ticket_url, enriched_at, calendar_uid, content_hash, \
   calendar_sequence, calendar_sent_at, calendar_attempts, \
   probable_setlist::text AS probable_setlist, probable_setlist_computed_at, \
   setlist_notified_at, setlist_found_at, setlist_attempts, created_at, updated_at \
   FROM concerts"

/// Upsert a concert keyed on `songkick_uid`. The `ON CONFLICT ... DO UPDATE` set
/// touches ONLY the FEED columns (account_id/artist/venue/city/country/starts_at/
/// tz/plan_status/songkick_event_url). It deliberately omits every calendar_* and
/// setlist_* column plus content_hash, so re-ingesting an unchanged feed is
/// idempotent and never resets downstream delivery state.
///
/// CLOBBER-SAFETY for the enrichment columns (event_start_at/doors_at/show_at/
/// openers/ticket_vendor/ticket_url/enriched_at): they are NOT in the feed, so a
/// re-ingest must PRESERVE them — except when the show's MATERIAL IDENTITY moves,
/// where the stale scrape must be discarded and re-fetched. Identity here is
/// exactly what `Calendar.contentHash` keys on (artist, venue, show instant), so
/// the reset condition mirrors the resend trigger: a same-date venue relocation or
/// artist correction resends AND re-enriches, never resending stale doors/openers/
/// vendor for the old identity. content_hash itself is not reset here — the moved
/// identity already changes the hash, so the calendar state machine resends on its
/// own, and `tryEnrich` re-scrapes because enriched_at was cleared. `updated_at` is
/// refreshed by the table trigger; `id`/`created_at` are DB-assigned and untouched.
let upsert (databaseUrl: string) (concert: Concert) : Result<unit, MusyncError> =
  try
    // "The show's material identity moved" — the same (artist, venue, show instant)
    // triple `Calendar.contentHash` keys on. Reused by every enrichment-reset CASE.
    let identityMoved =
      "(concerts.artist, concerts.venue, concerts.starts_at) \
       IS DISTINCT FROM (EXCLUDED.artist, EXCLUDED.venue, EXCLUDED.starts_at)"

    // Each enrichment column is preserved unless the material identity moved.
    let keepUnlessMoved (column: string) =
      sprintf
        "%s = CASE WHEN %s THEN NULL ELSE concerts.%s END"
        column
        identityMoved
        column

    let sql =
      "INSERT INTO concerts \
         (account_id, songkick_uid, artist, venue, city, country, starts_at, tz, plan_status, \
          songkick_event_url) \
       VALUES \
         (@account_id, @songkick_uid, @artist, @venue, @city, @country, @starts_at, @tz, \
          @plan_status, @songkick_event_url) \
       ON CONFLICT (songkick_uid) DO UPDATE SET \
         account_id = EXCLUDED.account_id, \
         artist = EXCLUDED.artist, \
         venue = EXCLUDED.venue, \
         city = EXCLUDED.city, \
         country = EXCLUDED.country, \
         starts_at = EXCLUDED.starts_at, \
         tz = EXCLUDED.tz, \
         plan_status = EXCLUDED.plan_status, \
         songkick_event_url = EXCLUDED.songkick_event_url, "
      + ([
           "event_start_at"
           "doors_at"
           "show_at"
           "openers"
           "ticket_vendor"
           "ticket_url"
           "enriched_at"
         ]
         |> List.map keepUnlessMoved
         |> String.concat ", ")
      + " ;"

    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query sql
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
      "@songkick_event_url", Sql.textOrNone concert.SongkickEventUrl
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
      |> Result.map (fun plan ->
        let openers =
          match row.Openers with
          // Newline-delimited (see storeEnrichment) so an opener name may contain
          // commas without being split into two.
          | Some raw ->
            raw.Split('\n')
            |> Array.map (fun s -> s.Trim())
            |> Array.filter (fun s -> s <> "")
            |> Array.toList
          | None -> []

        let ticketVendor =
          row.TicketVendor
          |> Option.map (fun name -> {
            Name = name
            Url = row.TicketUrl |> Option.defaultValue ""
          })

        {
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
          SongkickEventUrl = row.SongkickEventUrl
          EventStartAt = row.EventStartAt
          DoorsAt = row.DoorsAt
          ShowAt = row.ShowAt
          Openers = openers
          TicketVendor = ticketVendor
          EnrichedAt = row.EnrichedAt
          CalendarUid = row.CalendarUid
          ContentHash = row.ContentHash
          CalendarSequence = row.CalendarSequence
          CalendarSentAt = row.CalendarSentAt
          CalendarAttempts = row.CalendarAttempts
          // DLQ bookkeeping is written + read via the dedicated stuck-item queries
          // below, never through this rehydrated value — so, like the *LastError
          // fields, it is not surfaced onto the calendar/setlist read path.
          CalendarLastError = None
          CalendarFirstFailedAt = None
          CalendarAlertedAt = None
          // The stored `probable_setlist` jsonb is recomputed each curate run, so the
          // rehydrated domain value carries None here; the *state* columns the curate
          // step branches on (notified/found/computed_at) ARE surfaced from the row.
          ProbableSetlist = None
          ProbableSetlistComputedAt = row.ProbableSetlistComputedAt
          SetlistNotifiedAt = row.SetlistNotifiedAt
          SetlistFoundAt = row.SetlistFoundAt
          SetlistAttempts = row.SetlistAttempts
          SetlistLastError = None
          SetlistFirstFailedAt = None
          SetlistAlertedAt = None
          CreatedAt = row.CreatedAt
          UpdatedAt = row.UpdatedAt
        })))

// ── Concert-page enrichment write path ───────────────────────────────────────
// Enrichment columns are NOT in the feed, so they are written only here (never by
// `upsert`, which merely preserves/resets them). The resolved `event_start_at`
// encodes the doors->show precedence once; the calendar owns the 19:00 fallback.

/// Persist one concert-page scrape: the resolved event start (doors if known, else
/// show), the raw doors/show instants, comma-joined openers, the ticket vendor, and
/// an `enriched_at` stamp. A later re-enrich (after a reschedule reset) overwrites
/// in place. Absent fields are stored NULL and later render "?".
let storeEnrichment
  (databaseUrl: string)
  (id: Guid)
  (enriched: EnrichedShow)
  (enrichedAt: DateTimeOffset)
  : Result<unit, MusyncError> =
  try
    let eventStart = enriched.DoorsAt |> Option.orElse enriched.ShowAt

    let openers =
      match enriched.Openers with
      // Newline-delimited so a comma inside an opener name survives the round-trip;
      // the calendar DESCRIPTION re-joins with ", " for display.
      | [] -> None
      | names -> Some(String.concat "\n" names)

    let vendorName = enriched.TicketVendor |> Option.map (fun t -> t.Name)

    let vendorUrl =
      enriched.TicketVendor
      |> Option.bind (fun t -> if t.Url = "" then None else Some t.Url)

    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         event_start_at = @event_start_at, \
         doors_at = @doors_at, \
         show_at = @show_at, \
         openers = @openers, \
         ticket_vendor = @ticket_vendor, \
         ticket_url = @ticket_url, \
         enriched_at = @enriched_at \
       WHERE id = @id ;"
    |> Sql.parameters [
      "@event_start_at", Sql.timestamptzOrNone eventStart
      "@doors_at", Sql.timestamptzOrNone enriched.DoorsAt
      "@show_at", Sql.timestamptzOrNone enriched.ShowAt
      "@openers", Sql.textOrNone openers
      "@ticket_vendor", Sql.textOrNone vendorName
      "@ticket_url", Sql.textOrNone vendorUrl
      "@enriched_at", Sql.timestamptz enrichedAt
      "@id", Sql.uuid id
    ]
    |> Sql.executeNonQuery
    |> ignore

    Ok()
  with ex ->
    Error(PersistenceError ex.Message)

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
         calendar_last_error = NULL, \
         calendar_first_failed_at = NULL, \
         calendar_alerted_at = NULL \
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
         calendar_last_error = @error, \
         calendar_first_failed_at = COALESCE(calendar_first_failed_at, now()) \
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

// ── Setlist state machine (Phase 4) ──────────────────────────────────────────
// Per-concert setlist columns. Recompute policy: every curate run (while not
// found) re-derives the `ProbableSetlist` and overwrites `probable_setlist` +
// `probable_setlist_computed_at`. `setlist_notified_at` is the nudge DEDUPE
// (set once, never re-nudge); `setlist_found_at` is TERMINAL (a confirmed
// Setlist.fm entry ends the loop — no more recompute/nudge). A false "found"
// would permanently suppress the nudge, which is why the existence check is
// deliberately fail-OPEN (see Adapters.Setlist).

/// Stable jsonb serialization of a `ProbableSetlist`. System.Text.Json emits
/// record properties in declaration order (Songs, then ComputedAt), so the same
/// prediction always serializes to byte-identical JSON — deterministic for tests
/// and for hash/diff stability. Written into the `probable_setlist` jsonb column.
let serializeSetlist (setlist: ProbableSetlist) : string =
  JsonSerializer.Serialize setlist

/// Inverse of `serializeSetlist`. Returns None on any parse failure rather than
/// throwing — a drifted/legacy jsonb value degrades to "no stored prediction"
/// instead of aborting a read (the curate loop recomputes regardless).
let tryDeserializeSetlist (json: string) : ProbableSetlist option =
  try
    Some(JsonSerializer.Deserialize<ProbableSetlist> json)
  with _ ->
    None

/// Concerts in the pre-show curate WINDOW: not yet found, starting between `now`
/// and `now + horizonDays`. Excludes past shows (`starts_at >= now`) and terminal
/// ones (`setlist_found_at IS NULL`). Soonest first.
let listCurateWindow
  (databaseUrl: string)
  (now: DateTimeOffset)
  (horizonDays: int)
  : Result<ConcertRow list, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query (
      selectColumns
      + " WHERE setlist_found_at IS NULL \
           AND starts_at >= @now AND starts_at <= @horizon \
         ORDER BY starts_at ASC ;"
    )
    |> Sql.parameters [
      "@now", Sql.timestamptz now
      "@horizon", Sql.timestamptz (now.AddDays(float horizonDays))
    ]
    |> Sql.execute readConcertRow
    |> Ok
  with ex ->
    Error(PersistenceError ex.Message)

/// Store (overwrite) the recomputed prediction + its compute timestamp. Casts the
/// serialized text to jsonb server-side.
let storeProbableSetlist
  (databaseUrl: string)
  (id: Guid)
  (setlistJson: string)
  (computedAt: DateTimeOffset)
  : Result<unit, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         probable_setlist = @setlist::jsonb, \
         probable_setlist_computed_at = @computed_at \
       WHERE id = @id ;"
    |> Sql.parameters [
      "@setlist", Sql.text setlistJson
      "@computed_at", Sql.timestamptz computedAt
      "@id", Sql.uuid id
    ]
    |> Sql.executeNonQuery
    |> ignore

    Ok()
  with ex ->
    Error(PersistenceError ex.Message)

/// Stamp `setlist_notified_at` (the nudge dedupe) and clear the last error. Set
/// ONCE after a nudge sends; a later run sees it non-NULL and never re-nudges.
let markSetlistNotified
  (databaseUrl: string)
  (id: Guid)
  (now: DateTimeOffset)
  : Result<unit, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         setlist_notified_at = @now, \
         setlist_attempts = setlist_attempts + 1, \
         setlist_last_error = NULL, \
         setlist_first_failed_at = NULL, \
         setlist_alerted_at = NULL \
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

/// Stamp `setlist_found_at` — TERMINAL. A confirmed Setlist.fm entry ends the
/// loop: `listCurateWindow` excludes the row thereafter, so it is never
/// recomputed or nudged again.
let markSetlistFound
  (databaseUrl: string)
  (id: Guid)
  (now: DateTimeOffset)
  : Result<unit, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         setlist_found_at = @now, \
         setlist_first_failed_at = NULL, \
         setlist_alerted_at = NULL \
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

/// Record a curate-step failure (prediction/notify): bump attempts + store the
/// error. Leaves notified/found untouched so the next run retries.
let recordSetlistError
  (databaseUrl: string)
  (id: Guid)
  (error: string)
  : Result<unit, MusyncError> =
  try
    toConnectionString databaseUrl
    |> Sql.connect
    |> Sql.query
      "UPDATE concerts SET \
         setlist_attempts = setlist_attempts + 1, \
         setlist_last_error = @error, \
         setlist_first_failed_at = COALESCE(setlist_first_failed_at, now()) \
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

// ── Virtual dead-letter queue ────────────────────────────────────────────────
// A step is "stuck" once its `*_first_failed_at` predates the self-heal window,
// the step is still not done, and it has not yet been alerted on. `listStuck`
// surfaces those (one row per failing step, so a doubly-stuck concert yields two);
// `markAlerted` stamps `*_alerted_at` so the next run does not re-escalate.

let private alertedColumn (step: StuckStep) : string =
  match step with
  | StuckStep.Calendar -> "calendar_alerted_at"
  | StuckStep.Setlist -> "setlist_alerted_at"

let private parseStuckStep (raw: string) : Result<StuckStep, MusyncError> =
  match raw with
  | "calendar" -> Ok StuckStep.Calendar
  | "setlist" -> Ok StuckStep.Setlist
  | other -> Error(PersistenceError(sprintf "unknown stuck step '%s'" other))

let private toStuckItem
  (id: Guid)
  (artist: string)
  (step: string)
  (lastError: string option)
  (firstFailedAt: DateTimeOffset)
  : Result<StuckItem, MusyncError> =
  ArtistName.create artist
  |> Result.bind (fun name ->
    parseStuckStep step
    |> Result.map (fun s -> {
      ConcertId = id
      Artist = name
      Step = s
      LastError = lastError
      FirstFailedAt = firstFailedAt
    }))

/// Steps stuck longer than 24h: `*_first_failed_at < now - 24h`, the step still
/// not done (calendar: `calendar_sent_at IS NULL`; setlist: `setlist_found_at IS
/// NULL`), and not yet alerted. Oldest failure first.
let listStuck
  (databaseUrl: string)
  (now: DateTimeOffset)
  : Result<StuckItem list, MusyncError> =
  try
    let raw =
      toConnectionString databaseUrl
      |> Sql.connect
      |> Sql.query
        "SELECT id, artist, 'calendar' AS step, calendar_last_error AS last_error, \
            calendar_first_failed_at AS first_failed_at \
         FROM concerts \
         WHERE calendar_first_failed_at < @cutoff \
           AND calendar_sent_at IS NULL \
           AND calendar_alerted_at IS NULL \
         UNION ALL \
         SELECT id, artist, 'setlist' AS step, setlist_last_error AS last_error, \
            setlist_first_failed_at AS first_failed_at \
         FROM concerts \
         WHERE setlist_first_failed_at < @cutoff \
           AND setlist_found_at IS NULL \
           AND setlist_alerted_at IS NULL \
         ORDER BY first_failed_at ASC ;"
      |> Sql.parameters [ "@cutoff", Sql.timestamptz (now.AddHours(-24.0)) ]
      |> Sql.execute (fun read ->
        read.uuid "id",
        read.text "artist",
        read.text "step",
        read.textOrNone "last_error",
        read.datetimeOffset "first_failed_at")

    (Ok [], raw)
    ||> List.fold (fun acc (id, artist, step, lastError, firstFailedAt) ->
      acc
      |> Result.bind (fun items ->
        toStuckItem id artist step lastError firstFailedAt
        |> Result.map (fun item -> item :: items)))
    |> Result.map List.rev
  with ex ->
    Error(PersistenceError ex.Message)

/// Stamp `*_alerted_at = now` for each (concert, step) just escalated, so the next
/// run does not re-alert. Short-circuits on the first write failure.
let markAlerted
  (databaseUrl: string)
  (now: DateTimeOffset)
  (items: StuckItem list)
  : Result<unit, MusyncError> =
  try
    let connStr = toConnectionString databaseUrl

    (Ok(), items)
    ||> List.fold (fun acc item ->
      acc
      |> Result.map (fun () ->
        connStr
        |> Sql.connect
        |> Sql.query (
          sprintf
            "UPDATE concerts SET %s = @now WHERE id = @id ;"
            (alertedColumn item.Step)
        )
        |> Sql.parameters [
          "@now", Sql.timestamptz now
          "@id", Sql.uuid item.ConcertId
        ]
        |> Sql.executeNonQuery
        |> ignore))
  with ex ->
    Error(PersistenceError ex.Message)
