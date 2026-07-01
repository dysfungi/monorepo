module Musync.Program

open System
open Argu
open FsHttp
open Musync.Domain
open Musync.Ports
open Musync.Adapters

/// Top-level CLI commands. Argu lowercases + hyphenates the case names, so
/// `Poll_Songkick` is invoked as `musync poll-songkick`. Bodies are stubs in
/// Phase 1a — real logic arrives in later phases; Phase 1b adds the deadman ping.
type Command =
  | [<CliPrefix(CliPrefix.None)>] Poll_Songkick
  | [<CliPrefix(CliPrefix.None)>] Curate_Preshow

  interface IArgParserTemplate with
    member this.Usage =
      match this with
      | Poll_Songkick -> "Ingest 'Going' shows from the source and upsert concerts."
      | Curate_Preshow -> "Compute probable setlists and send pre-show nudges."

/// Deadman-switch ping: POST to the command's healthcheck URL to signal a
/// successful run. Called ONLY after the command body completes without error —
/// a failed or missed run withholds the ping, which trips the external alert
/// (Grafana Cloud / healthchecks-style). Config.load already guarantees the URL
/// is present (FsConfig fails loud on a missing env var), so the URL is non-empty.
let private pingDeadman (url: string) =
  http { POST url } |> Request.send |> ignore

[<EntryPoint>]
let main argv =
  let parser = ArgumentParser.Create<Command>(programName = "musync")

  match parser.ParseCommandLine(argv, raiseOnUsage = false).GetAllResults() with
  | [ Poll_Songkick ] ->
    let config = Config.load ()
    let source = Songkick.SongkickShowSource(config.SongkickIcsUrl) :> IShowSource

    let calendarTarget =
      CalendarEmail.SmtpCalendarTarget(config.Smtp) :> ICalendarTarget

    // ── Core: fetch Going shows, then upsert each. `List.fold` short-circuits on
    // the first persistence error (Result.bind), so a partial failure aborts and
    // — crucially — withholds the deadman ping below, tripping the external alert.
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
      // poll+upsert CORE already succeeded, so the deadman still pings below.
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
      // Deadman ping: poll+upsert core succeeded. Calendar failures are surfaced
      // (WARN + calendar_last_error) but do NOT withhold the ping.
      pingDeadman config.Deadman.PollSongkickUrl
      0
  | [ Curate_Preshow ] ->
    let config = Config.load ()
    printfn "[musync] curate-preshow: stub (Phase 1a) — no-op"
    pingDeadman config.Deadman.CuratePreshowUrl
    0
  | _ ->
    printfn "%s" (parser.PrintUsage())
    0
