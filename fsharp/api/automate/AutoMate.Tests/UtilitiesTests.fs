module AutoMate.Tests.Utilities

open AutoMate.Utilities
open Expecto

[<Tests>]
let strTests =

  testList "Str" [
    testList "toLower" [
      testCase "happy case" (fun _ ->
        let input = "FOOBAR"
        let output = Str.toLower input
        Expect.equal output "foobar" "Failed to lowercase")
    ]

    testList "toUpper" [
      testCase "happy case" (fun _ ->
        let input = "foobar"
        let output = Str.toUpper input
        Expect.equal output "FOOBAR" "Failed to uppercase")
    ]

    testList "startsWith" [
      testCase "foobar starts with foo" (fun _ ->
        let input, prefix = "foobar", "foo"
        let output = Str.startsWith prefix input
        Expect.equal output true $"Expected to start with {prefix}")

      testCase "foobar does not start with bar" (fun _ ->
        let input, suffix = "foobar", "bar"
        let output = Str.startsWith suffix input
        Expect.equal output false $"Expected to not start with {suffix}")
    ]

    testList "endsWith" [
      testCase "foobar ends with bar" (fun _ ->
        let input, suffix = "foobar", "bar"
        let output = Str.endsWith suffix input
        Expect.equal output true $"Expected to end with {suffix}")

      testCase "foobar does not end with foo" (fun _ ->
        let input, prefix = "foobar", "foo"
        let output = Str.endsWith prefix input
        Expect.equal output false $"Expected to not end with {prefix}")
    ]

    testList "split" [
      testCase """"foo,bar,baz" splits on "," as [foo;bar;baz]""" (fun _ ->
        let input = "foo,bar,baz"
        let output = Str.split "," input

        Expect.equal
          output
          [
            "foo"
            "bar"
            "baz"
          ]
          "Failed to split")
    ]

    testList "splitWhitespace" [
      testCase """"foo\nbar baz" splits on whitespace as [foo;bar;baz]""" (fun _ ->
        let input = "foo\nbar baz"
        let output = Str.splitWhitespace input

        Expect.equal
          output
          [
            "foo"
            "bar"
            "baz"
          ]
          "Failed to split")
    ]

    testList "splitMax" [
      testCase """"foo,bar,baz" splits twice on "," as [foo;bar,baz]""" (fun _ ->
        let input = "foo,bar,baz"
        let output = Str.splitMax 2 "," input

        Expect.equal
          output
          [
            "foo"
            "bar,baz"
          ]
          "Failed to split")
    ]

    testList "splitWhitespaceMax" [
      testCase
        """"foo\nbar baz" splits twice on whitespace as [foo;bar baz]"""
        (fun _ ->
          let input = "foo bar\nbaz"
          let output = Str.splitWhitespace input

          Expect.equal
            output
            [
              "foo"
              "bar"
              "baz"
            ]
            "Failed to split")
    ]

    testList "splitWord" [
      testCase """"foobarbaz" splits on "bar" as [foo;baz]""" (fun _ ->
        let input = "foobarbaz"
        let output = Str.splitWord "bar" input

        Expect.equal
          output
          [
            "foo"
            "baz"
          ]
          "Failed to split")
    ]

    testList "splitWordMax" [
      testCase
        """"foobarbazbarfoo" splits twice on "bar" as [foo;bazbarfoo]"""
        (fun _ ->
          let input = "foobarbazbarfoo"
          let output = Str.splitWordMax 2 "bar" input

          Expect.equal
            output
            [
              "foo"
              "bazbarfoo"
            ]
            "Failed to split")
    ]
  ]
