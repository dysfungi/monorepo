[<RequireQualifiedAccess>]
module AutoMate.Integrations.Todoist

open Falco
open FSharp.Json
open System
open Validus
open Validus.Operators

let jsonConfig = JsonConfig.create (jsonFieldNaming = Json.snakeCase)

let serialize data = Json.serializeEx jsonConfig data

let deserialize<'T> json =
  try
    Json.deserializeEx<'T> jsonConfig json |> Ok
  with ex ->
    Error ex

let deserializeValidator<'T> field input =
  input
  |> deserialize<'T>
  |> Result.mapError (fun e -> ValidationErrors.create field [ e.Message ])

[<RequireQualifiedAccess>]
module RestApiV2 =
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
module SyncApiV9 =
  type ItemDto =
    // https://developer.todoist.com/sync/v9/#items
    {
      Id: string
      V2Id: string
      ParentId: string option
      SectionId: string option
      ProjectId: string
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
    }

  type InitiatorDto = {
    Id: string
    Email: string
    FullName: string
  }

  type WebhookEventPeek = {
    Version: string
    EventName: string
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

  type WebhookEvent =
    | ItemEvent of ItemWebhookEventDto
    | NoteEvent of NoteWebhookEventDto

    static member Validate: Validator<string, WebhookEvent> =
      fun field input ->
        validate {
          let! eventPeek = deserializeValidator<WebhookEventPeek> "body" input

          return!
            match eventPeek.Version with
            | "9" ->
              match eventPeek.EventName with
              | "note:added"
              | "note:updated" ->
                deserializeValidator<NoteWebhookEventDto> "body" input
                |> Result.map (NoteEvent)
              | _ ->
                Error
                <| ValidationErrors.create "event_name" [
                  $"unsupported event_name: {eventPeek.EventName}"
                ]
            | _ ->
              Error
              <| ValidationErrors.create "version" [
                $"unsupported version: {eventPeek.Version}"
              ]
        }

  module WebhookEvent =
    // https://developer.todoist.com/sync/v9/#request-format
    (*
      {
        "triggered_at": "2024-10-30T13:56:25.601532Z",
        "initiator": {
          "id": "40102343",
          "email": "derek+todoist@frank.sh",
          "image_id": "86d065186f7a4073af86a5b4921e97b4",
          "full_name": "Derek",
          "is_premium": true
        },
        "event_name": "note:added",
        "event_data": {
          "id": "3651431408",
          "url": "https://app.todoist.com/app/task/8283578355",
          "item": {
            "id": "8283578355",
            "due": null,
            "v2_id": "6Vx3G2XJcJPxfvcG",
            "labels": [],
            "checked": false,
            "content": "Sync new comments from Todoist to Logseq",
            "sync_id": null,
            "user_id": "40102343",
            "added_at": "2024-08-10T17:12:50.068600Z",
            "deadline": null,
            "duration": null,
            "priority": 4,
            "collapsed": false,
            "parent_id": null,
            "is_deleted": false,
            "project_id": "2337670886",
            "section_id": "163355751",
            "updated_at": "2024-10-19T13:38:58Z",
            "child_order": 2,
            "description": "TBD: where are comments stored in Logseq?\n\nBlocked: on infrastructure setup",
            "added_by_uid": "40102343",
            "completed_at": null,
            "v2_parent_id": null,
            "v2_project_id": "6Vx3Cf3QvmqjR7vG",
            "v2_section_id": "6Vx3FmfM9xJQwqrp",
            "assigned_by_uid": null,
            "responsible_uid": null
          },
          "v2_id": "6WVxFjgm4pPpPMGG",
          "content": "test 6",
          "item_id": "8283578355",
          "posted_at": "2024-10-30T13:56:24.766000Z",
          "reactions": null,
          "is_deleted": false,
          "posted_uid": "40102343",
          "v2_item_id": "6Vx3G2XJcJPxfvcG",
          "v2_project_id": "6Vx3Cf3QvmqjR7vG",
          "uids_to_notify": null,
          "file_attachment": null
        },
        "user_id": "40102343",
        "version": "9"
      }
    *)

    let versionValidator = Check.String.equals "9" *|* int

    let handler: HttpHandler =
      fun ctx ->
        let handleBody (body: string) : HttpHandler =
          printfn "%A" body
          let result = WebhookEvent.Validate "body" body

          match result with
          | Error _ -> Response.withStatusCode 400 >> Response.ofPlainText "Bad Request"
          | _ -> Response.withStatusCode 200 >> Response.ofPlainText "OK"

        Request.bodyString handleBody ctx
