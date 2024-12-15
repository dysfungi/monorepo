module FsHttp.FSharpJson

open AutoMate.Utilities

module Response =

  let toJson<'T> response =
    response |> FsHttp.Response.toText |> Json.deserialize<'T>
