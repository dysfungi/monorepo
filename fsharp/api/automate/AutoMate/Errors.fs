[<AutoOpen>]
module AutoMate.Errors

open Falco
open Validus

type HandlerError =
  | QueryValidationError of ValidationErrors
  | BodyValidationError of ValidationErrors
  | DatabaseError of exn
  | NotImplemented of string
  | UnexpectedError of exn

type ErrorDetail = {
  Type: string
  Message: string
}

type ErrorDetails = ErrorDetail list

module ErrorDetails =
  let ofException (exc: exn) : ErrorDetails = [
    {
      Type = exc.GetType().FullName
      Message = exc.Message
    }
  ]

  let ofValidationErrors (subtype: string) validationErrors : ErrorDetails =
    validationErrors
    |> ValidationErrors.toMap
    |> Map.toList
    |> List.collect (fun (field, errors) -> [
      for error in errors do
        {
          Type = $"ValidationError[{subtype}:{field}]"
          Message = error
        }
    ])

type ErrorResponse = {
  Status: int
  Reason: string
  Errors: ErrorDetails
}

module ErrorResponse =
  let internal handle (statusCode: int) (statusReason: string) errors : HttpHandler =
    Response.withStatusCode statusCode
    >> Response.myOfJson {
      Status = statusCode
      Reason = statusReason
      Errors = errors
    }

  let badRequest: ErrorDetails -> HttpHandler = handle 400 "Bad Request"

  let validationErrors (subtype: string) : ValidationErrors -> HttpHandler =
    ErrorDetails.ofValidationErrors subtype >> badRequest

  let queryValidationErrors: ValidationErrors -> HttpHandler =
    validationErrors "Query"

  let bodyValidationErrors: ValidationErrors -> HttpHandler = validationErrors "Body"

  let notImplemented feature : HttpHandler =
    badRequest [
      {
        Type = "NotImplemented"
        Message = $"Not implemented for {feature}"
      }
    ]

  let internalServerError: ErrorDetails -> HttpHandler =
    handle 500 "Internal Server Error"

  let databaseError: exn -> HttpHandler =
    ErrorDetails.ofException >> internalServerError

  let unexpectedError: exn -> HttpHandler =
    ErrorDetails.ofException >> internalServerError

  let serviceUnavailable: ErrorDetails -> HttpHandler =
    handle 503 "Service Unavailable"

module ErrorController =
  let notFound: HttpHandler =
    Response.withStatusCode 404 >> Response.ofPlainText "Not Found"

  let unauthenticated: HttpHandler =
    Response.withStatusCode 401 >> Response.ofPlainText "Unauthenticated"

  let unauthorized: HttpHandler =
    Response.withStatusCode 403 >> Response.ofPlainText "Forbidden"
