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

[<EntryPoint>]
let main argv =
  let parser = ArgumentParser.Create<Command>(programName = "musync")

  match parser.ParseCommandLine(argv, raiseOnUsage = false).GetAllResults() with
  | [ Poll_Songkick ] ->
    let config = Config.load ()
    let source = Songkick.SongkickShowSource(config.SongkickIcsUrl) :> IShowSource

    let calendarTarget =
      CalendarEmail.SmtpCalendarTarget(config.Smtp, config.UserEmail) :> ICalendarTarget

    // ── Core: fetch Going shows, then upsert each. `List.fold` short-circuits on
    // the first persistence error (Result.bind), so a partial failure aborts the
    // run with a non-zero exit.
    let upsertOutcome =
      source.FetchGoingConcerts()
      |> Async.RunSynchronously
      |> Result.map (fun concerts ->
        let count =
          (Ok 0, concerts)
          ||> List.fold (fun acc concert ->
            acc
            |> Result.bind (fun n ->
              Persistence.upsert config.DatabaseUrl concert
              |> Result.map (fun () -> n + 1)))

        concerts, count)

    match upsertOutcome with
    | Error err ->
      eprintfn "[musync] poll-songkick FAILED: %A" err
      1
    | Ok(_, Error err) ->
      eprintfn "[musync] poll-songkick FAILED (upsert): %A" err
      1
    | Ok(concerts, Ok count) ->
      // ── Calendar pass: run the state machine per concert. A per-concert failure
      // is tallied + WARN-logged (via CalendarSync) but NEVER aborts the run — the
      // poll+upsert CORE already succeeded. A step that keeps failing is escalated
      // by the curate-preshow self-check (virtual DLQ), not here.
      let sent, skipped, failed =
        ((0, 0, 0), concerts)
        ||> List.fold (fun (s, k, f) concert ->
          let uid = SongkickUid.value concert.SongkickUid

          let stepOutcome =
            Persistence.getBySongkickUid config.DatabaseUrl uid
            |> Result.bind (function
              | None ->
                Error(Errors.PersistenceError(sprintf "row missing for uid %s" uid))
              | Some row ->
                CalendarSync.runStep
                  config.DatabaseUrl
                  calendarTarget
                  (fun () -> DateTimeOffset.UtcNow)
                  row
                |> Async.RunSynchronously)

          match stepOutcome with
          | Ok(CalendarSync.Sent _) -> (s + 1, k, f)
          | Ok CalendarSync.Skipped -> (s, k + 1, f)
          | Ok(CalendarSync.SendFailed _) -> (s, k, f + 1)
          | Error err ->
            eprintfn "[musync] WARN calendar: step error for %s: %A" uid err
            (s, k, f + 1))

      printfn
        "[musync] poll-songkick: upserted %d Going concert(s); calendar sent=%d skipped=%d failed=%d"
        count
        sent
        skipped
        failed

      0
  | [ Curate_Preshow ] ->
    let config = Config.load ()
    let provider = Setlist.SetlistFmProvider(config.SetlistFmApiKey) :> ISetlistProvider
    let notifier = Notifier.SmtpNotifier(config.Smtp, config.UserEmail) :> INotifier
    let now () = DateTimeOffset.UtcNow
    // ~3-day pre-show window. The user pre-creates the Setlist.fm entry ≤3 days
    // out, so that is when a nudge is actionable.
    let horizonDays = 3

    // ── Core: select the in-window, not-yet-found concerts. A window-query
    // failure aborts the run with a non-zero exit.
    match Persistence.listCurateWindow config.DatabaseUrl (now ()) horizonDays with
    | Error err ->
      eprintfn "[musync] curate-preshow FAILED (window query): %A" err
      1
    | Ok rows ->
      // Per-concert curate. A per-concert failure is tallied + WARN-logged (via
      // SetlistCurate) but NEVER aborts the run — the window-select CORE succeeded.
      let found, nudged, already, failed =
        ((0, 0, 0, 0), rows)
        ||> List.fold (fun (fo, nu, al, fa) row ->
          let stepOutcome =
            SetlistCurate.runStep config.DatabaseUrl provider notifier now row
            |> Async.RunSynchronously

          match stepOutcome with
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

      // ── Self-check (virtual DLQ): the daily run notices its OWN work that has
      // stayed stuck past the 24h self-heal window and escalates it ONCE. A
      // self-check failure is logged loud but never fails the run — the curate
      // core already succeeded.
      match Persistence.listStuck config.DatabaseUrl (now ()) with
      | Error err -> eprintfn "[musync] WARN self-check: listStuck failed: %A" err
      | Ok [] -> ()
      | Ok stuck ->
        match notifier.SendStuckAlert stuck |> Async.RunSynchronously with
        | Error err ->
          eprintfn "[musync] WARN self-check: stuck-alert send failed: %A" err
        | Ok() ->
          match Persistence.markAlerted config.DatabaseUrl (now ()) stuck with
          | Ok() ->
            printfn
              "[musync] self-check: escalated %d stuck item(s)"
              (List.length stuck)
          | Error err -> eprintfn "[musync] WARN self-check: markAlerted failed: %A" err

      0
  | _ ->
    printfn "%s" (parser.PrintUsage())
    0
