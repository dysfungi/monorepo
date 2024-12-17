module AutoMate.Tests.Arguments

open Argu
open AutoMate.Config
open Expecto
open System

type Args =
  | Foo of FOO: string
  | BarBaz of int
  | Egg_Spam of string

  interface IArgParserTemplate with
    member arg.Usage =
      match arg with
      | Foo _ -> "FOO"
      | BarBaz _ -> "BAR_BAZ"
      | Egg_Spam _ -> "EGG_SPAM"

let parser = ArgumentParser.Create<Args>(programName = "AutoMate.Tests")

[<Tests>]
let envReaderTests =
  testList "envReader" [
    testCase "pass"
    <| fun _ ->
      let expectedFoo = "foo"
      let expectedBarBaz = 2
      let expectedEggSpam = "egg spam"

      let expected = [
        Foo expectedFoo
        BarBaz expectedBarBaz
        Egg_Spam expectedEggSpam
      ]

      Environment.SetEnvironmentVariable("FOO", expectedFoo)
      Environment.SetEnvironmentVariable("BARBAZ", (string expectedBarBaz))
      Environment.SetEnvironmentVariable("EGG_SPAM", expectedEggSpam)

      let parse args =
        parser.ParseConfiguration(configurationReader = envReader)

      let results = parse [||]
      let output = results.GetAllResults()
      Want.equal expected output
  ]
