module AutoMate.Todoist

open AutoMate.Utilities
open Falco
open System
open Validus
open Validus.Operators

[<RequireQualifiedAccess>]
module RestApi =

  [<RequireQualifiedAccess>]
  module V2 =
    type TaskDueDto = {
      String: string
      Date: DateOnly
      IsRecurring: bool
      Datetime: DateTime option
      Timezone: string option
    }

    type TaskDurationDto = {
      Amount: int
      Unit: string
    }

    type TaskDto =
      // https://developer.todoist.com/rest/v2/#tasks
      {
        Id: string
        ProjectId: string
        SectionId: string option
        ParentId: string option
        CreatorId: string
        AssigneeId: string
        AssignerId: string
        Url: Uri
        Order: int
        Priority: int
        CommentCount: int
        Labels: string list
        IsCompleted: bool
        CreatedAt: DateTime
        Due: TaskDueDto option
        Duration: TaskDurationDto option
        Content: string
        Description: string
      }

[<RequireQualifiedAccess>]
module SyncApi =

  [<RequireQualifiedAccess>]
  module V9 =
    type ItemDto =
      // https://developer.todoist.com/sync/v9/#items
      {
        Id: string
        [<Json.Field("v2_id")>]
        V2Id: string
        ParentId: string option
        [<Json.Field("v2_parent_id")>]
        V2ParentId: string option
        SectionId: string option
        [<Json.Field("v2_section_id")>]
        V2SectionId: string option
        ProjectId: string
        [<Json.Field("v2_project_id")>]
        V2ProjectId: string option
        UserId: string
        ChildOrder: int
        Priority: int
        Labels: string list
        Checked: bool
        IsDeleted: bool
        AddedAt: DateTime
        UpdatedAt: DateTime
        Due: DateTime option
        CompletedAt: DateTime option
        Content: string
        Description: string
      }

    type NoteFileAttachmentDto = {
      /// The name of the file.
      FileName: string
      /// The size of the file in bytes.
      FileSize: int
      /// MIME type.
      FileType: string
      /// The URL where the file is located.
      FileUrl: Uri
      /// Upload completion state.
      UploadState: string
    }

    type NoteReactionsDto = Map<string, string list>

    type NoteDto =
      // https://developer.todoist.com/sync/v9/#notes
      {
        /// The ID of the note.
        Id: string
        /// The ID of the user that posted the note.
        PostedUid: string
        /// The item which the note is part of.
        ItemId: string
        /// Whether the note is marked as deleted.
        IsDeleted: bool
        /// The date when the note was posted.
        PostedAt: string
        /// The content of the note.
        Content: string
        /// A file attached to the note.
        FileAttachment: NoteFileAttachmentDto option
        /// A list of user IDs to notify.
        UidsToNotify: string array option
        /// List of emoji reactions and corresponding user IDs.
        Reactions: NoteReactionsDto option
        /// The item which the note is part of.
        Item: ItemDto option
      }

    type InitiatorDto = {
      Id: string
      Email: string
      FullName: string
    }

    type ItemWebhookEventDto = {
      Version: string
      EventName: string
      UserId: string
      TriggeredAt: DateTime
      Initiator: InitiatorDto
      EventData: ItemDto
    }

    type NoteWebhookEventDto = {
      Version: string
      EventName: string
      UserId: string
      TriggeredAt: DateTime
      Initiator: InitiatorDto
      EventData: NoteDto
    }

  type WebhookEventPeek = {
    Version: string
    EventName: string
  }

  type WebhookEvent =
    | ItemEvent of V9.ItemWebhookEventDto
    | NoteEvent of V9.NoteWebhookEventDto

    static member Validate: Validator<string, WebhookEvent> =
      fun field input ->
        let v9 eventName body =
          match eventName with
          | "note:added"
          | "note:updated" ->
            (Json.deserializeValidator<V9.NoteWebhookEventDto> *|* NoteEvent)
              "body"
              body
          | "item:added"
          | "item:updated" ->
            (Json.deserializeValidator<V9.ItemWebhookEventDto> *|* ItemEvent)
              "body"
              body
          | _ ->
            Error
            <| ValidationErrors.create "event_name" [
              $"unsupported event_name: {eventName}"
            ]

        validate {
          let! eventPeek = Json.deserializeValidator<WebhookEventPeek> "body" input

          let! event =
            match eventPeek.Version with
            | "9" -> v9 eventPeek.EventName input
            | _ ->
              Error
              <| ValidationErrors.create "version" [
                $"unsupported version: {eventPeek.Version}"
              ]

          return event
        }

  module WebhookEvent =
    // https://developer.todoist.com/sync/v9/#request-format
    let versionValidator = Check.String.equals "9" *|* int

    let handler: HttpHandler =
      fun ctx ->
        let handleBody (body: string) : HttpHandler =
          printfn "%A" body

          WebhookEvent.Validate "body" body
          |> function
            | Error _ ->
              Response.withStatusCode 400 >> Response.ofPlainText "Bad Request"
            | _ -> Response.withStatusCode 200 >> Response.ofPlainText "OK"

        Request.bodyString handleBody ctx
