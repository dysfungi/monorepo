module AutoMate.Config

open Argu
open AutoMate.Utilities
open FsConfig


type DatabaseConfig = {
  [<DefaultValue("automate_app")>]
  Name: string
  Host: string
  Password: string
  [<DefaultValue("5432")>]
  Port: int
  [<DefaultValue("automate_api")>]
  Username: string
}

type AppConfig = { Database: DatabaseConfig }

let load () =
  match EnvConfig.Get<AppConfig>() with
  | Ok config -> config
  | Error error ->
    match error with
    | NotFound envVarName -> failwith $"Environment variable {envVarName} not found"
    | BadValue(envVarName, value) ->
      failwith $"Environment variable {envVarName} has invalid value {value}"
    | NotSupported msg -> failwith msg

module Cli =
  type Args =
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

  let parser = ArgumentParser.Create<Args>(programName = "AutoMate")
  let envReader = EnvVarConfigReader()

  let parse args =
    parser.Parse(args, configurationReader = envReader)

  let getAll args =
    let results = parse args
    results.GetAllResults()
