module Musync.Tests.SetlistTests

open System
open System.IO
open Expecto
open Musync.Domain
open Musync.Adapters.Setlist

// Unit tests for the PURE setlist core — no network, no DB. Driven by recorded
// Setlist.fm JSON fixtures (fixtures/setlist_*.json) that reproduce the real
// payload's nesting (sets.set[].song[]), the single-element array quirk (a
// one-result response returns `setlist`/`set` as bare objects), and an empty
// (total:0) response.

let private loadFixture (name: string) =
  Path.Combine(AppContext.BaseDirectory, "fixtures", name) |> File.ReadAllText

let private fixedNow = DateTimeOffset(2026, 6, 30, 0, 0, 0, TimeSpan.Zero)

/// A concert with a venue-local show date driven by an LA midnight instant
/// (07:00Z in June/Aug PDT == 00:00 local). `dayZ`/`monthZ` set that local date.
let private concert
  (artist: string)
  (venue: string)
  (city: string)
  (month: int)
  (day: int)
  : Concert =
  {
    Id = Guid.Empty
    AccountId = "default"
    SongkickUid = SongkickUid.create "sk-1" |> Want.ok
    Artist = ArtistName.create artist |> Want.ok
    Venue = venue
    City = city
    Country = "US"
    StartsAt = DateTimeOffset(2026, month, day, 7, 0, 0, TimeSpan.Zero)
    Tz = "America/Los_Angeles"
    PlanStatus = PlanStatus.Going
    CalendarUid = None
    ContentHash = None
    CalendarSequence = 0
    CalendarSentAt = None
    CalendarAttempts = 0
    CalendarLastError = None
    ProbableSetlist = None
    ProbableSetlistComputedAt = None
    SetlistNotifiedAt = None
    SetlistFoundAt = None
    SetlistAttempts = 0
    SetlistLastError = None
    CreatedAt = DateTimeOffset.MinValue
    UpdatedAt = DateTimeOffset.MinValue
  }

[<Tests>]
let setlistTests =
  testList "setlist" [
    // ── ranking (pure Domain computation) ────────────────────────────────────
    testList "ranking" [
      testCase "ranks by frequency desc, then typical position, then name"
      <| fun _ ->
        // Bloom: 3 shows @ mean pos .33; 15 Step: 3 @ .67; Idioteque: 3 @ 2.33;
        // Reckoner: 2 @ 2.5; Lucky: 1 @ 3.0.
        let setlists = [
          [
            "Bloom"
            "15 Step"
            "Idioteque"
            "Reckoner"
          ]
          [
            "15 Step"
            "Bloom"
            "Idioteque"
            "Lucky"
          ]
          [
            "Bloom"
            "15 Step"
            "Reckoner"
            "Idioteque"
          ]
        ]

        let result = ProbableSetlist.fromSetlists fixedNow setlists

        let expected = [
          "Bloom", 3, 1
          "15 Step", 3, 2
          "Idioteque", 3, 3
          "Reckoner", 2, 4
          "Lucky", 1, 5
        ]

        Want.equal
          expected
          (result.Songs |> List.map (fun s -> s.Name, s.Frequency, s.Position))

        Want.equal fixedNow result.ComputedAt

      testCase "is deterministic — identical input yields identical output"
      <| fun _ ->
        let setlists = [
          [
            "A"
            "B"
            "C"
          ]
          [
            "B"
            "A"
            "D"
          ]
          [
            "A"
            "C"
            "B"
          ]
        ]

        Want.equal
          (ProbableSetlist.fromSetlists fixedNow setlists)
          (ProbableSetlist.fromSetlists fixedNow setlists)

      testCase "a repeat within one setlist counts once (first position wins)"
      <| fun _ ->
        // "Creep" appears twice in the single setlist -> frequency 1, position 1.
        let result =
          ProbableSetlist.fromSetlists fixedNow [
            [
              "Creep"
              "Karma"
              "Creep"
            ]
          ]

        Want.equal 2 result.Songs.Length
        let creep = result.Songs |> List.find (fun s -> s.Name = "Creep")
        Want.equal 1 creep.Frequency

      testCase "no tour history yields an empty prediction"
      <| fun _ -> Want.equal [] (ProbableSetlist.fromSetlists fixedNow []).Songs

      testCase "ranks a parsed fixture end-to-end (parse -> rank)"
      <| fun _ ->
        let parsed =
          parseArtistSetlists (loadFixture "setlist_radiohead_setlists.json") |> Want.ok

        let ranked = rankSetlists fixedNow parsed

        Want.equal
          [
            "Bloom"
            "15 Step"
            "Idioteque"
            "Reckoner"
            "Lucky"
          ]
          (ranked.Songs |> List.map (fun s -> s.Name))
    ]

    // ── parsing ──────────────────────────────────────────────────────────────
    testList "parsing" [
      testCase "parseArtistSetlists reads eventDate / venue / flattened songs"
      <| fun _ ->
        let parsed =
          parseArtistSetlists (loadFixture "setlist_radiohead_setlists.json") |> Want.ok

        Want.equal 3 parsed.Length
        let a = parsed |> List.find (fun s -> s.Id = "a1")
        Want.equal "20-06-2026" a.EventDate
        Want.equal "The Fillmore" a.VenueName
        Want.equal "San Francisco" a.City
        // main set + encore flattened in order.
        Want.equal
          [
            "Bloom"
            "15 Step"
            "Idioteque"
            "Reckoner"
          ]
          a.Songs

      testCase "parseArtistSetlists handles the single-element (object) quirk"
      <| fun _ ->
        // fixture returns `setlist`/`set` as bare objects, not arrays.
        let parsed =
          parseArtistSetlists (loadFixture "setlist_beatles_fuzzy.json") |> Want.ok

        Want.equal 1 parsed.Length
        Want.equal "The Beatles" parsed.[0].ArtistName

        Want.equal
          [
            "Twist and Shout"
            "I Feel Fine"
          ]
          parsed.[0].Songs

      testCase "parseArtistSetlists on an empty (total:0) response yields []"
      <| fun _ ->
        Want.equal
          []
          (parseArtistSetlists (loadFixture "setlist_search_empty.json") |> Want.ok)

      testCase "parseArtistSetlists on malformed JSON is an Error"
      <| fun _ -> parseArtistSetlists "not json" |> Want.isError

      testCase "parseArtistSearch reads (mbid, name), best match first"
      <| fun _ ->
        let json =
          """{"type":"artists","itemsPerPage":30,"page":1,"total":2,
             "artist":[{"mbid":"r-mbid","name":"Radiohead","sortName":"Radiohead"},
                       {"mbid":"r2","name":"Radiohead Tribute","sortName":"x"}]}"""

        Want.equal
          [
            "r-mbid", "Radiohead"
            "r2", "Radiohead Tribute"
          ]
          (parseArtistSearch json |> Want.ok)
    ]

    // ── existence check (matchesConcert; fail-open) ──────────────────────────
    testList "existence (matchesConcert)" [
      let radioheadSetlists () =
        parseArtistSetlists (loadFixture "setlist_radiohead_setlists.json") |> Want.ok

      let existsFor c =
        radioheadSetlists () |> List.exists (matchesConcert c)

      testCase "confident match (artist + date + venue/city) => exists"
      <| fun _ ->
        // a1: Radiohead @ The Fillmore, San Francisco, 20-06-2026.
        Want.equal
          true
          (existsFor (concert "Radiohead" "The Fillmore" "San Francisco" 6 20))

      testCase "matches on CITY agreement even if venue name differs"
      <| fun _ ->
        Want.equal
          true
          (existsFor (concert "Radiohead" "Some Other Hall" "San Francisco" 6 20))

      testCase "wrong date => no match (fail-open => nudge)"
      <| fun _ ->
        Want.equal
          false
          (existsFor (concert "Radiohead" "The Fillmore" "San Francisco" 6 21))

      testCase "right date but wrong venue AND city => no match"
      <| fun _ ->
        Want.equal
          false
          (existsFor (concert "Radiohead" "Nowhere Club" "Portland" 6 20))

      testCase "empty response => no match"
      <| fun _ ->
        let empty =
          parseArtistSetlists (loadFixture "setlist_search_empty.json") |> Want.ok

        Want.equal
          false
          (empty
           |> List.exists (
             matchesConcert (concert "Radiohead" "The Fillmore" "San Francisco" 6 20)
           ))

      testCase "fuzzy artist name (Beatles ~ The Beatles) still matches"
      <| fun _ ->
        let beatles =
          parseArtistSetlists (loadFixture "setlist_beatles_fuzzy.json") |> Want.ok
        // concert artist "Beatles" vs setlist "The Beatles"; city Queens; 22-08-2026.
        Want.equal
          true
          (beatles
           |> List.exists (
             matchesConcert (concert "Beatles" "Shea Stadium" "Queens" 8 22)
           ))
    ]

    // ── create deep-link ─────────────────────────────────────────────────────
    testCase "createSetlistUrl is the bare setlist.fm editor (prefill unsupported)"
    <| fun _ ->
      Want.equal
        "https://www.setlist.fm/edit"
        (createSetlistUrl (concert "Radiohead" "The Fillmore" "San Francisco" 6 20))
  ]
