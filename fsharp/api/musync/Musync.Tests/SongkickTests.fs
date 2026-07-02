module Musync.Tests.SongkickTests

open System
open System.IO
open Expecto
open Musync.Domain
open Musync.Adapters.Songkick

// Unit tests for the pure `parseIcs` — no network, no DB. Driven by a realistic
// multi-VEVENT fixture (see fixtures/songkick_attendance.ics) that reproduces the
// real feed's quirks: bare `DTSTART:YYYYMMDD` dates, the U+2019 "You’re going"
// discriminator, an explicit ;TZID= event, a UTC (Z) event, an Interested event,
// and an indeterminate (no DESCRIPTION) event.

let private loadFixture () =
  Path.Combine(AppContext.BaseDirectory, "fixtures", "songkick_attendance.ics")
  |> File.ReadAllText

let private parse () = parseIcs (loadFixture ()) |> Want.ok

let private byUid (concerts: Concert list) =
  concerts |> List.map (fun c -> SongkickUid.value c.SongkickUid, c) |> Map.ofList

// UIDs in the fixture. 11111/33333/55555/66666 are Going; 22222 Interested;
// 44444 indeterminate (no DESCRIPTION).
let private going1 = "songkick-event-11111@songkick.com"
let private interested = "songkick-event-22222@songkick.com"
let private goingTzid = "songkick-event-33333@songkick.com"
let private indeterminate = "songkick-event-44444@songkick.com"
let private goingUtc = "songkick-event-55555@songkick.com"
let private goingUnresolved = "songkick-event-66666@songkick.com"

[<Tests>]
let songkickTests =
  testList "songkick ingest" [
    testCase "parseIcs yields ONLY the four Going concerts"
    <| fun _ ->
      let uids =
        parse () |> List.map (fun c -> SongkickUid.value c.SongkickUid) |> Set.ofList

      Want.equal
        (Set.ofList [
          going1
          goingTzid
          goingUtc
          goingUnresolved
        ])
        uids

    testCase "Interested and indeterminate events are excluded (fail-closed)"
    <| fun _ ->
      let m = parse () |> byUid
      Want.equal false (Map.containsKey interested m)
      Want.equal false (Map.containsKey indeterminate m)

    testCase "artist/venue/city/country/uid parsed; plan is Going"
    <| fun _ ->
      let c = (parse () |> byUid).[going1]
      Want.equal "Puscifer" (ArtistName.value c.Artist)
      Want.equal "Golden Gate Theatre" c.Venue
      Want.equal "San Francisco" c.City
      Want.equal "US" c.Country
      Want.equal going1 (SongkickUid.value c.SongkickUid)
      Want.equal PlanStatus.Going c.PlanStatus

    testCase "support-act SUMMARY keeps only the headliner artist"
    <| fun _ ->
      // "IDLES with Lambrini Girls at The Roundhouse" -> artist "IDLES".
      let c = (parse () |> byUid).[goingTzid]
      Want.equal "IDLES" (ArtistName.value c.Artist)
      Want.equal "The Roundhouse" c.Venue

    testCase "explicit ;TZID= is preserved and the instant is correct"
    <| fun _ ->
      // 2026-06-15 20:00 Europe/London (BST, +01:00) == 19:00:00Z.
      let c = (parse () |> byUid).[goingTzid]
      Want.equal "Europe/London" c.Tz
      Want.equal (DateTime(2026, 6, 15, 19, 0, 0)) c.StartsAt.UtcDateTime

    testCase "bare date resolves venue-local zone from the city map"
    <| fun _ ->
      // San Francisco -> America/Los_Angeles; midnight local 2026-05-11 (PDT, -07) == 07:00Z.
      let c = (parse () |> byUid).[going1]
      Want.equal "America/Los_Angeles" c.Tz
      Want.equal (DateTime(2026, 5, 11, 7, 0, 0)) c.StartsAt.UtcDateTime

    testCase "UTC DTSTART keeps its instant; venue tz via country fallback"
    <| fun _ ->
      // DTSTART ...Z is a known instant; Paris not in the city map, FR -> Europe/Paris.
      let c = (parse () |> byUid).[goingUtc]
      Want.equal "Europe/Paris" c.Tz
      Want.equal (DateTime(2026, 7, 20, 21, 0, 0)) c.StartsAt.UtcDateTime
      Want.equal "Le Bataclan" c.Venue
      Want.equal "Paris" c.City
      Want.equal "FR" c.Country

    testCase "unresolvable venue falls back to UTC"
    <| fun _ ->
      // Reykjavik/IS is in neither map -> UTC (WARN logged), midnight UTC.
      let c = (parse () |> byUid).[goingUnresolved]
      Want.equal "UTC" c.Tz
      Want.equal (DateTime(2026, 8, 1, 0, 0, 0)) c.StartsAt.UtcDateTime

    testCase "parseIcs is deterministic and idempotent"
    <| fun _ ->
      // Re-parsing the same feed yields structurally identical concerts (the
      // property that makes re-ingest a no-op after the DB upsert dedupes on UID).
      Want.equal (parse ()) (parse ())
  ]
