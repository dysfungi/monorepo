module AutoMate.Tests.Program

open Expecto

[<EntryPoint>]
let main args =
  args |> runTestsInAssemblyWithCLIArgs []
