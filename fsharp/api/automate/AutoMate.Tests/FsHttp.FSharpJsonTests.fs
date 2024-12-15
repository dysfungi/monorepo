module AutoMate.Tests.FsHttp.FSharpJson

open AutoMate.Tests.Core
open AutoMate.Utilities
open Expecto
open FsHttp
open FsHttp.FSharpJson.Response
open Suave
open Suave.Operators
open Suave.Filters
open Suave.Successful

[<Tests>]
let responseTests =
  testList "Response" [
    testList "toJson" [
      testCase "pass"
      <| fun _ ->
        let expected = {| Foo = "bar" |}
        let input = Json.serialize expected
        use server = GET >=> request (fun _ -> input |> OK) |> Server.serve

        let output = get <| Server.url @"" |> Request.send |> toJson |> Want.ok
        Want.equal expected output
        server.Dispose()

    (* TODO: fix "Address already in use" issue with Server.serve
      testCase "fail when cannot deserialize"
      <| fun _ ->
        let input = "foo"
        use server = GET >=> request (fun _ -> input |> OK) |> Server.serve

        let output =
          get <| Server.url @""
          |> Request.send
          |> toJson
        Want.isError output
        server.Dispose()
      *)

    ]
  ]
