module Musync.Tests.PersistenceTests

open System
open Expecto
open Npgsql.FSharp
open Musync.Domain
open Musync.Persistence

// Integration tests against a REAL Postgres (compose PG + dbmate migrations).
// Gated on MUSYNC_TEST_DATABASE_URL: when set, the suite runs for real; when
// unset it degrades to a single pending case so a plain `dotnet test` without
// Docker still passes. Each case uses a random UID and cleans up after itself.

let private dbUrl = Environment.GetEnvironmentVariable "MUSYNC_TEST_DATABASE_URL"

let private wantOk result =
  match result with
  | Ok v -> v
  | Error err -> failtestf "expected Ok, got %A" err

let private makeConcert (uid: string) (venue: string) (plan: PlanStatus) : Concert = {
  Id = Guid.Empty
  AccountId = "default"
  SongkickUid = SongkickUid.create uid |> wantOk
  Artist = ArtistName.create "Test Artist" |> wantOk
  Venue = venue
  City = "San Francisco"
  Country = "US"
  StartsAt = DateTimeOffset(2026, 5, 11, 3, 0, 0, TimeSpan.Zero)
  Tz = "America/Los_Angeles"
  PlanStatus = plan
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

let private integrationTests (databaseUrl: string) =
  let connStr = toConnectionString databaseUrl

  let exec sql ps =
    connStr
    |> Sql.connect
    |> Sql.query sql
    |> Sql.parameters ps
    |> Sql.executeNonQuery
    |> ignore

  testList "persistence (integration)" [
    testCase "upsert inserts, then updates on conflict WITHOUT clobbering state"
    <| fun _ ->
      let uid = "it-" + Guid.NewGuid().ToString("N")

      try
        // ── insert path ──────────────────────────────────────────────────────
        upsert databaseUrl (makeConcert uid "Venue One" PlanStatus.Going) |> wantOk

        let row1 =
          getBySongkickUid databaseUrl uid
          |> wantOk
          |> Option.defaultWith (fun () -> failtest "expected a row after insert")

        Want.equal "Venue One" row1.Venue
        Want.equal "going" row1.PlanStatus
        Want.equal 0 row1.CalendarSequence
        Want.equal None row1.ProbableSetlist

        // Simulate downstream state written by later phases (calendar + setlist).
        exec "UPDATE concerts SET content_hash=@h, calendar_sequence=@s, \
           probable_setlist=@p::jsonb, setlist_attempts=@a WHERE songkick_uid=@u" [
          "@h", Sql.text "hash-xyz"
          "@s", Sql.int 3
          "@p", Sql.text "{\"songs\":[]}"
          "@a", Sql.int 2
          "@u", Sql.text uid
        ]

        // ── conflict/update path (re-ingest with changed show fields) ─────────
        upsert databaseUrl (makeConcert uid "Venue Two" PlanStatus.Interested) |> wantOk

        let row2 =
          getBySongkickUid databaseUrl uid
          |> wantOk
          |> Option.defaultWith (fun () ->
            failtest "expected a row after conflict-update")

        // show/plan columns ARE updated
        Want.equal "Venue Two" row2.Venue
        Want.equal "interested" row2.PlanStatus
        // downstream state is PRESERVED (the whole point of the narrow SET clause)
        Want.equal (Some "hash-xyz") row2.ContentHash
        Want.equal 3 row2.CalendarSequence
        Want.equal 2 row2.SetlistAttempts
        Want.equal true (Option.isSome row2.ProbableSetlist)
        // idempotent identity: same row, not a duplicate
        Want.equal row1.Id row2.Id
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]

    testCase "listConcerts round-trips an inserted row"
    <| fun _ ->
      let uid = "it-" + Guid.NewGuid().ToString("N")

      try
        upsert databaseUrl (makeConcert uid "List Venue" PlanStatus.Going) |> wantOk
        let rows = listConcerts databaseUrl |> wantOk
        Want.equal true (rows |> List.exists (fun r -> r.SongkickUid = uid))
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]
  ]

[<Tests>]
let persistenceTests =
  if String.IsNullOrWhiteSpace dbUrl then
    testList "persistence (integration)" [
      ptestCase "skipped — set MUSYNC_TEST_DATABASE_URL to run" <| fun _ -> ()
    ]
  else
    integrationTests dbUrl
