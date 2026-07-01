module Musync.Program

open Argu

/// Top-level CLI commands. Argu lowercases + hyphenates the case names, so
/// `Poll_Songkick` is invoked as `musync poll-songkick`. Bodies are stubs in
/// Phase 1a — real logic (and deadman pings) arrive in later phases.
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
    printfn "[musync] poll-songkick: stub (Phase 1a) — no-op"
    0
  | [ Curate_Preshow ] ->
    printfn "[musync] curate-preshow: stub (Phase 1a) — no-op"
    0
  | _ ->
    printfn "%s" (parser.PrintUsage())
    0
