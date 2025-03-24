module AutoMate.UseCases

open Falco

module Todoist =
  open AutoMate.NoteSyncing.DomainFunctions
  open AutoMate.Todoist
  open FSharp.Formatting.Markdown

  let handleWebhookEvent: HttpHandler =
    // deserializeEvent
    // validateEvent
    // routeEvent
    //  syncComment
    // toResponse

    let handleDepInj deps body =
      result {
        let! receivedEvent =
          SyncApi.WebhookEvent.Validate "body" body
          |> Result.mapError BodyValidationError

        let! todoistEvent =
          match receivedEvent with
          | SyncApi.ItemEvent _ -> NotImplemented "TODO" |> Error
          | SyncApi.NoteEvent noteEvent ->
            Todoist.TaskCommentEvent.fromNoteEventDto noteEvent

        let! logseqPage = Logseq.Page.fromTodoistTaskComment todoistEvent

        // Logseq.Page
        // enrich with more data (eg, task/item)
        // send to all sinks (ie, logseq)
        // transform to logseq document with Markdown doc provider
        // logseq stores with dropbox storage provider

        return logseqPage
      }

    let handleOk result =
      Response.withStatusCode 200 >> Response.myOfJson result

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
