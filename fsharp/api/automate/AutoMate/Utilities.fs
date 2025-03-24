[<AutoOpen>]
module AutoMate.Utilities

type UNDEFINED = exn

[<RequireQualifiedAccess>]
module Str =
  open System

  let whitespace = "\t\n\v\f\r "

  let toLower (s: string) = s.ToLower()
  let toUpper (s: string) = s.ToUpper()

  let startsWith (prefix: string) (s: string) = s.StartsWith prefix
  let endsWith (suffix: string) (s: string) = s.EndsWith suffix

  let replace (oldValue: string) (newValue: string) (s: string) =
    s.Replace(oldValue, newValue)

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

  let trim (chars: string) (s: string) = s.Trim(chars.ToCharArray())
  let trimLeft (chars: string) (s: string) = s.TrimStart(chars.ToCharArray())
  let trimRight (chars: string) (s: string) = s.TrimEnd(chars.ToCharArray())

[<RequireQualifiedAccess>]
module Unwrap =
  /// Unwrap Some option or throw exception with error message.
  let someWith errorMessage =
    function
    | Some value -> value
    | None -> failwith errorMessage

  /// Unwrap Some option or throw exception.
  let some opt =
    someWith "Wanted Some option, got None" opt

  /// Unwrap Ok result or throw exception with error message.
  let okWith errorMessage =
    function
    | Ok value -> value
    | Error _ -> failwith errorMessage

  /// Unwrap Ok result or throw exception.
  let ok result =
    okWith "Wanted Ok result, got Error" result

[<RequireQualifiedAccess>]
module Qry =
  open System

  type Query = Map<string, string list>

  let create = Query

  let empty: Query = create []

  let add (key: string) (value: string) : Query -> Query =
    Map.change key (function
      | Some values -> Some(List.append values [ value ])
      | None -> Some [ value ])

  let extend (key: string) (values: string list) (query: Query) : Query =
    List.fold (fun query value -> add key value query) query values

  let parse (qs: string) : Query =
    qs
    |> Str.trimLeft "?"
    |> Str.split "&"
    |> List.fold
      (fun query part ->
        match Str.splitMax 2 "=" part with
        | [ key; values ] ->
          let decodedKey = Uri.UnescapeDataString key

          let decodedValues =
            values |> Str.split "," |> List.map Uri.UnescapeDataString

          extend decodedKey decodedValues query
        | [ "" ] -> query
        | [ key ] -> add key "" query
        | _ -> query)
      (Query [])

  let toString: (Query) -> string =
    Map.toList
    >> List.map (fun (key, values) ->
      let encodedKey = Uri.EscapeDataString key

      values
      |> List.map Uri.EscapeDataString
      |> List.map (fun encodedValue -> sprintf "%s=%s" encodedKey encodedValue)
      |> Str.join "&")
    >> Str.join "&"

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

  let internal tryUriBuilder uri : Result<UriBuilder, exn> =
    try
      string uri |> UriBuilder |> Ok
    with exc ->
      Error exc

  let internal tryMutate
    (mutator: UriBuilder -> unit)
    : Result<Uri, exn> -> Result<Uri, exn> =
    Result.bind tryUriBuilder
    >> Result.bind (fun builder ->
      try
        mutator builder |> ignore
        Ok builder.Uri
      with exc ->
        Error exc)

  let build baseUri : Result<Uri, exn> =
    tryUriBuilder baseUri
    |> Result.bind (fun builder ->
      try
        Ok builder.Uri
      with exc ->
        Error exc)

  let replaceScheme scheme : Result<Uri, exn> -> Result<Uri, exn> =
    tryMutate (fun builder -> builder.Scheme <- scheme)

  let replaceUserName username =
    tryMutate (fun builder -> builder.UserName <- username)

  let replaceHost host =
    tryMutate (fun builder -> builder.Host <- host)

  let replacePath path =
    tryMutate (fun builder -> builder.Path <- path)

  let addQuery (key: string) (value: string) =
    tryMutate (fun builder ->
      builder.Query <- Qry.parse builder.Query |> Qry.add key value |> Qry.toString)

[<RequireQualifiedAccess>]
module Json =
  open FSharp.Json
  open Validus

  type Field = JsonField

  let defaultConfig = JsonConfig.create (jsonFieldNaming = Json.snakeCase)

  let serialize data = Json.serializeEx defaultConfig data

  let deserialize<'T> json =
    try
      Json.deserializeEx<'T> defaultConfig json |> Ok
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
    get name |> Unwrap.someWith $"Missing environment variable - ${name}"

  let set name value =
    Environment.SetEnvironmentVariable(name, value)

//==============================================
// Computation Expression for Result
//==============================================
// https://github.com/swlaschin/DomainModelingMadeFunctional/blob/master/src/OrderTakingEvolved/Result.fs#L174

[<AutoOpen>]
module ResultComputationExpression =

  type ResultBuilder() =
    member __.Return(x) = Ok x
    member __.Bind(x, f) = Result.bind f x

    member __.ReturnFrom(x) = x
    member this.Zero() = this.Return()

    member __.Delay(f) = f
    member __.Run(f) = f ()

    member this.While(guard, body) =
      if not (guard ()) then
        this.Zero()
      else
        this.Bind(body (), fun () -> this.While(guard, body))

    member this.TryWith(body, handler) =
      try
        this.ReturnFrom(body ())
      with e ->
        handler e

    member this.TryFinally(body, compensation) =
      try
        this.ReturnFrom(body ())
      finally
        compensation ()

    member this.Using(disposable: #System.IDisposable, body) =
      let body' = fun () -> body disposable

      this.TryFinally(
        body',
        fun () ->
          match disposable with
          | null -> ()
          | disp -> disp.Dispose()
      )

    member this.For(sequence: seq<_>, body) =
      this.Using(
        sequence.GetEnumerator(),
        fun enum -> this.While(enum.MoveNext, this.Delay(fun () -> body enum.Current))
      )

    member this.Combine(a, b) = this.Bind(a, fun () -> b ())

  let result = new ResultBuilder()
