[<AutoOpen>]
module AutoMate.FsHttpExtensions

open FsHttp

module Response =
  let myToJson<'T> response =
    response |> Response.toText |> Json.deserialize<'T>
