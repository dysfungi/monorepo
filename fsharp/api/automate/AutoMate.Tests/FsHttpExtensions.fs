module AutoMate.Tests.FsHttpExtensions

open AutoMate.FsHttpExtensions
open AutoMate.Tests.Core
open AutoMate.Utilities
open Expecto
open FsHttp
open Suave
open Suave.Operators
open Suave.Filters
open Suave.Successful

[<Tests>]
let responseTests =
  testList "Response" [
    testList "myToJson" [
      testCase "pass"
      <| fun _ ->
        let expected = {| Foo = "bar" |}
        let input = Json.serialize expected
        use server = GET >=> request (fun _ -> input |> OK) |> Server.serve

        let output =
          get <| Server.url @"" |> Request.send |> Response.myToJson |> Want.ok

        Want.equal expected output

    (* TODO: fix "Address already in use" issue with Server.serve
      testCase "fail when cannot deserialize"
      <| fun _ ->
        let input = "foo"
        use server = GET >=> request (fun _ -> input |> OK) |> Server.serve

        let output =
          get <| Server.url @""
          |> Request.send
          |> Response.myToJson
        Want.isError output
      *)

    ]
  ]
