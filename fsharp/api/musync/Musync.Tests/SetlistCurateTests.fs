module Musync.Tests.SetlistCurateTests

open System
open Expecto
open Npgsql.FSharp
open Musync.Errors
open Musync.Domain
open Musync.Ports
open Musync.Persistence

// Integration tests for the setlist CURATE state machine against a REAL Postgres
// (compose PG + dbmate). Gated on MUSYNC_TEST_DATABASE_URL exactly like the other
// integration suites: unset => one pending case so `dotnet test` without Docker
// still passes. Provider + notifier are controllable stubs (fixed clock, no
// network) so window / dedupe / terminal behavior is exercised deterministically.

let private dbUrl = Environment.GetEnvironmentVariable "MUSYNC_TEST_DATABASE_URL"
let private now = DateTimeOffset(2026, 6, 30, 12, 0, 0, TimeSpan.Zero)
let private clock () = now

let private prediction =
  ProbableSetlist.fromSetlists now [
    [
      "Bloom"
      "15 Step"
    ]
    [
      "Bloom"
      "Idioteque"
    ]
  ]

/// Controllable `ISetlistProvider`: canned prediction, settable existence verdict.
type private StubProvider() =
  let mutable exists = false
  member _.SetExists v = exists <- v

  interface ISetlistProvider with
    member _.PredictSetlist(_) = async { return Ok prediction }
    member _.SetlistExists(_) = async { return Ok exists }

/// Controllable `INotifier`: counts nudges sent.
type private StubNotifier() =
  let mutable calls = 0
  member _.Calls = calls

  interface INotifier with
    member _.SendSetlistNudge(_, _) =
      async {
        calls <- calls + 1
        return Ok()
      }

    member _.SendStuckAlert(_) = async { return Ok() }

/// A Going concert `daysOut` days from `now` (drives window membership).
let private makeConcert (uid: string) (daysOut: float) : Concert = {
  Id = Guid.Empty
  AccountId = "default"
  SongkickUid = SongkickUid.create uid |> Result.defaultWith (fun _ -> failwith "uid")
  Artist =
    ArtistName.create "Radiohead" |> Result.defaultWith (fun _ -> failwith "artist")
  Venue = "The Fillmore"
  City = "San Francisco"
  Country = "US"
  StartsAt = now.AddDays daysOut
  Tz = "America/Los_Angeles"
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

let private wantOk result =
  match result with
  | Ok v -> v
  | Error err -> failtestf "expected Ok, got %A" err

let private integrationTests (databaseUrl: string) =
  let connStr = toConnectionString databaseUrl

  let exec sql ps =
    connStr
    |> Sql.connect
    |> Sql.query sql
    |> Sql.parameters ps
    |> Sql.executeNonQuery
    |> ignore

  let readState (uid: string) =
    connStr
    |> Sql.connect
    |> Sql.query
      "SELECT probable_setlist::text AS probable_setlist, probable_setlist_computed_at, \
       setlist_notified_at, setlist_found_at, setlist_attempts \
       FROM concerts WHERE songkick_uid=@u"
    |> Sql.parameters [ "@u", Sql.text uid ]
    |> Sql.execute (fun r -> {|
      Setlist = r.textOrNone "probable_setlist"
      ComputedAt = r.datetimeOffsetOrNone "probable_setlist_computed_at"
      NotifiedAt = r.datetimeOffsetOrNone "setlist_notified_at"
      FoundAt = r.datetimeOffsetOrNone "setlist_found_at"
      Attempts = r.int "setlist_attempts"
    |})
    |> List.head

  // Re-select the row from the window each time (mirrors Program: fresh state per
  // run) so runStep sees the latest notified/found flags.
  let rowInWindow (uid: string) =
    listCurateWindow databaseUrl now 3
    |> wantOk
    |> List.tryFind (fun r -> r.SongkickUid = uid)

  let step (provider: ISetlistProvider) (notifier: INotifier) (uid: string) =
    match rowInWindow uid with
    | None -> failtestf "row %s not in window" uid
    | Some row ->
      Musync.SetlistCurate.runStep databaseUrl provider notifier clock row
      |> Async.RunSynchronously
      |> wantOk

  testList "setlist curate (integration)" [
    testCase "window selects near shows; nudge once (dedupe); found is terminal"
    <| fun _ ->
      let near = "cur-" + Guid.NewGuid().ToString("N")
      let far = "cur-" + Guid.NewGuid().ToString("N")

      try
        upsert databaseUrl (makeConcert near 2.0) |> wantOk // in window
        upsert databaseUrl (makeConcert far 10.0) |> wantOk // out of window

        // ── window membership: near in, far out ──────────────────────────────
        let windowUids =
          listCurateWindow databaseUrl now 3
          |> wantOk
          |> List.map (fun r -> r.SongkickUid)
          |> Set.ofList

        Want.equal true (Set.contains near windowUids)
        Want.equal false (Set.contains far windowUids)

        let provider = StubProvider()
        let notifier = StubNotifier()

        // ── first run: no entry => nudge, stamp notified, store prediction ────
        provider.SetExists false

        match step provider notifier near with
        | Musync.SetlistCurate.Nudged -> ()
        | other -> failtestf "expected Nudged, got %A" other

        let s1 = readState near
        Want.equal 1 notifier.Calls
        Want.equal true (Option.isSome s1.NotifiedAt)
        Want.equal None s1.FoundAt
        Want.equal true (Option.isSome s1.Setlist) // recomputed + stored
        Want.equal (Some now) s1.ComputedAt

        // ── second run (still missing): dedupe — NO second nudge ─────────────
        match step provider notifier near with
        | Musync.SetlistCurate.AlreadyNotified -> ()
        | other -> failtestf "expected AlreadyNotified, got %A" other

        Want.equal 1 notifier.Calls // NOT called again
        Want.equal s1.NotifiedAt (readState near).NotifiedAt // unchanged

        // ── entry now exists: stamp found (terminal), no nudge ───────────────
        provider.SetExists true

        match step provider notifier near with
        | Musync.SetlistCurate.Found -> ()
        | other -> failtestf "expected Found, got %A" other

        Want.equal 1 notifier.Calls
        Want.equal true (Option.isSome (readState near).FoundAt)

        // ── terminal: found rows drop out of the window (no recompute/nudge) ──
        Want.equal None (rowInWindow near)
      finally
        exec "DELETE FROM concerts WHERE songkick_uid = ANY(@uids)" [
          "@uids",
          Sql.stringArray [|
            near
            far
          |]
        ]
  ]

[<Tests>]
let setlistCurateTests =
  if String.IsNullOrWhiteSpace dbUrl then
    testList "setlist curate (integration)" [
      ptestCase "skipped — set MUSYNC_TEST_DATABASE_URL to run" <| fun _ -> ()
    ]
  else
    integrationTests dbUrl
