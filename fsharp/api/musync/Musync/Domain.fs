namespace Musync.Domain

open System
open Validus
open Musync.Errors

/// Bridges Validus' `ValidationErrors` channel onto the app-wide `MusyncError`.
/// Kept internal so smart constructors below can share one mapping.
[<AutoOpen>]
module internal Validation =
  let toMusyncError (result: Result<'a, ValidationErrors>) : Result<'a, MusyncError> =
    result |> Result.mapError (ValidationErrors.toList >> ValidationError)

// ── Validated primitives (Pattern B: private single-case DUs) ────────────────
// The constructor is private, so a value can only exist by passing through
// `create`, which runs Validus validation. `value` is the read accessor.

/// A Songkick event identifier. Non-empty, trimmed.
type SongkickUid = private SongkickUid of string

module SongkickUid =
  let create (input: string) : Result<SongkickUid, MusyncError> =
    validate {
      let trimmed = if isNull input then "" else input.Trim()
      let! value = Check.String.notEmpty "songkick_uid" trimmed
      return SongkickUid value
    }
    |> toMusyncError

  let value (SongkickUid v) = v

/// A performing artist's name. Non-empty, trimmed.
type ArtistName = private ArtistName of string

module ArtistName =
  let create (input: string) : Result<ArtistName, MusyncError> =
    validate {
      let trimmed = if isNull input then "" else input.Trim()
      let! value = Check.String.notEmpty "artist" trimmed
      return ArtistName value
    }
    |> toMusyncError

  let value (ArtistName v) = v

/// The user's RSVP intent for a show. The ingest pipeline only *persists*
/// `Going` (fail-closed — see Adapters.Songkick), but `Interested` is modeled so
/// downstream reads/round-trips of the `plan_status` column stay total.
type PlanStatus =
  | Going
  | Interested

module PlanStatus =
  /// Wire form written to `concerts.plan_status` (lowercase, stable).
  let serialize (status: PlanStatus) : string =
    match status with
    | Going -> "going"
    | Interested -> "interested"

  /// Total parse of the `plan_status` column. Unknown values fail loud rather
  /// than defaulting, so a schema/data drift surfaces instead of silently
  /// coercing to `Going`.
  let parse (input: string) : Result<PlanStatus, MusyncError> =
    match (if isNull input then "" else input.Trim().ToLowerInvariant()) with
    | "going" -> Ok Going
    | "interested" -> Ok Interested
    | other -> Error(ValidationError [ $"unknown plan_status: '{other}'" ])

// ── Probable setlist (shared computation) ────────────────────────────────────
// These types are FINAL in Phase 1a; the ranking algorithm lands in Phase 4.
// They are reused later by the Setlist.fm assist and the YT playlist builder.

/// One predicted song within a probable setlist.
type PredictedSong = {
  Name: string
  /// How often the artist has recently played this song (higher = likelier).
  Frequency: int
  /// 1-based expected slot in the show, ordered by the ranking algorithm.
  Position: int
}

/// A ranked prediction of what an artist will play, with a compute timestamp.
type ProbableSetlist = {
  Songs: PredictedSong list
  ComputedAt: DateTimeOffset
}

module ProbableSetlist =
  /// Deterministic empty prediction (no tour history to rank). The TYPE is final;
  /// `fromSetlists` below is the real Phase 4 ranking.
  let empty (computedAt: DateTimeOffset) : ProbableSetlist = {
    Songs = []
    ComputedAt = computedAt
  }

  /// Per-song accumulator used only while ranking. `Display` is the first-seen
  /// raw spelling (stable in input order); `Key` is the case-folded match key.
  type private SongAgg = {
    Display: string
    Key: string
    /// Number of DISTINCT setlists the song appeared in (its frequency).
    Count: int
    /// Sum of the song's first-occurrence 0-based position across those setlists.
    PosSum: int
  }

  /// Rank songs across an artist's recent tour setlists into a probable setlist.
  ///
  /// Input: `setlists` — the recent shows, each an ORDERED list of song names
  /// (index 0 = opener). Output ordering:
  ///   1. play frequency, DESCENDING (how many setlists the song appears in);
  ///   2. tie-break: typical (mean first-occurrence) position, ASCENDING, so
  ///      equally-frequent songs keep their usual running order;
  ///   3. tie-break: display name, ORDINAL ascending — a total, deterministic key.
  /// `Position` is the 1-based slot in the resulting order; `Frequency` is the
  /// setlist count. A song repeated within ONE setlist counts once (its first
  /// position wins). PURE + deterministic: identical input -> identical output,
  /// no wall-clock or randomness (the only time input is the caller's timestamp).
  let fromSetlists
    (computedAt: DateTimeOffset)
    (setlists: string list list)
    : ProbableSetlist =
    // Collapse ONE setlist to its unique (key, display, firstPosition) triples,
    // preserving first-occurrence order and dropping empty names.
    let dedupeSetlist (songs: string list) : (string * string * int) list =
      songs
      |> List.mapi (fun pos name -> pos, (if isNull name then "" else name.Trim()))
      |> List.filter (fun (_, name) -> name <> "")
      |> List.fold
        (fun (seen: Set<string>, acc) (pos, name) ->
          let key = name.ToLowerInvariant()

          if Set.contains key seen then
            seen, acc
          else
            Set.add key seen, (key, name, pos) :: acc)
        (Set.empty, [])
      |> snd
      |> List.rev

    let aggregated =
      setlists
      |> List.collect dedupeSetlist
      |> List.fold
        (fun (m: Map<string, SongAgg>) (key, display, pos) ->
          match Map.tryFind key m with
          | Some agg ->
            Map.add
              key
              {
                agg with
                    Count = agg.Count + 1
                    PosSum = agg.PosSum + pos
              }
              m
          | None ->
            Map.add
              key
              {
                Display = display
                Key = key
                Count = 1
                PosSum = pos
              }
              m)
        Map.empty

    let songs =
      aggregated
      |> Map.toList
      |> List.map snd
      |> List.sortWith (fun a b ->
        let byFreq = compare b.Count a.Count // frequency DESC

        if byFreq <> 0 then
          byFreq
        else
          let meanA = float a.PosSum / float a.Count
          let meanB = float b.PosSum / float b.Count
          let byPos = compare meanA meanB // typical position ASC

          if byPos <> 0 then
            byPos
          else
            String.CompareOrdinal(a.Display, b.Display)) // name ASC (total order)
      |> List.mapi (fun i agg -> {
        Name = agg.Display
        Frequency = agg.Count
        Position = i + 1
      })

    {
      Songs = songs
      ComputedAt = computedAt
    }

// ── Concert aggregate ────────────────────────────────────────────────────────
// Maps 1:1 to the `concerts` table (see db/migrations). Nullable columns are
// `option`; timestamps are `DateTimeOffset`; counters are `int`.

type Concert = {
  // identity
  Id: Guid
  AccountId: string
  SongkickUid: SongkickUid
  // show
  Artist: ArtistName
  Venue: string
  City: string
  Country: string
  StartsAt: DateTimeOffset
  /// Venue-local IANA timezone (e.g. "America/Los_Angeles").
  Tz: string
  PlanStatus: PlanStatus
  // calendar
  CalendarUid: string option
  ContentHash: string option
  CalendarSequence: int
  CalendarSentAt: DateTimeOffset option
  CalendarAttempts: int
  CalendarLastError: string option
  /// Set-once on the calendar step's first failure; cleared on its next success.
  CalendarFirstFailedAt: DateTimeOffset option
  /// Stamped when the stuck-calendar escalation has been sent (one-shot dedupe).
  CalendarAlertedAt: DateTimeOffset option
  // setlist
  ProbableSetlist: ProbableSetlist option
  ProbableSetlistComputedAt: DateTimeOffset option
  SetlistNotifiedAt: DateTimeOffset option
  SetlistFoundAt: DateTimeOffset option
  SetlistAttempts: int
  SetlistLastError: string option
  /// Set-once on the setlist step's first failure; cleared on its next success.
  SetlistFirstFailedAt: DateTimeOffset option
  /// Stamped when the stuck-setlist escalation has been sent (one-shot dedupe).
  SetlistAlertedAt: DateTimeOffset option
  // timestamps
  CreatedAt: DateTimeOffset
  UpdatedAt: DateTimeOffset
}

// ── Virtual dead-letter queue ────────────────────────────────────────────────
// A concert's calendar/setlist steps self-heal on the next scheduled run, so a
// step is only "stuck" once it has been failing longer than the self-heal window
// AND is not yet done AND has not been alerted on. `listStuck` surfaces these;
// one `StuckItem` is emitted per (concert, failing step).

/// Which delivery step a concert is stuck on. Qualified access keeps the case
/// names from shadowing `Ical.Net.Calendar` where `Musync.Domain` is opened.
[<RequireQualifiedAccess>]
type StuckStep =
  | Calendar
  | Setlist

/// A concert step that has stayed stuck past the self-heal window and is awaiting
/// (or has just been chosen for) escalation.
type StuckItem = {
  ConcertId: Guid
  Artist: ArtistName
  Step: StuckStep
  LastError: string option
  FirstFailedAt: DateTimeOffset
}
