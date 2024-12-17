module AutoMate.Config

open Argu
open AutoMate.Utilities

type AppConfig =
  | Database_Name of NAME: string
  | Database_Host of HOST: string
  | Database_Password of PASSWORD: string
  | Database_Port of PORT: int
  | Database_Username of USERNAME: string

  interface IArgParserTemplate with
    member arg.Usage =
      match arg with
      | Database_Name _ -> "The database name"
      | Database_Host _ -> "The database host"
      | Database_Password _ -> "The database password"
      | Database_Port _ -> "The database port"
      | Database_Username _ -> "The database username"

/// Environment variable-based configuration reader
type EnvVarConfigReader() =

  interface IConfigurationReader with
    member x.Name = "Environment Variables Configuration Reader"

    member x.GetValue(key: string) =
      Str.toUpper key |> FsRegEx.replace @"[^A-Z0-9_]+" "_" |> Env.getDefault ""

let parser = ArgumentParser.Create<AppConfig>(programName = "AutoMate")
let envReader = EnvVarConfigReader()

let parse args =
  parser.Parse(args, configurationReader = envReader)

let getAll args =
  let results = parse args
  results.GetAllResults()
