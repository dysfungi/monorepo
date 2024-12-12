module AutoMate.Utilities

open System

let wantSome errorMsg =
  function
  | Some value -> value
  | None -> failwith errorMsg


[<RequireQualifiedAccess>]
module Str =
  let whitespace = "\t\n\v\f\r "

  let toLower (s: string) = s.ToLower()
  let toUpper (s: string) = s.ToUpper()

  let startsWith (prefix: string) (s: string) = s.StartsWith prefix
  let endsWith (suffix: string) (s: string) = s.EndsWith suffix

  let split (separators: string) (s: string) =
    s.Split(separators.ToCharArray()) |> List.ofArray

  let splitWhitespace = split whitespace

  let splitMax (max: int) (separators: string) (s: string) =
    s.Split(separators.ToCharArray(), max) |> List.ofArray

  let splitWhitespaceMax (max: int) = splitMax max whitespace

  let splitWord (word: string) (s: string) = s.Split word |> List.ofArray

  let splitWordMax (max: int) (word: string) (s: string) =
    s.Split(word, max) |> List.ofArray

  let join = String.concat

[<RequireQualifiedAccess>]
module Env =

  let get name =
    match Environment.GetEnvironmentVariable name with
    | null -> None
    | value -> Some value

  let getDefault fallback name =
    match get name with
    | Some value -> value
    | None -> fallback

  let want name =
    get name |> wantSome $"Missing environment variable - ${name}"

  let set name value =
    Environment.SetEnvironmentVariable(name, value)
