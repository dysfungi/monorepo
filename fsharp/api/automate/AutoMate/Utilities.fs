module AutoMate.Utilities

open System

let wantSome errorMsg =
  function
  | Some value -> value
  | None -> failwith errorMsg

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
