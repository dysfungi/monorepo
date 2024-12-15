module AutoMate.Tests.Utilities

open AutoMate.Utilities
open Expecto

[<Tests>]
let strTests =
  testList "Str" [
    testList "toLower" [
      testCase "pass"
      <| fun _ ->
        let input = "FOOBAR"
        let output = Str.toLower input
        Want.equal "foobar" output
    ]

    testList "toUpper" [
      testCase "pass"
      <| fun _ ->
        let input = "foobar"
        let output = Str.toUpper input
        Want.equal "FOOBAR" output
    ]

    testList "startsWith" [
      testCase "pass"
      <| fun _ ->
        let input, prefix = "foobar", "foo"
        let output = Str.startsWith prefix input
        Want.equal true output

      testCase "fail when does not start with prefix"
      <| fun _ ->
        let input, suffix = "foobar", "bar"
        let output = Str.startsWith suffix input
        Want.equal false output
    ]

    testList "endsWith" [
      testCase "pass"
      <| fun _ ->
        let input, suffix = "foobar", "bar"
        let output = Str.endsWith suffix input
        Want.equal true output

      testCase "fail when does not end with suffix"
      <| fun _ ->
        let input, prefix = "foobar", "foo"
        let output = Str.endsWith prefix input
        Want.equal false output
    ]

    testList "split" [
      testCase "pass"
      <| fun _ ->
        let input = "foo,bar,baz"
        let output = Str.split "," input

        Want.equal
          [
            "foo"
            "bar"
            "baz"
          ]
          output
    ]

    testList "splitWhitespace" [
      testCase "pass"
      <| fun _ ->
        let input = "foo\nbar baz"
        let output = Str.splitWhitespace input

        Want.equal
          [
            "foo"
            "bar"
            "baz"
          ]
          output
    ]

    testList "splitMax" [
      testCase "pass"
      <| fun _ ->
        let input = "foo,bar,baz"
        let output = Str.splitMax 2 "," input

        Want.equal
          [
            "foo"
            "bar,baz"
          ]
          output
    ]

    testList "splitWhitespaceMax" [
      testCase "pass"
      <| fun _ ->
        let input = "foo bar\nbaz"
        let output = Str.splitWhitespace input

        Want.equal
          [
            "foo"
            "bar"
            "baz"
          ]
          output
    ]

    testList "splitWord" [
      testCase "pass"
      <| fun _ ->
        let input = "foobarbaz"
        let output = Str.splitWord "bar" input

        Want.equal
          [
            "foo"
            "baz"
          ]
          output
    ]

    testList "splitWordMax" [
      testCase "pass"
      <| fun _ ->
        let input = "foobarbazbarfoo"
        let output = Str.splitWordMax 2 "bar" input

        Want.equal
          [
            "foo"
            "bazbarfoo"
          ]
          output
    ]
  ]

[<Tests>]
let optTests =
  testList "Opt" [
    testList "wantSome" [
      testCase "pass"
      <| fun _ ->
        let expected = "foo"
        let input = Some expected
        let output = Opt.wantSome "expect Some" input
        Want.equal expected output

      testCase "fail when exception is not raised"
      <| fun _ ->
        let input = None
        let outputf = (fun _ -> Opt.wantSome "expect None" input)
        Want.throws outputf
    ]
  ]

[<Tests>]
let urlTests =
  testList "Url" [
    testList "parseAbsolute" [
      testCase "pass"
      <| fun _ ->
        let input = "https://foo.bar/baz"
        let output = Url.parseAbsolute input
        let output': Uri = Want.wantOk output
        Want.equal input <| string output'
    ]

    testList "parseRelative" [
      testCase "pass"
      <| fun _ ->
        let input = "https://foo.bar/baz"
        let output = Url.parseRelative input
        let output' = Want.wantOk output
        Want.equal input <| string output'
    ]
  ]

type TDeserialize = {
  Nested: {|
    String: string
    Number: int
  |}
  SnakeCase: bool option
}

[<Tests>]
let jsonTests =
  testList "Json" [
    testList "serialize" [
      testCase "pass"
      <| fun _ ->
        let input = {|
          Nested = {|
            String = "foo"
            Number = 2
          |}
          SnakeCase = "foo bar"
        |}

        let output = Json.serialize input

        let expected =
          """{
  "nested": {
    "number": 2,
    "string": "foo"
  },
  "snake_case": "foo bar"
}"""

        Want.equal expected output
    ]

    testList "deserialize" [
      testCase "pass"
      <| fun _ ->
        let input = """{"nested":{"string":"foo","number":2},"snake_case": null}"""
        let output = Json.deserialize<TDeserialize> input

        let expected = {
          Nested = {|
            String = "foo"
            Number = 2
          |}
          SnakeCase = None
        }

        let output' = Want.wantOk output
        Want.equal expected output'
    ]
  ]
