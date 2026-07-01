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
  /// Deterministic empty prediction. Placeholder until the Phase 4 ranking
  /// algorithm replaces the body; the TYPE stays as-is.
  let empty (computedAt: DateTimeOffset) : ProbableSetlist = {
    Songs = []
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
  // setlist
  ProbableSetlist: ProbableSetlist option
  ProbableSetlistComputedAt: DateTimeOffset option
  SetlistNotifiedAt: DateTimeOffset option
  SetlistFoundAt: DateTimeOffset option
  SetlistAttempts: int
  SetlistLastError: string option
  // timestamps
  CreatedAt: DateTimeOffset
  UpdatedAt: DateTimeOffset
}
