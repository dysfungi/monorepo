module AutoMate.Tests.Todoist

open Expecto

type TDeserialize = {
  Nested: {|
    String: string
    Number: int
  |}
  SnakeCase: bool option
}

[<Tests>]
let todoistTests =
  testList "Todoist" [
    testCase "JSON serialize" (fun _ ->
      let input = {|
        Nested = {|
          String = "foo"
          Number = 2
        |}
        SnakeCase = "foo bar"
      |}

      let output = AutoMate.Integrations.Todoist.serialize input

      let expected =
        """{
  "nested": {
    "number": 2,
    "string": "foo"
  },
  "snake_case": "foo bar"
}"""

      Expect.equal output expected "Bad serialize")

    testCase "JSON deserialize" (fun _ ->
      let input = """{"nested":{"string":"foo","number":2},"snake_case": null}"""

      let output = AutoMate.Integrations.Todoist.deserialize<TDeserialize> input

      let expected = {
        Nested = {|
          String = "foo"
          Number = 2
        |}
        SnakeCase = None
      }

      let output' = Expect.wantOk output "Bad deserialize"
      Expect.equal output' expected "Bad deserialize")

    testCase "WebhookEvent.Validate note:added" (fun _ ->
      let input =
        """
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
        """

      let output =
        AutoMate.Integrations.Todoist.SyncApiV9.WebhookEvent.Validate "test" input

      Expect.isOk output "Bad validate")
  ]
