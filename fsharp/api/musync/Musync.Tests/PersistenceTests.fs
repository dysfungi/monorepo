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
  SongkickEventUrl = None
  EventStartAt = None
  DoorsAt = None
  ShowAt = None
  Openers = []
  TicketVendor = None
  EnrichedAt = None
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

/// A concert-page scrape (arbitrary instants; only their round-trip matters here).
let private sampleEnriched: EnrichedShow = {
  DoorsAt = Some(DateTimeOffset(2026, 5, 11, 1, 0, 0, TimeSpan.Zero))
  ShowAt = Some(DateTimeOffset(2026, 5, 11, 2, 0, 0, TimeSpan.Zero))
  Openers = [
    "Op A"
    "Op B"
  ]
  TicketVendor =
    Some {
      Name = "AXS"
      Url = "https://www.axs.com/x"
    }
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

  // Raw read of the DLQ bookkeeping columns (not surfaced on ConcertRow).
  let readDlq (id: Guid) =
    connStr
    |> Sql.connect
    |> Sql.query
      "SELECT calendar_first_failed_at, calendar_alerted_at, \
       setlist_first_failed_at, setlist_alerted_at FROM concerts WHERE id=@id"
    |> Sql.parameters [ "@id", Sql.uuid id ]
    |> Sql.execute (fun r -> {|
      CalFirst = r.datetimeOffsetOrNone "calendar_first_failed_at"
      CalAlerted = r.datetimeOffsetOrNone "calendar_alerted_at"
      SetFirst = r.datetimeOffsetOrNone "setlist_first_failed_at"
      SetAlerted = r.datetimeOffsetOrNone "setlist_alerted_at"
    |})
    |> List.head

  let insertReturningId (uid: string) =
    upsert databaseUrl (makeConcert uid "DLQ Venue" PlanStatus.Going) |> wantOk
    (getBySongkickUid databaseUrl uid |> wantOk |> Option.get).Id

  let stampNow = DateTimeOffset(2026, 6, 1, 12, 0, 0, TimeSpan.Zero)

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

    // ── virtual dead-letter queue ─────────────────────────────────────────────
    testCase "calendar: error sets first_failed_at; markCalendarSent clears both"
    <| fun _ ->
      let uid = "it-" + Guid.NewGuid().ToString("N")

      try
        let id = insertReturningId uid
        recordCalendarError databaseUrl id "boom" |> wantOk
        Want.equal true (Option.isSome (readDlq id).CalFirst)

        // Prove markCalendarSent clears the alerted stamp too.
        exec "UPDATE concerts SET calendar_alerted_at = now() WHERE id=@id" [
          "@id", Sql.uuid id
        ]

        markCalendarSent databaseUrl id stampNow |> wantOk
        let after = readDlq id
        Want.equal None after.CalFirst
        Want.equal None after.CalAlerted
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]

    testCase "setlist: error sets first_failed_at; notified + found both clear it"
    <| fun _ ->
      let uid = "it-" + Guid.NewGuid().ToString("N")

      try
        let id = insertReturningId uid
        recordSetlistError databaseUrl id "boom" |> wantOk
        Want.equal true (Option.isSome (readDlq id).SetFirst)

        exec "UPDATE concerts SET setlist_alerted_at = now() WHERE id=@id" [
          "@id", Sql.uuid id
        ]

        markSetlistNotified databaseUrl id stampNow |> wantOk
        let afterNudge = readDlq id
        Want.equal None afterNudge.SetFirst
        Want.equal None afterNudge.SetAlerted

        // A later error re-arms the marker; the terminal found-success clears it.
        recordSetlistError databaseUrl id "boom again" |> wantOk

        exec "UPDATE concerts SET setlist_alerted_at = now() WHERE id=@id" [
          "@id", Sql.uuid id
        ]

        markSetlistFound databaseUrl id stampNow |> wantOk
        let afterFound = readDlq id
        Want.equal None afterFound.SetFirst
        Want.equal None afterFound.SetAlerted
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]

    // ── concert-page enrichment ───────────────────────────────────────────────
    testCase "storeEnrichment round-trips; event_start = doors precedence"
    <| fun _ ->
      let uid = "it-" + Guid.NewGuid().ToString("N")

      try
        let id = insertReturningId uid
        storeEnrichment databaseUrl id sampleEnriched stampNow |> wantOk

        let c =
          getBySongkickUid databaseUrl uid
          |> wantOk
          |> Option.get
          |> toConcert
          |> wantOk

        Want.equal sampleEnriched.DoorsAt c.DoorsAt
        Want.equal sampleEnriched.ShowAt c.ShowAt

        Want.equal
          [
            "Op A"
            "Op B"
          ]
          c.Openers

        Want.equal
          (Some {
            Name = "AXS"
            Url = "https://www.axs.com/x"
          })
          c.TicketVendor

        Want.equal sampleEnriched.DoorsAt c.EventStartAt // doors, not show
        Want.equal (Some stampNow) c.EnrichedAt
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]

    testCase "enriched columns survive a benign re-ingest (identity unchanged)"
    <| fun _ ->
      let uid = "it-" + Guid.NewGuid().ToString("N")

      try
        let id = insertReturningId uid // artist/venue/starts_at fixed by makeConcert
        storeEnrichment databaseUrl id sampleEnriched stampNow |> wantOk

        // Re-ingest with the SAME identity (artist/venue/starts_at) but a benign
        // change: plan flips + a feed URL arrives.
        let reingest = {
          makeConcert uid "DLQ Venue" PlanStatus.Interested with
              SongkickEventUrl = Some "https://www.songkick.com/concerts/xyz"
        }

        upsert databaseUrl reingest |> wantOk
        let row = getBySongkickUid databaseUrl uid |> wantOk |> Option.get
        // feed columns updated
        Want.equal "interested" row.PlanStatus
        Want.equal (Some "https://www.songkick.com/concerts/xyz") row.SongkickEventUrl
        // enriched columns PRESERVED (not in the feed); openers are newline-joined
        Want.equal true (Option.isSome row.DoorsAt)
        Want.equal (Some "Op A\nOp B") row.Openers
        Want.equal (Some "AXS") row.TicketVendor
        Want.equal true (Option.isSome row.EnrichedAt)
      finally
        exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]

    testCase "material-identity change (date OR venue) resets enriched columns"
    <| fun _ ->
      // Both a reschedule (date) and a same-date relocation (venue) move the hash,
      // so both must re-arm enrichment or the resend would carry the old scrape.
      let expectReset (mutate: Concert -> Concert) =
        let uid = "it-" + Guid.NewGuid().ToString("N")

        try
          let id = insertReturningId uid
          storeEnrichment databaseUrl id sampleEnriched stampNow |> wantOk

          upsert databaseUrl (mutate (makeConcert uid "DLQ Venue" PlanStatus.Going))
          |> wantOk

          let row = getBySongkickUid databaseUrl uid |> wantOk |> Option.get
          Want.equal None row.EventStartAt
          Want.equal None row.DoorsAt
          Want.equal None row.ShowAt
          Want.equal None row.Openers
          Want.equal None row.TicketVendor
          Want.equal None row.EnrichedAt
        finally
          exec "DELETE FROM concerts WHERE songkick_uid=@u" [ "@u", Sql.text uid ]

      // reschedule: different starts_at
      expectReset (fun c -> {
        c with
            StartsAt = DateTimeOffset(2026, 6, 20, 3, 0, 0, TimeSpan.Zero)
      })
      // relocation: same date, different venue
      expectReset (fun c -> { c with Venue = "Relocated Hall" })

    testCase "listStuck: 24h window, both-steps-stuck, markAlerted dedupes"
    <| fun _ ->
      let stuckUid = "it-" + Guid.NewGuid().ToString("N")
      let freshUid = "it-" + Guid.NewGuid().ToString("N")

      try
        // Concert 1: BOTH steps first failed 25h ago, neither done nor alerted.
        let stuckId = insertReturningId stuckUid

        exec "UPDATE concerts SET calendar_first_failed_at=@t, calendar_last_error=@ce, \
           setlist_first_failed_at=@t, setlist_last_error=@se WHERE id=@id" [
          "@t", Sql.timestamptz (stampNow.AddHours(-25.0))
          "@ce", Sql.text "cal boom"
          "@se", Sql.text "set boom"
          "@id", Sql.uuid stuckId
        ]

        // Concert 2: only 1h into failure => still inside the self-heal window.
        let freshId = insertReturningId freshUid

        exec "UPDATE concerts SET calendar_first_failed_at=@t WHERE id=@id" [
          "@t", Sql.timestamptz (stampNow.AddHours(-1.0))
          "@id", Sql.uuid freshId
        ]

        let mine (items: StuckItem list) =
          items |> List.filter (fun i -> i.ConcertId = stuckId || i.ConcertId = freshId)

        let stuck = listStuck databaseUrl stampNow |> wantOk |> mine
        Want.equal 2 (List.length stuck)
        Want.equal true (stuck |> List.forall (fun i -> i.ConcertId = stuckId))
        Want.equal true (stuck |> List.exists (fun i -> i.Step = StuckStep.Calendar))
        Want.equal true (stuck |> List.exists (fun i -> i.Step = StuckStep.Setlist))

        let calItem = stuck |> List.find (fun i -> i.Step = StuckStep.Calendar)
        Want.equal (Some "cal boom") calItem.LastError

        // Escalate, then the same window must no longer surface them.
        markAlerted databaseUrl stampNow stuck |> wantOk
        Want.equal 0 (List.length (listStuck databaseUrl stampNow |> wantOk |> mine))
      finally
        exec "DELETE FROM concerts WHERE songkick_uid IN (@a, @b)" [
          "@a", Sql.text stuckUid
          "@b", Sql.text freshUid
        ]
  ]

[<Tests>]
let persistenceTests =
  if String.IsNullOrWhiteSpace dbUrl then
    testList "persistence (integration)" [
      ptestCase "skipped — set MUSYNC_TEST_DATABASE_URL to run" <| fun _ -> ()
    ]
  else
    integrationTests dbUrl
