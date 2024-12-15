module AutoMate.Utilities

[<RequireQualifiedAccess>]
module Str =
  open System

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
module Want =
  let someMsg errorMsg =
    function
    | Some value -> value
    | None -> failwith errorMsg

  let some opt =
    someMsg "Wanted Some option, got None" opt

  let okMsg errorMsg =
    function
    | Ok value -> value
    | Error _ -> failwith errorMsg

  let ok result =
    okMsg "Wanted Ok result, got Error" result

[<RequireQualifiedAccess>]
module Url =
  open System

  let parse (kind: UriKind) s =
    try
      Ok <| Uri(s, kind)
    with ex ->
      Error ex.Message

  let parseAny = parse UriKind.RelativeOrAbsolute
  let parseAbsolute = parse UriKind.Absolute
  let parseRelative = parse UriKind.Relative

[<RequireQualifiedAccess>]
module Json =
  open FSharp.Json
  open Validus

  type Field = JsonField

  let config = JsonConfig.create (jsonFieldNaming = Json.snakeCase)

  let serialize data = Json.serializeEx config data

  let deserialize<'T> json =
    try
      Json.deserializeEx<'T> config json |> Ok
    with ex ->
      Error ex

  let deserializeValidator<'T> : Validator<string, 'T> =
    fun (field: string) (input: string) ->
      input
      |> Check.String.notEmpty field
      |> Result.bind (
        deserialize<'T>
        >> function
          | Ok v -> Ok v
          | Error e -> Error <| ValidationErrors.create field [ e.Message ]
      )

[<RequireQualifiedAccess>]
module Env =
  open System

  let get name =
    match Environment.GetEnvironmentVariable name with
    | null -> None
    | value -> Some value

  let getDefault fallback name =
    match get name with
    | Some value -> value
    | None -> fallback

  let want name =
    get name |> Want.someMsg $"Missing environment variable - ${name}"

  let set name value =
    Environment.SetEnvironmentVariable(name, value)

module FsHttp =
  open FsHttp

  module Response =
    let toJson response = response |> Response.parseAsync
