module Musync.Program

open Argu
open FsHttp
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

    // Fetch Going shows, then upsert each. `List.fold` short-circuits on the first
    // persistence error (Result.bind), so a partial failure aborts and — crucially
    // — withholds the deadman ping below, tripping the external alert.
    let outcome =
      source.FetchGoingConcerts()
      |> Async.RunSynchronously
      |> Result.bind (fun concerts ->
        (Ok 0, concerts)
        ||> List.fold (fun acc concert ->
          acc
          |> Result.bind (fun n ->
            Persistence.upsert config.DatabaseUrl concert
            |> Result.map (fun () -> n + 1))))

    match outcome with
    | Ok count ->
      printfn "[musync] poll-songkick: upserted %d Going concert(s)" count
      // Deadman ping ONLY on overall success — a failed run must not ping.
      pingDeadman config.Deadman.PollSongkickUrl
      0
    | Error err ->
      eprintfn "[musync] poll-songkick FAILED: %A" err
      1
  | [ Curate_Preshow ] ->
    let config = Config.load ()
    printfn "[musync] curate-preshow: stub (Phase 1a) — no-op"
    pingDeadman config.Deadman.CuratePreshowUrl
    0
  | _ ->
    printfn "%s" (parser.PrintUsage())
    0
