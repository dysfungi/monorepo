namespace AutoMate.NoteSyncing

open AutoMate.Utilities
open System
open System.Text.RegularExpressions
open FSharp.Formatting.Markdown
open FsRegEx

module DomainTypes =
  module Todoist =
    // data types
    type User = {
      Id: string
      Email: string
      FullName: string
    }

    type PersonalLabel = UNDEFINED
    type SharedLabel = UNDEFINED
    type Project = UNDEFINED
    type ProjectComment = UNDEFINED
    type Section = UNDEFINED
    type TaskTitle = TaskTitle of string
    type Task = UNDEFINED
    type TaskComment = UNDEFINED

    // event types
    type TaskAdded = UNDEFINED
    type TaskUpdated = UNDEFINED
    type TaskDeleted = UNDEFINED
    type TaskCompleted = UNDEFINED
    type TaskUncompleted = UNDEFINED
    type TaskCommentAdded = UNDEFINED
    type TaskCommentUpdated = UNDEFINED
    type TaskCommentDeleted = UNDEFINED

    // event data types
    type NewTask = {
      Id: string
      CreatedAt: DateTimeOffset
      Creator: User
      Title: TaskTitle
      Description: MarkdownDocument
    }

    type UpdatedTask = UNDEFINED
    type DeletedTask = UNDEFINED
    type CompletedTask = UNDEFINED
    type UncompletedTask = UNDEFINED

    type NewTaskComment = {
      Id: string
      CreatedAt: DateTimeOffset
      Creator: User
      TaskId: string
      Content: MarkdownDocument
    }

    type EditedTaskComment = {
      Id: string
      CreatedAt: DateTimeOffset
      CreatorId: string
      EditedAt: DateTimeOffset
      Editor: User
      TaskId: string
      Content: MarkdownDocument
    }

    type DeletedTaskComment = {
      Id: string
      CreatedAt: DateTimeOffset
      CreatorId: string
      DeletedAt: DateTimeOffset
      Deleter: User
      TaskId: string
      Content: MarkdownDocument
    }

    type TaskCommentEvent =
      | TaskCommentAdded of NewTaskComment
      | TaskCommentUpdated of EditedTaskComment
      | TaskCommentDeleted of DeletedTaskComment

  module Logseq =
    // data types
    type PageReferences = PageReference list
    and PageReference = PageReference of string

    type JournalReferences = JournalReference list
    and JournalReference = JournalReference of string

    type StringWithRefs = StringWithRefsToken list

    and StringWithRefsToken =
      | String of string
      | BracketPageReference of PageReference
      | HashPageReference of PageReference
      | HashBracketPageReference of PageReference
      | BracketJournalReference of JournalReference
      | HashJournalReference of JournalReference
      | HashBracketJournalReference of JournalReference

    type ListType =
      | OrderedList of OrderedListType
      | UnorderedList of UnorderedListType

    and OrderedListType =
      // https://docs.logseq.com/#/page/numbered list
      | NumberedList

    and UnorderedListType = | BulletedList

    /// Block properties are defined by putting them into any other block aside from the page frontmatter
    type BlockProperties = BlockProperty list

    and BlockProperty =
      // https://docs.logseq.com/#/page/properties
      // Built-in
      | OrderListType of OrderedListType
    // Custom

    type Blocks = Block list

    and Block = {
      Properties: BlockProperties
      Content: string
      Blocks: Blocks
    }

    /// Page properties are defined by putting them in the first block of the page (frontmatter)
    type Frontmatter = PageProperties

    and PageProperties = PageProperty list

    and PageProperty =
      // https://docs.logseq.com/#/page/properties
      // Built-in
      | Aliases of PageReferences
      | PageRefTags of PageReferences
      // Custom
      | CreatedOn of JournalReference
      | UpdatedOn of JournalReference

    type Pages = Page list

    and Page = {
      Name: PageReference
      Properties: Frontmatter
      Blocks: Blocks
    }

    type Journals = Journal list

    and Journal = {
      Name: JournalReference
      Properties: Frontmatter
      Blocks: Blocks
    }

    type TodoistUserPage = UNDEFINED
    type TodoistPersonalLabelPage = UNDEFINED
    type TodoistSharedLabelPage = UNDEFINED
    type TodoistProjectPage = UNDEFINED
    type TodoistSectionPage = UNDEFINED
    type TodoistTaskPage = UNDEFINED
    type TodoistTaskCommentPage = UNDEFINED

  // behavior types
  type TodoistUserToLogseqPage = Todoist.User -> Logseq.Page
  type TodoistPersonalLabelToLogseqPage = Todoist.PersonalLabel -> Logseq.Page
  type TodoistSharedLabelToLogseqPage = Todoist.SharedLabel -> Logseq.Page
  type TodoistProjectCommentToLogseqPage = Todoist.ProjectComment -> Logseq.Page
  type TodoistProjectToLogseqPage = Todoist.Project -> Logseq.Page
  type TodoistSectionToLogseqPage = Todoist.Section -> Logseq.Page
  type TodoistTaskToLogseqPage = Todoist.Task -> Logseq.Page
  type TodoistTaskCommentToLogseqPage = Todoist.TaskComment -> Logseq.Page

module DomainFunctions =
  open AutoMate.Errors
  open AutoMate.Todoist

  module Todoist =

    open DomainTypes.Todoist

    [<RequireQualifiedAccess>]
    module TaskCommentEvent =

      let fromNoteEventDto
        (dto: SyncApi.V9.NoteWebhookEventDto)
        : Result<TaskCommentEvent, HandlerError> =
        match dto.EventName with
        | "item:added" ->
          TaskCommentAdded {
            Id = dto.EventData.Id
            CreatedAt = dto.EventData.PostedAt
            Creator = {
              Id = dto.EventData.PostedUid
              Email = dto.Initiator.Email
              FullName = dto.Initiator.FullName
            }
            TaskId = dto.EventData.ItemId
            Content = Markdown.Parse dto.EventData.Content
          }
          |> Ok
        | "item:updated" ->
          TaskCommentUpdated {
            Id = dto.EventData.Id
            CreatedAt = dto.EventData.PostedAt
            CreatorId = dto.EventData.PostedUid
            EditedAt = dto.TriggeredAt
            Editor = {
              Id = dto.Initiator.Id
              Email = dto.Initiator.Email
              FullName = dto.Initiator.FullName
            }
            TaskId = dto.EventData.ItemId
            Content = Markdown.Parse dto.EventData.Content
          }
          |> Ok
        | "item:deleted" ->
          TaskCommentDeleted {
            Id = dto.EventData.Id
            CreatedAt = dto.EventData.PostedAt
            CreatorId = dto.EventData.PostedUid
            DeletedAt = dto.TriggeredAt
            Deleter = {
              Id = dto.Initiator.Id
              Email = dto.Initiator.Email
              FullName = dto.Initiator.FullName
            }
            TaskId = dto.EventData.ItemId
            Content = Markdown.Parse dto.EventData.Content
          }
          |> Ok
        | _ -> NotImplemented "TODO" |> Error

  module Logseq =
    open DomainTypes.Logseq
    open DomainTypes.Todoist

    [<RequireQualifiedAccess>]
    module Page =

      let journalNameFromDateTimeOffset (date: DateTimeOffset) : JournalReference =
        date.ToString "yyyy-MM-dd" |> JournalReference

      let fromTodoistTaskComment
        (commentEvent: TaskCommentEvent)
        : Result<Page, HandlerError> =
        let commentPageName =
          match commentEvent with
          | TaskCommentAdded { Id = commentId }
          | TaskCommentUpdated { Id = commentId }
          | TaskCommentDeleted { Id = commentId } ->
            PageReference $"todoist/comment/{commentId}"

        let taskPageName =
          match commentEvent with
          | TaskCommentAdded { TaskId = taskId }
          | TaskCommentUpdated { TaskId = taskId }
          | TaskCommentDeleted { TaskId = taskId } ->
            PageReference $"todoist/task/{taskId}"

        let frontmatter = [
          PageRefTags [ taskPageName ]
          CreatedOn
          <| match commentEvent with
             | TaskCommentAdded { CreatedAt = commentCreatedAt }
             | TaskCommentUpdated { CreatedAt = commentCreatedAt }
             | TaskCommentDeleted { CreatedAt = commentCreatedAt } ->
               journalNameFromDateTimeOffset commentCreatedAt
        ]

        let contentBlock = {
          Properties = []
          Content =
            match commentEvent with
            | TaskCommentAdded { Content = doc }
            | TaskCommentUpdated { Content = doc }
            | TaskCommentDeleted { Content = doc } ->
              let paragraphs = [
                MarkdownParagraph.ListBlock(
                  MarkdownListKind.Unordered,
                  [ for p in doc.Paragraphs -> [ p ] ],
                  None
                )
              ]

              let listBlocksWithDashes (m: Match) = Str.replace "*" "-" m.Value

              MarkdownDocument(paragraphs, doc.DefinedLinks)
              |> Markdown.ToMd
              |> FsRegEx.replaceByMatchOpt
                @"^\s*[*] "
                RegexOptions.Multiline
                listBlocksWithDashes
          Blocks = []
        }

        let blocks = [ contentBlock ]

        match commentEvent with
        | TaskCommentAdded _ ->
          {
            Page.Name = commentPageName
            Properties = frontmatter
            Blocks = blocks
          }
          |> Ok
        | TaskCommentUpdated comment ->
          {
            Page.Name = commentPageName
            Properties =
              List.append frontmatter [
                UpdatedOn <| journalNameFromDateTimeOffset comment.EditedAt
              ]
            Blocks = blocks
          }
          |> Ok
        | TaskCommentDeleted _ -> NotImplemented "TODO: ignore" |> Error


      let toMarkdown page = UNDEFINED
