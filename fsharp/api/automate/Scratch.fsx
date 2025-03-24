#r "nuget: FSharp.Formatting"

open FSharp.Formatting.Markdown

// https://docs.logseq.com/#/page/properties
type LogseqFrontmatter = LogseqProperties * MarkdownRange
and LogseqProperties = LogseqProperty list
and LogseqProperty = string * string list

let content =
  """
my list:

- one
- two
    - juan
- three

Lorem ipsum.
"""

let comment =
  """
tags:: 2024-11-02, todoist/task/8535742406, 2024-10-29
created:: 2024-10-29
updated:: 2024-11-02

- [Comment in Todoist](https://app.todoist.com/app/task/8535742406)
  - ~[https://github.com/helm/charts/blob/master/stable/prometheus-postgres-exporter/README.md](https://github.com/helm/charts/blob/master/stable/prometheus-postgres-exporter/README.md)~
  - [https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-postgres-exporter](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-postgres-exporter)
  - [https://artifacthub.io/packages/helm/prometheus-community/prometheus-postgres-exporter](https://artifacthub.io/packages/helm/prometheus-community/prometheus-postgres-exporter)
  - [https://github.com/prometheus-community/postgres_exporter](https://github.com/prometheus-community/postgres_exporter)
  """

let doc = Markdown.Parse(content)

let taskId = 1234

let frontMatter =
  Paragraph(
    [
      Literal(
        $"""tags:: todoist/task/{taskId}
created:: #2025-01-25
updated:: #2025-01-26""",
        None
      )
    ],
    None
  )

let doc' =
  let pars = [
    frontMatter
    ListBlock(Unordered, [ doc.Paragraphs ], None)
  ]

  MarkdownDocument(pars, doc.DefinedLinks)

doc' |> Markdown.ToMd



let doc2 = Markdown.Parse "Foo Bar:\n- Baz\n- Egg\n- Spam\n\nLorem ipsum."

let paras = [
  MarkdownParagraph.ListBlock(
    MarkdownListKind.Unordered,
    [ for p in doc2.Paragraphs -> [ p ] ],
    None
  )
]

Markdown.ToMd <| MarkdownDocument(paras, doc2.DefinedLinks)
