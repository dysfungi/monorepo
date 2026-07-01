module Musync.Adapters.Setlist

open System
open System.Text.Json
open FsHttp
open Musync.Errors
open Musync.Domain
open Musync.Ports

// Setlist.fm `ISetlistProvider`. Two responsibilities:
//   • PredictSetlist — resolve the artist's MBID, pull recent tour setlists, and
//     rank them into a shared `ProbableSetlist` (Domain.fromSetlists).
//   • SetlistExists  — has the user's show already been logged on Setlist.fm?
//
// The parse/rank/match core is PURE (parseArtistSetlists / parseArtistSearch /
// rankSetlists / matchesConcert) so tests drive it with recorded JSON fixtures
// and never touch the network. The adapter shell adds only HTTP + the API key.
//
// FAIL-OPEN (opposite of the calendar's fail-closed): `SetlistExists` declares
// "exists" ONLY on a confident match (artist AND same eventDate AND venue/city
// agreement). Anything ambiguous — no match, a parse failure, a 404, a network
// error — resolves to `false`, i.e. "missing -> nudge". A false "exists" would
// stamp `setlist_found_at` (terminal) and permanently suppress the nudge, so the
// safe direction is to nudge.
//
// Setlist.fm REST: base https://api.setlist.fm/rest/1.0/, `x-api-key` header,
// `Accept: application/json`. Dates are `dd-MM-yyyy`. Standard tier is rate-
// limited to 2 req/sec, 1440 req/day (429 over) — the daily curate run makes a
// bounded 2 calls per in-window concert, well under the cap.

let private baseUrl = "https://api.setlist.fm/rest/1.0/"

/// The setlist.fm WEBSITE "add a setlist" page. Query-param PREFILL (artist /
/// date / venue) is NOT supported by setlist.fm — the create form is filled
/// interactively — so this degrades to the bare editor URL. The predicted
/// setlist + show details travel in the nudge email BODY instead. `concert` is
/// unused today but kept in the signature for a future prefill upgrade.
let createSetlistUrl (_concert: Concert) : string = "https://www.setlist.fm/edit"

// ── Pure JSON model + parsing (System.Text.Json DOM) ─────────────────────────
// DOM traversal (not typed deserialization) because the payload is deeply
// optional and setlist.fm's XML->JSON layer collapses a SINGLE-element array
// into a bare object (`setlist`, `set`, `song`, `artist`). `asArray` normalizes
// both shapes so the parse is robust to result counts.

/// A recorded Setlist.fm setlist, flattened to just what musync needs.
type ParsedSetlist = {
  Id: string
  /// As returned: `dd-MM-yyyy`.
  EventDate: string
  ArtistMbid: string
  ArtistName: string
  VenueName: string
  City: string
  CountryCode: string
  /// Song names in show order, flattened across every set (main + encores).
  Songs: string list
}

let private tryProp (el: JsonElement) (name: string) : JsonElement option =
  if el.ValueKind = JsonValueKind.Object then
    match el.TryGetProperty name with
    | true, v -> Some v
    | _ -> None
  else
    None

let private strProp (el: JsonElement) (name: string) : string =
  match tryProp el name with
  | Some v when v.ValueKind = JsonValueKind.String -> v.GetString()
  | _ -> ""

/// Normalize an element that may be an array, a single object (setlist.fm's
/// one-element quirk), or absent, into a list of elements.
let private asArray (elOpt: JsonElement option) : JsonElement list =
  match elOpt with
  | None -> []
  | Some el ->
    match el.ValueKind with
    | JsonValueKind.Array -> [ for x in el.EnumerateArray() -> x ]
    | JsonValueKind.Object -> [ el ]
    | _ -> []

let private parseSetlistEl (el: JsonElement) : ParsedSetlist =
  let artist = tryProp el "artist"
  let venue = tryProp el "venue"
  let city = venue |> Option.bind (fun v -> tryProp v "city")
  let country = city |> Option.bind (fun c -> tryProp c "country")

  let songs =
    tryProp el "sets"
    |> fun sets -> asArray (sets |> Option.bind (fun s -> tryProp s "set"))
    |> List.collect (fun s -> asArray (tryProp s "song"))
    |> List.map (fun song -> (strProp song "name").Trim())
    |> List.filter (fun n -> n <> "")

  {
    Id = strProp el "id"
    EventDate = strProp el "eventDate"
    ArtistMbid =
      artist |> Option.map (fun a -> strProp a "mbid") |> Option.defaultValue ""
    ArtistName =
      artist |> Option.map (fun a -> strProp a "name") |> Option.defaultValue ""
    VenueName =
      venue |> Option.map (fun v -> strProp v "name") |> Option.defaultValue ""
    City = city |> Option.map (fun c -> strProp c "name") |> Option.defaultValue ""
    CountryCode =
      country |> Option.map (fun c -> strProp c "code") |> Option.defaultValue ""
    Songs = songs
  }

/// Parse an artist-setlists (or search-setlists) response into `ParsedSetlist`s.
/// A `total:0` / absent `setlist` yields `Ok []`. Malformed JSON -> `SetlistError`
/// (the caller decides how to fail; `SetlistExists` treats it as fail-open).
let parseArtistSetlists (json: string) : Result<ParsedSetlist list, MusyncError> =
  try
    use doc = JsonDocument.Parse json
    asArray (tryProp doc.RootElement "setlist") |> List.map parseSetlistEl |> Ok
  with ex ->
    Error(SetlistError(sprintf "failed to parse setlist.fm setlists: %s" ex.Message))

/// Parse a `/search/artists` response into (mbid, name) pairs, best match first
/// (the API already sorts by relevance). Entries without an MBID are dropped.
let parseArtistSearch (json: string) : Result<(string * string) list, MusyncError> =
  try
    use doc = JsonDocument.Parse json

    asArray (tryProp doc.RootElement "artist")
    |> List.map (fun a -> strProp a "mbid", strProp a "name")
    |> List.filter (fun (mbid, _) -> mbid <> "")
    |> Ok
  with ex ->
    Error(SetlistError(sprintf "failed to parse setlist.fm artists: %s" ex.Message))

/// Rank recent setlists into a probable setlist (shared Domain computation).
let rankSetlists
  (computedAt: DateTimeOffset)
  (setlists: ParsedSetlist list)
  : ProbableSetlist =
  setlists
  |> List.map (fun s -> s.Songs)
  |> ProbableSetlist.fromSetlists computedAt

// ── Confident-match (existence check) ────────────────────────────────────────

/// Case-fold + strip non-alphanumerics for fuzzy string agreement.
let private norm (s: string) : string =
  if isNull s then
    ""
  else
    s
    |> Seq.filter Char.IsLetterOrDigit
    |> Seq.toArray
    |> String
    |> (fun x -> x.ToLowerInvariant())

/// The concert's venue-local show date rendered as Setlist.fm's `dd-MM-yyyy`.
/// Mirrors `Calendar.localYmd`: Songkick gives a date-only show, so the canonical
/// date is the venue-local calendar day; an unknown tz falls back to UTC.
let eventDateFor (concert: Concert) : string =
  let local =
    try
      let zone = TimeZoneInfo.FindSystemTimeZoneById concert.Tz
      TimeZoneInfo.ConvertTime(concert.StartsAt, zone)
    with _ ->
      concert.StartsAt.ToUniversalTime()

  sprintf "%02d-%02d-%04d" local.Day local.Month local.Year

/// Confident match between a concert and a recorded setlist. TRUE requires ALL:
///   • same event date (venue-local dd-MM-yyyy);
///   • artist agreement — normalized equality OR a containment (strong fuzzy,
///     e.g. "The Beatles" ⊇ "Beatles");
///   • place agreement — normalized venue OR city equality.
/// Any weaker overlap is NOT confident -> false (fail-open -> nudge).
let matchesConcert (concert: Concert) (setlist: ParsedSetlist) : bool =
  let dateOk = eventDateFor concert = setlist.EventDate

  let artistOk =
    let a = norm (ArtistName.value concert.Artist)
    let b = norm setlist.ArtistName
    a <> "" && b <> "" && (a = b || a.Contains b || b.Contains a)

  let placeOk =
    let venueOk =
      norm concert.Venue <> "" && norm concert.Venue = norm setlist.VenueName

    let cityOk = norm concert.City <> "" && norm concert.City = norm setlist.City
    venueOk || cityOk

  dateOk && artistOk && placeOk

// ── Adapter shell ────────────────────────────────────────────────────────────

let private warn (msg: string) =
  eprintfn "[musync] WARN setlist: %s" msg

/// `ISetlistProvider` backed by the Setlist.fm REST API. `now` is injectable so
/// the prediction's `ComputedAt` is deterministic under test; production uses the
/// wall clock. Sync FsHttp calls are wrapped in `async` (matching Songkick).
type SetlistFmProvider(apiKey: string, ?now: unit -> DateTimeOffset) =
  let clock = defaultArg now (fun () -> DateTimeOffset.UtcNow)

  let getJson (url: string) (queryParams: (string * string) list) : string =
    http {
      GET url
      query queryParams
      header "x-api-key" apiKey
      Accept "application/json"
    }
    |> Request.send
    |> Response.toText

  interface ISetlistProvider with
    member _.PredictSetlist(artist) =
      async {
        try
          let name = ArtistName.value artist

          // 1. resolve the artist's MBID (best relevance match).
          let searchJson =
            getJson (baseUrl + "search/artists") [
              "artistName", name
              "sort", "relevance"
            ]

          match parseArtistSearch searchJson with
          | Error err -> return Error err
          | Ok [] ->
            // Unknown artist / no tour history — an empty (but valid) prediction.
            return Ok(ProbableSetlist.empty (clock ()))
          | Ok((mbid, _) :: _) ->
            // 2. pull recent setlists for that MBID and rank them.
            let setlistsJson = getJson (baseUrl + "artist/" + mbid + "/setlists") []

            match parseArtistSetlists setlistsJson with
            | Ok setlists -> return Ok(rankSetlists (clock ()) setlists)
            | Error err -> return Error err
        with ex ->
          return Error(SetlistError(sprintf "predict failed: %s" ex.Message))
      }

    member _.SetlistExists(concert) =
      async {
        // Fail-open everywhere: a confident match is the ONLY path to `true`.
        try
          let name = ArtistName.value concert.Artist
          let date = eventDateFor concert

          let json =
            getJson (baseUrl + "search/setlists") [
              "artistName", name
              "date", date
            ]

          match parseArtistSetlists json with
          | Ok setlists -> return Ok(setlists |> List.exists (matchesConcert concert))
          | Error err ->
            // Parse-uncertain -> treat as missing (nudge), don't abort the run.
            warn (sprintf "existence parse failed for '%s' (%s): %A" name date err)
            return Ok false
        with ex ->
          warn (sprintf "existence check errored (fail-open -> nudge): %s" ex.Message)
          return Ok false
      }
