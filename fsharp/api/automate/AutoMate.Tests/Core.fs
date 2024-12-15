[<AutoOpen>]
module AutoMate.Tests.Core

/// Wrap Expecto without need to supply `message` and enable currying by swapping `expected` and `actual` arguments.
[<RequireQualifiedAccess>]
module Want =
  open Expecto

  /// Want actual to equal expected.
  let equal (expected: 'T) (actual: 'T) =
    Expect.equal actual expected $"Wanted {actual} == {expected}"

  /// Want f to throw an exception.
  let throws f =
    Expect.throws f "Wanted a thrown exception"

  /// Want Some option and return wrapped value.
  let some opt =
    Expect.wantSome opt "Wanted Some option"

  /// Want Some option.
  let isSome opt = Expect.isSome opt "Wanted Some option"
  /// Want Ok result and return wrapped value.
  let ok result = Expect.wantOk result "Wanted Ok result"
  /// Want Ok result.
  let isOk result = Expect.isOk result "Wanted Ok result"

  /// Want Error result and return wrapped value.
  let error result =
    Expect.wantError result "Wanted Error result"

  /// Want Error result.
  let isError result =
    Expect.isError result "Wanted Error result"

[<RequireQualifiedAccess>]
module Server =
  // https://github.com/SchlenkR/FsHttp/blob/master/src/Tests/Helper/Server.fs
  open System.Threading
  open Suave

  type Route = {
    method: WebPart
    route: string
    handler: HttpRequest -> WebPart
  }

  let url (s: string) = $"http://127.0.0.1:8080{s}"

  let serve (app: WebPart) =
    let cts = new CancellationTokenSource()
    let conf = { defaultConfig with cancellationToken = cts.Token }
    let listening, server = startWebServerAsync conf app

    Async.Start(server, cts.Token)

    do
      listening
      |> Async.RunSynchronously
      |> Array.choose id
      |> Array.map (fun x -> x.binding |> string)
      |> String.concat "; "
      |> printfn "Server ready and listening on: %s"

    let dispose () =
      cts.Cancel()
      cts.Dispose()

    { new System.IDisposable with
        member this.Dispose() = dispose ()
    }
