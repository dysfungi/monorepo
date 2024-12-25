// https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring
// https://andrewlock.net/deploying-asp-net-core-applications-to-kubernetes-part-6-adding-health-checks-with-liveness-readiness-and-startup-probes/#the-three-kinds-of-probe-liveness-readiness-and-startup-probes
// TODO: Use bulitin health checks
//   https://github.com/Xabaril/AspNetCore.Diagnostics.HealthChecks
//   https://www.davidguida.net/health-checks-with-asp-net-core-and-kubernetes/
[<AutoOpen>]
module AutoMate.Health

open Falco
open FSharp.Json
open Npgsql.FSharp
open System.Text

let defaultJsonConfig = JsonConfig.create (jsonFieldNaming = Json.snakeCase)

let serialize data = Json.serializeEx defaultJsonConfig data

let deserialize<'T> json =
  try
    Ok <| Json.deserializeEx<'T> defaultJsonConfig json
  with ex ->
    Error ex

module Respond =
  let ofJson (obj: 'T) : HttpHandler =
    // https://github.com/pimbrouwers/Falco/blob/25d828d832c0fde2dfff04775bea1eced9050458/src/Falco/Response.fs#L200
    Response.withContentType "applicaton/json; charset=utf-8"
    >> (serialize >> Response.ofString Encoding.UTF8) obj

type HealthCheck = {
  Status: string
  Description: string option
}

type HealthCheckResults = { Database: HealthCheck option }

type Health = {
  Status: string
  Results: HealthCheckResults
}

[<RequireQualifiedAccess>]
module Startup =
  let handler: HttpHandler =
    let checkDb dbConn =
      try
        dbConn
        |> Sql.existingConnection
        |> Sql.query "SELECT 'Healthy' AS status"
        |> Sql.executeRow (fun read -> read.string "status")
        |> fun status ->
            Ok {
              Status = status
              Description = None
            }
      with ex ->
        Error {
          Status = "Unhealthy"
          Description = Some ex.Message
        }

    let handleDepInj: DependencyInjectionHandler<unit, Health, Health> =
      fun deps input ->
        let dbResult = checkDb deps.DbConn

        match dbResult with
        | Ok dbCheck ->
          Ok {
            Status = "Healthy"
            Results = { Database = Some dbCheck }
          }
        | Error dbCheck ->
          Error {
            Status = "Unhealthy"
            Results = { Database = Some dbCheck }
          }

    let handleOk (health: Health) = Respond.ofJson health

    let handleError (health: Health) =
      Response.withStatusCode 503 >> Respond.ofJson health

    Deps.inject handleDepInj handleOk handleError ()

[<RequireQualifiedAccess>]
module Readiness =
  // TODO: latency for readiness checks? OS metrics?
  let handler: HttpHandler =
    let skippedCheck = {
      Status = "Skipped"
      Description = None
    }

    Respond.ofJson {
      Status = "Healthy"
      Results = { Database = Some skippedCheck }
    }

[<RequireQualifiedAccess>]
module Liveness =
  let handler: HttpHandler = Readiness.handler
