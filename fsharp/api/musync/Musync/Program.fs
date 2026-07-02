module Musync.Program

open System
open Argu
open Musync.Domain
open Musync.Ports
open Musync.Adapters

/// Top-level CLI commands. Argu lowercases + hyphenates the case names, so
/// `Poll_Songkick` is invoked as `musync poll-songkick`.
type Command =
  | [<CliPrefix(CliPrefix.None)>] Poll_Songkick
  | [<CliPrefix(CliPrefix.None)>] Curate_Preshow

  interface IArgParserTemplate with
    member this.Usage =
      match this with
      | Poll_Songkick -> "Ingest 'Going' shows from the source and upsert concerts."
      | Curate_Preshow -> "Compute probable setlists and send pre-show nudges."

/// Best-effort concert-page enrichment, run BEFORE the calendar send so the first
/// invite already carries doors/show/openers/vendor. Skipped once `enriched_at` is
/// set (a reschedule resets it, forcing a re-enrich) or when there is no page URL.
/// On success returns the freshly reloaded row (now carrying the enriched columns),
/// else None; every failure is WARN-logged and swallowed. The reload only feeds
/// fresher data into THIS send — the content hash excludes enriched fields, so late
/// enrichment never forces a clobbering resend over the user's hand-edits.
let private enrichAndReload
  (databaseUrl: string)
  (enricher: IShowEnricher)
  (now: unit -> DateTimeOffset)
  (concert: Concert)
  : Persistence.ConcertRow option =
  let uid = SongkickUid.value concert.SongkickUid

  match concert.EnrichedAt, concert.SongkickEventUrl with
  | Some _, _
  | None, None -> None
  | None, Some _ ->
    match enricher.Enrich concert |> Async.RunSynchronously with
    | Error err ->
      eprintfn "[musync] WARN enrich: fetch/parse failed for %s: %A" uid err
      None
    | Ok enriched ->
      match Persistence.storeEnrichment databaseUrl concert.Id enriched (now ()) with
      | Error err ->
        eprintfn "[musync] WARN enrich: store failed for %s: %A" uid err
        None
      | Ok() ->
        match Persistence.getBySongkickUid databaseUrl uid with
        | Ok(Some fresh) -> Some fresh
        | _ -> None

/// `poll-songkick`: fetch the Going shows, upsert each, then run the calendar
/// state machine per concert.
let private runPoll (config: Config.AppConfig) : int =
  let source = Songkick.SongkickShowSource(config.SongkickIcsUrl) :> IShowSource

  let calendarTarget =
    CalendarEmail.SmtpCalendarTarget(config.Smtp, config.UserEmail) :> ICalendarTarget

  let enricher = SongkickEnrich.SongkickEnricher() :> IShowEnricher
  let now () = DateTimeOffset.UtcNow

  // Upsert every fetched concert, counting successes. `Result.bind` short-circuits
  // on the first persistence error, so a partial failure aborts with a non-zero exit.
  let upsertAll (concerts: Concert list) : Result<int, Errors.MusyncError> =
    (Ok 0, concerts)
    ||> List.fold (fun acc concert ->
      acc
      |> Result.bind (fun n ->
        Persistence.upsert config.DatabaseUrl concert |> Result.map (fun () -> n + 1)))

  // One concert's calendar step: reload its row, best-effort enrich before the
  // send, then run the state machine on the (possibly enriched) row.
  let calendarStep
    (concert: Concert)
    : Result<CalendarSync.CalStepResult, Errors.MusyncError> =
    let uid = SongkickUid.value concert.SongkickUid

    Persistence.getBySongkickUid config.DatabaseUrl uid
    |> Result.bind (function
      | None -> Error(Errors.PersistenceError(sprintf "row missing for uid %s" uid))
      | Some row0 ->
        let row =
          match Persistence.toConcert row0 with
          | Ok concert ->
            enrichAndReload config.DatabaseUrl enricher now concert
            |> Option.defaultValue row0
          | Error _ -> row0

        CalendarSync.runStep config.DatabaseUrl calendarTarget now row
        |> Async.RunSynchronously)

  match source.FetchGoingConcerts() |> Async.RunSynchronously with
  | Error err ->
    eprintfn "[musync] poll-songkick FAILED: %A" err
    1
  | Ok concerts ->
    match upsertAll concerts with
    | Error err ->
      eprintfn "[musync] poll-songkick FAILED (upsert): %A" err
      1
    | Ok count ->
      // Calendar pass: a per-concert failure is tallied + WARN-logged but NEVER
      // aborts the run — the poll+upsert core already succeeded. A step that keeps
      // failing is escalated by curate-preshow's virtual DLQ, not here.
      let sent, skipped, failed =
        ((0, 0, 0), concerts)
        ||> List.fold (fun (s, k, f) concert ->
          match calendarStep concert with
          | Ok(CalendarSync.Sent _) -> (s + 1, k, f)
          | Ok CalendarSync.Skipped -> (s, k + 1, f)
          | Ok(CalendarSync.SendFailed _) -> (s, k, f + 1)
          | Error err ->
            let uid = SongkickUid.value concert.SongkickUid
            eprintfn "[musync] WARN calendar: step error for %s: %A" uid err
            (s, k, f + 1))

      printfn
        "[musync] poll-songkick: upserted %d Going concert(s); calendar sent=%d skipped=%d failed=%d"
        count
        sent
        skipped
        failed

      0

/// Virtual-DLQ self-check: escalate our OWN steps that have stayed stuck past the
/// 24h self-heal window, once each. Every failure is logged loud but swallowed —
/// the curate core already succeeded, so this never fails the run.
let private runStuckSelfCheck
  (config: Config.AppConfig)
  (now: unit -> DateTimeOffset)
  (notifier: INotifier)
  : unit =
  match Persistence.listStuck config.DatabaseUrl (now ()) with
  | Error err -> eprintfn "[musync] WARN self-check: listStuck failed: %A" err
  | Ok [] -> ()
  | Ok stuck ->
    match notifier.SendStuckAlert stuck |> Async.RunSynchronously with
    | Error err -> eprintfn "[musync] WARN self-check: stuck-alert send failed: %A" err
    | Ok() ->
      match Persistence.markAlerted config.DatabaseUrl (now ()) stuck with
      | Ok() ->
        printfn "[musync] self-check: escalated %d stuck item(s)" (List.length stuck)
      | Error err -> eprintfn "[musync] WARN self-check: markAlerted failed: %A" err

/// `curate-preshow`: compute probable setlists + nudge for in-window shows, then
/// run the virtual-DLQ self-check and evict stale predictions.
let private runCurate (config: Config.AppConfig) : int =
  let provider = Setlist.SetlistFmProvider(config.SetlistFmApiKey) :> ISetlistProvider
  let notifier = Notifier.SmtpNotifier(config.Smtp, config.UserEmail) :> INotifier
  let now () = DateTimeOffset.UtcNow
  // ~3-day pre-show window: the user pre-creates the Setlist.fm entry ≤3 days out,
  // so that is when a nudge is actionable.
  let horizonDays = 3

  match Persistence.listCurateWindow config.DatabaseUrl (now ()) horizonDays with
  | Error err ->
    eprintfn "[musync] curate-preshow FAILED (window query): %A" err
    1
  | Ok rows ->
    // Per-concert curate. A per-concert failure is tallied + WARN-logged but never
    // aborts the run — the window-select core already succeeded.
    let found, nudged, already, failed =
      ((0, 0, 0, 0), rows)
      ||> List.fold (fun (fo, nu, al, fa) row ->
        match
          SetlistCurate.runStep config.DatabaseUrl provider notifier now row
          |> Async.RunSynchronously
        with
        | Ok SetlistCurate.Found -> (fo + 1, nu, al, fa)
        | Ok SetlistCurate.Nudged -> (fo, nu + 1, al, fa)
        | Ok SetlistCurate.AlreadyNotified -> (fo, nu, al + 1, fa)
        | Ok(SetlistCurate.Failed _) -> (fo, nu, al, fa + 1)
        | Error err ->
          eprintfn "[musync] WARN setlist: step error for %s: %A" row.SongkickUid err
          (fo, nu, al, fa + 1))

    printfn
      "[musync] curate-preshow: window=%d found=%d nudged=%d already-notified=%d failed=%d"
      (List.length rows)
      found
      nudged
      already
      failed

    runStuckSelfCheck config now notifier

    // Evict predictions for shows that have dropped out of the curate window.
    match Persistence.purgeStalePredictions config.DatabaseUrl (now ()) with
    | Ok() -> ()
    | Error err ->
      eprintfn "[musync] WARN self-check: purgeStalePredictions failed: %A" err

    0

[<EntryPoint>]
let main argv =
  let parser = ArgumentParser.Create<Command>(programName = "musync")

  match parser.ParseCommandLine(argv, raiseOnUsage = false).GetAllResults() with
  | [ Poll_Songkick ] -> runPoll (Config.load ())
  | [ Curate_Preshow ] -> runCurate (Config.load ())
  | _ ->
    printfn "%s" (parser.PrintUsage())
    0
