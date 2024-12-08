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


(*
module Respond =
  let ofJsonConfig (config: JsonConfig) (obj: 'T) : HttpHandler =
    let jsonHandler : HttpHandler =
      Json.serializeEx<'T> config obj

    Response.withContentType "applicaton/json; charset=utf-8"
    >> jsonHandler
    >> Response.ofString Encoding.UTF8

  let ofJson (obj: 'T) : HttpHandler =
    // https://github.com/pimbrouwers/Falco/blob/25d828d832c0fde2dfff04775bea1eced9050458/src/Falco/Response.fs#L200
    withContentType "application/json; charset=utf-8"
    >> ofJsonConfig Receive.defaultJsonConfig obj
  *)


type Alive = { Status: string }
type Ready = { Status: string }
type Startup = { Status: string }

[<RequireQualifiedAccess>]
module Alive =
  let handle: HttpHandler =
    //Respond.ofJson { Status = "OK" }
    Response.withContentType "application/json; charset=utf-8"
    >> (serialize >> Response.ofString Encoding.UTF8) { Status = "OK" }

[<RequireQualifiedAccess>]
module Ready =
  let handle: HttpHandler =
    //Respond.ofJson { Status = "OK" }
    Response.withContentType "application/json; charset=utf-8"
    >> (serialize >> Response.ofString Encoding.UTF8) { Status = "OK" }

[<RequireQualifiedAccess>]
module Startup =
  let handle: HttpHandler =
    //Respond.ofJson { Status = "OK" }
    Response.withContentType "application/json; charset=utf-8"
    >> (serialize >> Response.ofString Encoding.UTF8) { Status = "OK" }
