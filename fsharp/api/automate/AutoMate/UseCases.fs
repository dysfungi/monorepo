module AutoMate.UseCases

open Falco

module Todoist =
  open AutoMate.Todoist

  let deserializeWebhookEvent body =
    SyncApi.WebhookEvent.Validate "body" body |> Result.mapError BodyValidationError

  let handleWebhookEvent: HttpHandler =
    // deserializeEvent
    // validateEvent
    // routeEvent
    //  syncComment
    // toResponse

    let handleDepInj deps body =
      deserializeWebhookEvent body
      |> Result.bind (function
        | SyncApi.ItemEvent _ -> Error(NotImplemented "Item Events")
        | SyncApi.NoteEvent noteEvent -> Ok noteEvent.EventData
      // Logseq.Page
      // enrich with more data (eg, task/item)
      // send to all sinks (ie, logseq)
      // transform to logseq document with Markdown doc provider
      // logseq stores with dropbox storage provider
      )

    let handleOk input =
      Response.withStatusCode 200 >> Response.myOfJson input

    let handleError =
      function
      | QueryValidationError validationErrors ->
        ErrorResponse.queryValidationErrors validationErrors
      | BodyValidationError validationErrors ->
        ErrorResponse.bodyValidationErrors validationErrors
      | DatabaseError exc -> ErrorResponse.databaseError exc
      | NotImplemented feature -> ErrorResponse.notImplemented feature
      | UnexpectedError exc -> ErrorResponse.unexpectedError exc

    Request.bodyString <| Deps.inject handleDepInj handleOk handleError
