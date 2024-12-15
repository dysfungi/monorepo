module AutoMate.Dropbox

open FsHttp
open FsHttp.FSharpJson
open System

module Api =
  // https://www.dropbox.com/developers/documentation/http/documentation#authorization
  let authorize (clientId: string) =
    http {
      GET "https://www.dropbox.com/oauth2/authorize"

      query [
        "client_id", clientId
        "token_access_type", "offline"
        "response_type", "code"
      ]
    }
    |> Request.send
  (*
    |> Response.toJson
    |> fun json -> json?name.GetString(), json?age.GetInt32()
    *)

  type OfflineAccess = {
    AccessToken: string
    RefreshToken: string
    ExpiresIn: int
    TokenType: string
    Scope: string
    AccountId: string
    Uid: string
  }

  let getAccessToken
    (redirectUri: Uri)
    (appKey: string)
    (appSecret: string)
    (authorizationCode: string)
    : OfflineAccess =
    http {
      POST "https://api.dropbox.com/oauth2/token"

      query [
        "code", authorizationCode
        "grant_type", "authorization_code"
        "redirect_uri", string (redirectUri)
        "client_id", appKey
        "client_secret", appSecret
      ]
    }
    |> Request.send

    {
      AccessToken = "foo"
      RefreshToken = "bar"
      ExpiresIn = 2
      TokenType = "bearer"
      Scope = ""
      AccountId = "me"
      Uid = "id"
    }
  (*
    |> Response.toJson
    |> fun json -> json?name.GetString()
    *)

  let refreshToken =
    http {
      POST "https://api.dropbox.com/oauth2/token"

      query [
        "grant_type", "refresh_token"
        "refresh_token", "<REFRESH_TOKEN>"
        "client_id", "<APP_KEY>"
        "client_secret", "<APP_SECRET>"
      ]
    }
(*
    |> Request.send
    |> Response.toJson
    |> fun json -> json?name.GetString()
    *)
