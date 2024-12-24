module AutoMate.Dropbox

open FsHttp
open FsHttp.FSharpJson.Response
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
    |> Response.toText

  type ShortLivedOfflineAccess = {
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
    =
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
    |> toJson<ShortLivedOfflineAccess>

  type ShortLivedRefreshAccess = {
    AccessToken: string
    ExpiresIn: int
    TokenType: string
  }

  let refreshToken (clientId: string) (clientSecret: string) (refreshToken: string) =
    http {
      POST "https://api.dropbox.com/oauth2/token"

      query [
        "grant_type", "refresh_token"
        "refresh_token", refreshToken
        "client_id", clientId
        "client_secret", clientSecret
      ]
    }
    |> Request.send
    |> toJson<ShortLivedRefreshAccess>
