module AutoMate.Tests.NoteSyncing

open AutoMate.NoteSyncing
open AutoMate.NoteSyncing.DomainFunctions
open AutoMate.NoteSyncing.DomainTypes
open Expecto
open FSharp.Formatting.Markdown
open System

[<Tests>]
let logseqPageTests =

  testList "fromTodoistTaskComment" [
    testCase "success"
    <| fun _ ->
      let input =
        Todoist.TaskCommentAdded {
          Id = "3651431408"
          CreatedAt = DateTimeOffset.Parse "2024-08-10T17:12:50.068600Z"
          Creator = {
            Id = "40102343"
            Email = "someone@example.com"
            FullName = "Some Juan"
          }
          TaskId = "8283578355"
          Content = Markdown.Parse "Foo Bar:\n- Baz\n- Egg\n- Spam\n\nLorem ipsum."
        }

      let output = Logseq.Page.fromTodoistTaskComment input

      let expected: Logseq.Page = {
        Name = Logseq.PageReference "todoist/comment/3651431408"
        Properties = [
          Logseq.PageRefTags [ Logseq.PageReference "todoist/task/8283578355" ]
          Logseq.CreatedOn <| Logseq.JournalReference "2024-08-10"
        ]
        Blocks = [
          {
            Properties = []
            Content = "- Foo Bar:\n- Baz\n- Egg\n- Spam \n\n\n- Lorem ipsum.\n\n"
            Blocks = []
          }
        ]
      }

      let o =
        match output with
        | Ok v -> v
        | Error e -> failwith "uhoh"

      Want.equal expected.Name o.Name
      Want.equal expected.Properties o.Properties
      Want.equal expected.Blocks[0].Properties o.Blocks[0].Properties
      Want.equal expected.Blocks[0].Content o.Blocks[0].Content
      Want.equal expected.Blocks[0].Blocks o.Blocks[0].Blocks
  //Want.equal expected.Blocks[0] o.Blocks[0]
  //Want.equal expected.Blocks o.Blocks
  //Want.equal (Ok expected) output
  ]
