module AutoMate.Todoist

open System
open System.Text.Json
open System.Text.Json.Serialization

open Falco

let jsonOptions =
  // https://learn.microsoft.com/en-us/dotnet/api/system.text.json.jsonserializeroptions
  let options = JsonFSharpOptions.Default().ToJsonSerializerOptions()
  options.AllowTrailingCommas <- true
  // https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/customize-properties?pivots=dotnet-8-0#enums-as-strings
  JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower)
  |> options.Converters.Add

  options.PropertyNameCaseInsensitive <- true
  // https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/customize-properties?pivots=dotnet-8-0#use-a-custom-json-property-naming-policy
  options.PropertyNamingPolicy <- JsonNamingPolicy.SnakeCaseLower
  options.ReadCommentHandling <- JsonCommentHandling.Skip
  // TODO: options.WriteIndented <- true
  options

(*
BLOCK_LINE = re.compile(r"\s[-*] ")


"""
https://developer.todoist.com/sync/v9/#request-format

json = {
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
"""
def main(event: dict) -> dict:
    """
    https://developer.todoist.com/appconsole.html
    """
    comment_event = TodoistEvent.model_validate(event)
    return {
        "path": get_path(comment_event),
        "content": get_content(comment_event),
    }


def get_path(event: TodoistEvent) -> str:
    return f"/notes/pages/todoist___comment___{event.event_data.id}.md"


def get_content(event: TodoistEvent) -> str:
    created = event.event_data.posted_at.date().isoformat()
    updated = event.triggered_at.date().isoformat()
    tags = {
        created,
        updated,
        f"todoist/task/{event.event_data.task_id}",
    }
    content = textwrap.indent(
        event.event_data.content,
        "  ",
        lambda line: BLOCK_LINE.match(line) is None
    )
    content = textwrap.indent(content, "- ", lambda line: BLOCK_LINE.match(line) is not None)
    content = "\n".join([
        f"tags:: {', '.join(tags)}",
        f"created:: {created}",
        f"updated:: {updated}",
        "",
        f"- [Comment in Todoist]({event.event_data.url})",
        content,
        "",
    ])
    return content


def get_task(comment_event: TodoistEvent) -> Task:
    token = wmill.get_variable("u/dmf/todoist-app-token")
    if comment_event.event_data.task is None:
        response = httpx.get(
            f"https://api.todoist.com/rest/v2/tasks/{item_id}",
            headers={"Authorization": f"Bearer {token}"},
            follow_redirects=True,
        )
        task = Task.validate_model(response.json())
    else:
        task = comment_event.event_data.task
    return task
 *)

type Initiator = {
  Id: string
  Email: string
  FullName: string
}

type Task = {
  Id: string
  ParentId: string option
  SectionId: string option
  ProjectId: string
  Priority: int
  Labels: int list
  IsDeleted: bool
  CompletedAt: DateTime option
  Content: string
  Description: string
}

type EventData = {
  Id: string
  Url: string
  IsDeleted: bool
  TaskId: string
  //Task: Task option
  PostedAt: DateTime
}

type WebhookEvent = {
  Version: string
  UserId: string
  TriggeredAt: DateTime
  Initiator: Initiator
  // https://developer.todoist.com/sync/v9/#webhooks
  EventName: string
  EventData: EventData
}

module WebhookEvent =

  type EventHandled = { Status: string }

  let success = { Status = "successful" }
  let failure = { Status = "failure" }
  let unsupported = { Status = "ignored" }

  let handler: HttpHandler =
    fun ctx ->
      let handleOk (event: WebhookEvent) : HttpHandler =
        printfn "%A" event

        let result =
          match event with
          | { EventName = "note:added" } -> success
          | { EventName = "note:updated" } -> success
          | { EventName = "note:deleted" } -> unsupported
          | _ -> unsupported

        // Response.ofJson {}
        // Response.ofJson Seq.empty
        Response.ofJson result

      Request.mapJsonOption jsonOptions handleOk ctx
