module Musync.Adapters.Songkick

open System
open System.Text.RegularExpressions
open Ical.Net
open Ical.Net.CalendarComponents
open Ical.Net.DataTypes
open FsHttp
open Musync.Errors
open Musync.Domain
open Musync.Ports

// Songkick per-user attendance feed:
//   https://www.songkick.com/users/<user>/calendars.ics?filter=attendance[&key=...]
// The feed mixes BOTH "Going" and "Interested" events. This adapter is the
// INBOUND port implementation: it fetches the ICS and turns it into `Concert`s.
//
// Fail-closed: only events CONFIRMED "Going" become concerts. An "Interested"
// event is skipped; an event whose intent is indeterminate is skipped AND warned.
// A wrongly-invited show is worse than a missed one, so ambiguity never emits.
//
// The parse is a PURE function (`parseIcs`) so tests drive it with a fixture and
// never touch the network. Ical.Net does the RFC-5545 heavy lifting (line
// unfolding, property/escape handling, multi-VEVENT); we compute instants
// ourselves via `TimeZoneInfo` so the timezone logic is deterministic and unit-
// testable rather than depending on Ical.Net's VTIMEZONE resolution.

/// The three RSVP states we can infer from a VEVENT. Only `Going` is persisted.
type private Rsvp =
  | Going
  | Interested
  | Indeterminate

let private warn (msg: string) =
  eprintfn "[musync] WARN songkick: %s" msg

// ── Going/Interested discriminator ───────────────────────────────────────────
// CONFIRMED against a real live-feed consumer (jayme-github/songkick-calendar):
// a "Going" VEVENT's DESCRIPTION begins with "You’re going" (note the Unicode
// right-single-quote U+2019, not ASCII '). Everything else is Interested. We
// normalize the apostrophe and lowercase so both apostrophe forms match.
// NOTE (verify at live-apply): the exact "Interested" DESCRIPTION text is not
// publicly confirmed; classification is by NEGATION of the Going prefix, which
// is the safe (fail-closed) direction regardless of the interested wording.
let private goingPrefix = "you're going"

let private classify (description: string) : Rsvp =
  if isNull description then
    Indeterminate
  else
    let normalized = description.Replace('’', '\'').TrimStart().ToLowerInvariant()

    if normalized.StartsWith(goingPrefix) then Going
    elif normalized.Length > 0 then Interested
    else Indeterminate

// ── Field extraction ─────────────────────────────────────────────────────────
// SUMMARY shape: "<Artist> at <Venue> (<date>)". Strip the trailing "(date)",
// split on the first " at ", drop any " with <support acts>" from the artist.
let private stripTrailingParen (s: string) =
  Regex.Replace(s, @"\s*\([^)]*\)\s*$", "").Trim()

let private parseSummary (summary: string) : string * string =
  let cleaned = stripTrailingParen (if isNull summary then "" else summary)
  let idx = cleaned.IndexOf(" at ", StringComparison.Ordinal)

  if idx < 0 then
    cleaned, ""
  else
    let artistPart = cleaned.Substring(0, idx)
    let venue = cleaned.Substring(idx + 4).Trim()
    // Drop support-act suffix ("Headliner with A and B") from the headliner.
    let withIdx = artistPart.IndexOf(" with ", StringComparison.Ordinal)

    let artist =
      (if withIdx < 0 then
         artistPart
       else
         artistPart.Substring(0, withIdx))
        .Trim()

    artist, venue

// LOCATION shape (best-effort; sub-structure unverified — flag for live-apply):
// "<Venue>, <City>, [<State>,] <CC>". First part = venue, last = 2-letter country,
// second = city when there are >= 3 parts.
let private parseLocation (location: string) : string option * string * string =
  if String.IsNullOrWhiteSpace location then
    None, "", ""
  else
    let parts =
      location.Split(',')
      |> Array.map (fun p -> p.Trim())
      |> Array.filter (fun p -> p.Length > 0)

    match parts.Length with
    | 0 -> None, "", ""
    | 1 -> Some parts.[0], "", ""
    | 2 -> Some parts.[0], "", parts.[1]
    | n -> Some parts.[0], parts.[1], parts.[n - 1]

// ── Venue → IANA timezone (best-effort seed map) ─────────────────────────────
// The real Songkick feed emits a bare, TZID-less DTSTART date, so for those
// events we must guess the venue-local zone. This is a small seed map covering
// common cases; anything unresolved falls back to UTC + WARN. Country fallback
// is intentionally omitted for the US (spans multiple zones — cannot guess).
// EXPAND at live-apply as real venues surface.
let private cityZones =
  dict [
    "san francisco", "America/Los_Angeles"
    "los angeles", "America/Los_Angeles"
    "seattle", "America/Los_Angeles"
    "new york", "America/New_York"
    "chicago", "America/Chicago"
    "london", "Europe/London"
    "berlin", "Europe/Berlin"
  ]

let private countryZones =
  dict [
    "GB", "Europe/London"
    "IE", "Europe/Dublin"
    "FR", "Europe/Paris"
    "DE", "Europe/Berlin"
    "ES", "Europe/Madrid"
    "NL", "Europe/Amsterdam"
  ]

let private resolveZone (city: string) (country: string) : string option =
  match cityZones.TryGetValue(city.Trim().ToLowerInvariant()) with
  | true, zone -> Some zone
  | _ ->
    match countryZones.TryGetValue(country.Trim().ToUpperInvariant()) with
    | true, zone -> Some zone
    | _ -> None

/// Interpret a wall-clock `DateTime` in the named IANA zone as an instant.
/// Returns None if the zone id is unknown on this host.
let private instantInZone (wall: DateTime) (zoneId: string) : DateTimeOffset option =
  try
    let tz = TimeZoneInfo.FindSystemTimeZoneById(zoneId)
    let unspecified = DateTime.SpecifyKind(wall, DateTimeKind.Unspecified)
    Some(DateTimeOffset(unspecified, tz.GetUtcOffset(unspecified)))
  with _ ->
    None

let private asUtcInstant (wall: DateTime) =
  DateTimeOffset(DateTime.SpecifyKind(wall, DateTimeKind.Utc))

/// Resolve (instant, venue-local tz) for a VEVENT's DTSTART. Three shapes:
///   1. explicit ;TZID=Zone  -> use that zone directly.
///   2. UTC (...Z)           -> instant is known; venue zone resolved best-effort.
///   3. floating date/time   -> resolve venue zone, else store UTC + WARN.
let private resolveStart
  (start: IDateTime)
  (city: string)
  (country: string)
  (label: string)
  =
  let wall = start.Value
  let tzId = start.TzId
  // Ical.Net tags a UTC (`...Z`) time with TzId="UTC" — that's NOT a venue-local
  // zone, so treat it like IsUtc: the instant is known, resolve the venue tz
  // separately. A non-empty, non-UTC TzId is a real venue zone (e.g. the feed's
  // ;TZID= form).
  let isUtc =
    start.IsUtc
    || (not (isNull tzId) && tzId.Equals("UTC", StringComparison.OrdinalIgnoreCase))

  let hasVenueTzId = (not (String.IsNullOrWhiteSpace tzId)) && not isUtc

  let resolvedVenueZone () =
    match resolveZone city country with
    | Some zone -> zone
    | None ->
      warn $"could not resolve venue tz for {label} ({city}, {country}); storing UTC"
      "UTC"

  if hasVenueTzId then
    match instantInZone wall tzId with
    | Some instant -> instant, tzId
    | None ->
      warn $"unknown TZID '{tzId}' for {label}; storing UTC"
      asUtcInstant wall, "UTC"
  elif isUtc then
    asUtcInstant wall, resolvedVenueZone ()
  else
    // Floating (Songkick's real bare-date shape): no zone, no time-of-day.
    match resolveZone city country with
    | Some zone ->
      match instantInZone wall zone with
      | Some instant -> instant, zone
      | None -> asUtcInstant wall, "UTC"
    | None ->
      warn $"could not resolve venue tz for {label} ({city}, {country}); storing UTC"
      asUtcInstant wall, "UTC"

// Songkick emits a bare `DTSTART:YYYYMMDD` WITHOUT the required `;VALUE=DATE`
// param — an RFC-5545 violation that trips strict parsers. Patch it to a proper
// date value before handing the text to Ical.Net (same fix the reference worker
// applies). Only bare 8-digit DTSTART/DTEND lines match; zoned/UTC lines don't.
let private normalizeBareDates (ics: string) =
  Regex.Replace(ics, @"(?m)^(DT(?:START|END)):(\d{8})\s*$", "$1;VALUE=DATE:$2")

/// Build a `Concert` from one Going VEVENT. Id/timestamps are DB-assigned, so
/// they carry deterministic placeholders here (Guid.Empty / MinValue) and are
/// ignored by `Persistence.upsert` — keeping `parseIcs` pure and deterministic.
let private toConcert (evt: CalendarEvent) : Result<Concert, MusyncError> =
  let artistText, summaryVenue = parseSummary evt.Summary
  let locVenue, city, country = parseLocation evt.Location
  let venue = locVenue |> Option.defaultValue summaryVenue

  let label =
    if String.IsNullOrWhiteSpace evt.Uid then
      artistText
    else
      evt.Uid

  let build uid artist =
    let instant, tz = resolveStart evt.Start city country label

    {
      Id = Guid.Empty
      AccountId = "default"
      SongkickUid = uid
      Artist = artist
      Venue = venue
      City = city
      Country = country
      StartsAt = instant
      Tz = tz
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

  SongkickUid.create evt.Uid
  |> Result.bind (fun uid -> ArtistName.create artistText |> Result.map (build uid))

/// Parse a Songkick attendance ICS into Going-only concerts. Total-feed parse
/// failures return `SourceError`; a single malformed/indeterminate event is
/// skipped (and warned) rather than failing the whole ingest.
let parseIcs (ics: string) : Result<Concert list, MusyncError> =
  try
    let calendar = Calendar.Load(normalizeBareDates ics)

    let concerts =
      calendar.Events
      |> Seq.choose (fun evt ->
        match classify evt.Description with
        | Interested -> None
        | Indeterminate ->
          warn $"indeterminate RSVP for event '{evt.Uid}' ('{evt.Summary}'); skipping"
          None
        | Going ->
          match toConcert evt with
          | Ok concert -> Some concert
          | Error err ->
            warn $"skipping Going event '{evt.Uid}' ('{evt.Summary}'): {err}"
            None)
      |> List.ofSeq

    Ok concerts
  with ex ->
    Error(SourceError $"failed to parse Songkick ICS: {ex.Message}")

/// `IShowSource` adapter. Fetches the ICS over HTTP (URL is a per-user secret
/// from Config) and delegates to the pure `parseIcs`. Network/parse failures
/// land on the `MusyncError` channel.
type SongkickShowSource(icsUrl: string) =
  interface IShowSource with
    member _.FetchGoingConcerts() =
      async {
        return
          try
            http { GET icsUrl } |> Request.send |> Response.toText |> parseIcs
          with ex ->
            Error(SourceError $"failed to fetch Songkick ICS: {ex.Message}")
      }
