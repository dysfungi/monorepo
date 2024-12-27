[<AutoOpen>]
module AutoMate.Errors

open Falco
open Falco.FSharpJson

type ErrorResponse = {
  Status: int
  Error: string
  Message: string
}

module ErrorResponse =
  let internal handle (status: int) (error: string) (exc: exn) : HttpHandler =
    Response.withStatusCode status
    >> Respond.ofJson {
      Status = status
      Error = error
      Message = string (exc)
    }

  let badRequest (exc: exn) : HttpHandler = handle 400 "Bad Request" exc

  let internalServerError (exc: exn) : HttpHandler =
    handle 500 "Internal Server Error" exc

  let serviceUnavailable (exc: exn) : HttpHandler = handle 503 "Service Unavailable" exc
