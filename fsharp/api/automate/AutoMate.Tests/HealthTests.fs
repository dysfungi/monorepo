module AutoMate.Tests.Health

open Expecto

type T = { SnakeCase: string }

[<Tests>]
let healthTests =

  testList "Health" [
    testCase "serialize JSON with defaults" (fun _ ->
      let input = { SnakeCase = "foobar" }

      let output = AutoMate.Health.serialize input

      let expected =
        """{
  "snake_case": "foobar"
}"""

      Expect.equal output expected "Bad serialize")

    testCase "deserialize JSON with defaults" (fun _ ->
      let input = """{"snake_case":"foobar"}"""

      let result = AutoMate.Health.deserialize<T> input

      let output = Expect.wantOk result "Bad deserialize"

      Expect.equal output { SnakeCase = "foobar" } "Bad deserialize")
  ]
