module Musync.Program

open Argu
open FsHttp

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
    printfn "[musync] poll-songkick: stub (Phase 1a) — no-op"
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
