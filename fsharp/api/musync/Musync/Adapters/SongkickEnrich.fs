module Musync.Adapters.SongkickEnrich

open System
open System.Globalization
open System.Text.Json
open System.Text.RegularExpressions
open FsHttp
open Musync.Errors
open Musync.Domain
open Musync.Ports

// Enriches a concert from its Songkick page. The page embeds a schema.org
// MusicEvent as a `<script type="application/ld+json">` block (a top-level JSON
// ARRAY holding the event), which is far more robust than scraping the rendered
// HTML. `parseConcertPage` is PURE so tests drive it from a captured fixture and
// never touch the network; `SongkickEnricher` is the thin FsHttp fetch on top.
//
// TOS / BRITTLENESS: this scrapes Songkick (now Suno-owned) under its own terms,
// distinct from the Setlist.fm API. The JSON-LD shape is undocumented and can
// change without notice — re-verify at live-apply, and treat every field as
// best-effort (a missing field stays None/empty and renders "?" on the event).
//
// Reality of the real feed (verified 2026): `startDate` is a naive wall-clock with
// NO timezone offset, so we interpret it in the venue's IANA zone (passed in).
// `doorTime`, openers, and a ticket `seller` are frequently ABSENT — those cases
// yield None by design.

let private jsonLdBlocks =
  Regex(
    """<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>""",
    RegexOptions.Singleline ||| RegexOptions.IgnoreCase
  )

let private tryString (element: JsonElement) (name: string) : string option =
  match element.TryGetProperty name with
  | true, v when v.ValueKind = JsonValueKind.String ->
    match v.GetString() with
    | null -> None
    | s when s.Trim() = "" -> None
    | s -> Some(s.Trim())
  | _ -> None

/// Interpret a naive `yyyy-MM-ddTHH:mm:ss` wall-clock string in the venue's IANA
/// zone. Songkick omits the offset, so the venue zone is the only correct source;
/// an unknown zone id falls back to a UTC reading (matching Songkick.resolveStart).
let private wallTimeInZone (venueTz: string) (raw: string) : DateTimeOffset option =
  match
    DateTime.TryParse(
      raw,
      CultureInfo.InvariantCulture,
      DateTimeStyles.NoCurrentDateDefault
    )
  with
  | true, parsed ->
    let wall = DateTime.SpecifyKind(parsed, DateTimeKind.Unspecified)

    try
      let zone = TimeZoneInfo.FindSystemTimeZoneById venueTz
      Some(DateTimeOffset(wall, zone.GetUtcOffset wall))
    with _ ->
      Some(DateTimeOffset(DateTime.SpecifyKind(wall, DateTimeKind.Utc)))
  | _ -> None

/// The performers array is headliner-first (Songkick convention), so every entry
/// AFTER the first is a support act. A single performer => no openers.
let private extractOpeners (event: JsonElement) : string list =
  match event.TryGetProperty "performer" with
  | true, p when p.ValueKind = JsonValueKind.Array ->
    p.EnumerateArray()
    |> Seq.toList
    |> function
      | [] -> []
      // Drop the headliner by POSITION (whether or not it has a parseable name),
      // then read the remaining support acts' names.
      | _headliner :: supports -> supports |> List.choose (fun e -> tryString e "name")
  | _ -> []

/// The first offer that names a real seller (or, failing that, the offer itself)
/// becomes the ticket vendor. The real feed usually carries a self-referential
/// Songkick offer with no seller — that yields None.
let private extractTicketVendor (event: JsonElement) : TicketVendor option =
  let offers =
    match event.TryGetProperty "offers" with
    | true, o when o.ValueKind = JsonValueKind.Array -> o.EnumerateArray() |> Seq.toList
    | true, o -> [ o ]
    | _ -> []

  offers
  |> List.tryPick (fun offer ->
    let sellerName =
      match offer.TryGetProperty "seller" with
      | true, s -> tryString s "name"
      | _ -> None

    sellerName
    |> Option.orElse (tryString offer "name")
    |> Option.map (fun name -> {
      Name = name
      Url = tryString offer "url" |> Option.defaultValue ""
    }))

let private isMusicEvent (element: JsonElement) : bool =
  match element.TryGetProperty "@type" with
  | true, t when t.ValueKind = JsonValueKind.String -> t.GetString() = "MusicEvent"
  // schema.org permits a multi-type array, e.g. ["MusicEvent","Event"].
  | true, t when t.ValueKind = JsonValueKind.Array ->
    t.EnumerateArray()
    |> Seq.exists (fun e ->
      e.ValueKind = JsonValueKind.String && e.GetString() = "MusicEvent")
  | _ -> false

let private toEnriched (venueTz: string) (event: JsonElement) : EnrichedShow = {
  DoorsAt = tryString event "doorTime" |> Option.bind (wallTimeInZone venueTz)
  ShowAt = tryString event "startDate" |> Option.bind (wallTimeInZone venueTz)
  Openers = extractOpeners event
  TicketVendor = extractTicketVendor event
}

/// Parse one Songkick concert page into an `EnrichedShow`. Scans every JSON-LD
/// block, picks the first `MusicEvent`, and reads it in the venue's zone. Returns
/// `SourceError` when no MusicEvent block is present (a page shape change).
let parseConcertPage
  (venueTz: string)
  (html: string)
  : Result<EnrichedShow, MusyncError> =
  let fromBlock (json: string) : EnrichedShow option =
    try
      use doc = JsonDocument.Parse json

      let candidates =
        match doc.RootElement.ValueKind with
        | JsonValueKind.Array -> doc.RootElement.EnumerateArray() |> Seq.toList
        | _ -> [ doc.RootElement ]

      candidates |> List.tryFind isMusicEvent |> Option.map (toEnriched venueTz)
    with _ ->
      None

  jsonLdBlocks.Matches html
  |> Seq.cast<Match>
  |> Seq.tryPick (fun m -> fromBlock m.Groups.[1].Value)
  |> function
    | Some enriched -> Ok enriched
    | None ->
      Error(SourceError "no schema.org MusicEvent JSON-LD found on concert page")

/// `IShowEnricher` adapter: fetch the concert page and parse it. A concert with no
/// captured page URL, a network failure, or a shape change all land on the error
/// channel — the caller treats enrichment as best-effort and sends "?" defaults.
type SongkickEnricher() =
  interface IShowEnricher with
    member _.Enrich(concert: Concert) =
      async {
        match concert.SongkickEventUrl with
        | None -> return Error(SourceError "concert has no Songkick page URL to enrich")
        | Some url ->
          return
            try
              http { GET url }
              |> Request.send
              |> Response.toText
              |> parseConcertPage concert.Tz
            with ex ->
              Error(SourceError $"failed to fetch Songkick concert page: {ex.Message}")
      }
