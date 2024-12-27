module Falco.FSharpJson

open AutoMate.Utilities
open Falco
open System.Text

module Respond =
  let ofJson (obj: 'T) : HttpHandler =
    // https://github.com/pimbrouwers/Falco/blob/25d828d832c0fde2dfff04775bea1eced9050458/src/Falco/Response.fs#L200
    Response.withContentType "applicaton/json; charset=utf-8"
    >> (Json.serialize >> Response.ofString Encoding.UTF8) obj
