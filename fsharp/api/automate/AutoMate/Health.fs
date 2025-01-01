// https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring
// https://andrewlock.net/deploying-asp-net-core-applications-to-kubernetes-part-6-adding-health-checks-with-liveness-readiness-and-startup-probes/#the-three-kinds-of-probe-liveness-readiness-and-startup-probes
// TODO: Use bulitin health checks
//   https://github.com/Xabaril/AspNetCore.Diagnostics.HealthChecks
//   https://www.davidguida.net/health-checks-with-asp-net-core-and-kubernetes/
[<AutoOpen>]
module AutoMate.Health

open Falco
open Microsoft.Extensions.Logging
open Npgsql.FSharp

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
        deps.Logger.LogDebug("Handling startup health check")

        deps.Logger.LogDebug("Checking database health")
        let dbResult = checkDb deps.DbConn
        deps.Logger.LogDebug("Checked database health")

        match dbResult with
        | Ok dbCheck ->
          deps.Logger.LogDebug("Checked startup health - Healthy")

          Ok {
            Status = "Healthy"
            Results = { Database = Some dbCheck }
          }
        | Error dbCheck ->
          deps.Logger.LogWarning("Checked startup health - Unhealthy")

          Error {
            Status = "Unhealthy"
            Results = { Database = Some dbCheck }
          }

    let handleOk (health: Health) = Response.myOfJson health

    let handleError (health: Health) =
      Response.withStatusCode 503 >> Response.myOfJson health

    Deps.inject handleDepInj handleOk handleError ()

[<RequireQualifiedAccess>]
module Readiness =
  // TODO: latency for readiness checks? OS metrics?
  let handler: HttpHandler =
    let skippedCheck = {
      Status = "Skipped"
      Description = None
    }

    Response.myOfJson {
      Status = "Healthy"
      Results = { Database = Some skippedCheck }
    }

[<RequireQualifiedAccess>]
module Liveness =
  let handler: HttpHandler = Readiness.handler

let configHandler: HttpHandler =
  let handleDepInj deps input =
    deps.Logger.LogInformation("Config - {Config}", deps.Config)
    Ok "Successful"

  let handleOk msg = Response.ofPlainText msg

  let handleError msg =
    Response.withStatusCode 503 >> Response.ofPlainText msg

  Deps.inject handleDepInj handleOk handleError ()
