module Musync.Tests.CalendarStateTests

open System
open Expecto
open Npgsql.FSharp
open Musync.Errors
open Musync.Domain
open Musync.Ports
open Musync.Persistence

// Integration tests for the calendar STATE MACHINE against a REAL Postgres
// (compose PG + dbmate). Gated on MUSYNC_TEST_DATABASE_URL exactly like
// PersistenceTests: unset => a single pending case so `dotnet test` without Docker
// still passes. The `ICalendarTarget` is a controllable stub so we exercise the
// Tx-A / send / Tx-B ordering deterministically (fixed clock, no real SMTP).

let private dbUrl = Environment.GetEnvironmentVariable "MUSYNC_TEST_DATABASE_URL"
let private fixedNow = DateTimeOffset(2026, 3, 1, 12, 0, 0, TimeSpan.Zero)
let private clock () = fixedNow

/// A controllable `ICalendarTarget`: counts sends and returns a settable result.
type private StubTarget() =
  let mutable calls = 0
  let mutable result: Result<unit, MusyncError> = Ok()
  member _.Calls = calls
  member _.SetResult r = result <- r

  interface ICalendarTarget with
    member _.SendInvite(_) =
      async {
        calls <- calls + 1
        return result
      }

let private makeConcert (uid: string) (venue: string) : Concert = {
  Id = Guid.Empty
  AccountId = "default"
  SongkickUid = SongkickUid.create uid |> Result.defaultWith (fun _ -> failwith "uid")
  Artist =
    ArtistName.create "Test Artist"
    |> Result.defaultWith (fun _ -> failwith "artist")
  Venue = venue
  City = "San Francisco"
  Country = "US"
  StartsAt = DateTimeOffset(2026, 5, 11, 7, 0, 0, TimeSpan.Zero)
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

  // Raw calendar-state read (some columns aren't on ConcertRow, e.g. last_error).
  let readState (uid: string) =
    connStr
    |> Sql.connect
    |> Sql.query
      "SELECT content_hash, calendar_sequence, calendar_uid, calendar_sent_at, \
       calendar_attempts, calendar_last_error FROM concerts WHERE songkick_uid=@u"
    |> Sql.parameters [ "@u", Sql.text uid ]
    |> Sql.execute (fun r -> {|
      Hash = r.textOrNone "content_hash"
      Sequence = r.int "calendar_sequence"
      Uid = r.textOrNone "calendar_uid"
      SentAt = r.datetimeOffsetOrNone "calendar_sent_at"
      Attempts = r.int "calendar_attempts"
      LastError = r.textOrNone "calendar_last_error"
    |})
    |> List.head

  let step (target: ICalendarTarget) (uid: string) =
    let row =
      getBySongkickUid databaseUrl uid
      |> wantOk
      |> Option.defaultWith (fun () -> failtest "row vanished")

    Musync.CalendarSync.runStep databaseUrl target clock row
    |> Async.RunSynchronously
    |> wantOk

  testList "calendar state machine (integration)" [
    testCase "first send -> unchanged skip -> projected change resend (seq++)"
    <| fun _ ->
      let uid = "cal-" + Guid.NewGuid().ToString("N")
      let target = StubTarget()

      try
        // ── first run: insert + send at sequence 0 ───────────────────────────
        upsert databaseUrl (makeConcert uid "Venue One") |> wantOk

        match step target uid with
        | Musync.CalendarSync.Sent 0 -> ()
        | other -> failtestf "expected Sent 0, got %A" other

        let s1 = readState uid
        Want.equal 1 target.Calls
        Want.equal true (Option.isSome s1.Hash)
        Want.equal 0 s1.Sequence

        Want.equal
          (Some(
            Musync.Calendar.uidFor
              (getBySongkickUid databaseUrl uid |> wantOk |> Option.get).Id
          ))
          s1.Uid

        Want.equal (Some fixedNow) s1.SentAt
        Want.equal 1 s1.Attempts
        Want.equal None s1.LastError

        // ── unchanged re-run: no resend ──────────────────────────────────────
        Want.equal Musync.CalendarSync.Skipped (step target uid)
        Want.equal 1 target.Calls // NOT called again
        Want.equal (Some fixedNow) (readState uid).SentAt

        // ── projected-field change (venue): sequence++ and resend ────────────
        upsert databaseUrl (makeConcert uid "Venue Two") |> wantOk

        match step target uid with
        | Musync.CalendarSync.Sent 1 -> ()
        | other -> failtestf "expected Sent 1, got %A" other

        let s2 = readState uid
        Want.equal 2 target.Calls
        Want.equal 1 s2.Sequence
        Want.equal (Some fixedNow) s2.SentAt
        Want.equal true (s1.Hash <> s2.Hash) // hash moved with the venue
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]

    testCase "send failure leaves sent_at NULL + records last_error; retry succeeds"
    <| fun _ ->
      let uid = "cal-" + Guid.NewGuid().ToString("N")
      let target = StubTarget()

      try
        upsert databaseUrl (makeConcert uid "Venue One") |> wantOk

        // ── failing send: sent_at stays NULL, error recorded, attempts bumped ─
        target.SetResult(Error(CalendarError "boom"))

        match step target uid with
        | Musync.CalendarSync.SendFailed _ -> ()
        | other -> failtestf "expected SendFailed, got %A" other

        let sFail = readState uid
        Want.equal None sFail.SentAt // NULL => next run retries
        Want.equal true (Option.isSome sFail.LastError)
        Want.equal 0 sFail.Sequence
        Want.equal 1 sFail.Attempts
        Want.equal true (Option.isSome sFail.Hash) // Tx A still stored the hash

        // ── retry (now succeeding): SAME sequence, sent_at set, error cleared ─
        target.SetResult(Ok())

        match step target uid with
        | Musync.CalendarSync.Sent 0 -> () // unchanged hash => sequence NOT bumped
        | other -> failtestf "expected Sent 0 on retry, got %A" other

        let sOk = readState uid
        Want.equal (Some fixedNow) sOk.SentAt
        Want.equal None sOk.LastError
        Want.equal 0 sOk.Sequence
        Want.equal 2 sOk.Attempts
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]
  ]

[<Tests>]
let calendarStateTests =
  if String.IsNullOrWhiteSpace dbUrl then
    testList "calendar state machine (integration)" [
      ptestCase "skipped — set MUSYNC_TEST_DATABASE_URL to run" <| fun _ -> ()
    ]
  else
    integrationTests dbUrl
