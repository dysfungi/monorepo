module Musync.Tests.DomainTests

open System
open Expecto
open Musync.Domain

[<Tests>]
let domainTests =
  testList "domain" [
    testCase "SongkickUid smart constructor round-trips a valid value"
    <| fun _ ->
      let uid = SongkickUid.create "sk-12345" |> Want.ok
      Want.equal "sk-12345" (SongkickUid.value uid)

    testCase "SongkickUid trims surrounding whitespace"
    <| fun _ ->
      let uid = SongkickUid.create "  sk-12345  " |> Want.ok
      Want.equal "sk-12345" (SongkickUid.value uid)

    testCase "SongkickUid rejects empty input"
    <| fun _ -> SongkickUid.create "   " |> Want.isError

    testCase "ArtistName round-trips a valid value"
    <| fun _ ->
      let artist = ArtistName.create "Radiohead" |> Want.ok
      Want.equal "Radiohead" (ArtistName.value artist)

    testCase "ProbableSetlist.empty is deterministic"
    <| fun _ ->
      // Placeholder ranking (Phase 4 replaces the body) must be pure/stable.
      let computedAt = DateTimeOffset.UnixEpoch

      let expected: ProbableSetlist = {
        Songs = []
        ComputedAt = computedAt
      }

      Want.equal expected (ProbableSetlist.empty computedAt)
  ]
