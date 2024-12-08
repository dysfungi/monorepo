// https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring
// https://andrewlock.net/deploying-asp-net-core-applications-to-kubernetes-part-6-adding-health-checks-with-liveness-readiness-and-startup-probes/#the-three-kinds-of-probe-liveness-readiness-and-startup-probes
[<AutoOpen>]
module AutoMate.Health

open Falco
open FSharp.Json
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

type Alive = { Status: string }
type Ready = { Status: string }
type Startup = { Status: string }

[<RequireQualifiedAccess>]
module Alive =
  let handle: HttpHandler = Respond.ofJson { Status = "OK" }

[<RequireQualifiedAccess>]
module Ready =
  // TODO: latency for readiness checks? OS metrics?
  let handle: HttpHandler = Respond.ofJson { Status = "OK" }

[<RequireQualifiedAccess>]
module Startup =
  let handle: HttpHandler = Respond.ofJson { Status = "OK" }
