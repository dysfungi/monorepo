module AutoMate.OAuth

open Falco
open System
open Validus

module Dropbox =
  open AutoMate.Dropbox

  type Authorization = {
    ResponseType: string
    ClientId: string
    RedirectUri: string
    TokenAccessType: string
    State: string
  }

  let authorizeHandler: HttpHandler =
    let handleDeps deps input =
      let config = deps.Config.Dropbox

      let redirectUri =
        Url.build config.RedirectBaseUrl
        |> Url.replacePath Route.V1.OAuth.Dropbox.register
        |> Unwrap.ok

      Url.build "https://www.dropbox.com/oauth2/authorize"
      |> Url.addQuery "response_type" "code"
      |> Url.addQuery "client_id" config.ClientId
      |> Url.addQuery "redirect_uri" (string redirectUri)
      |> Url.addQuery "token_access_type" "offline"
      |> Url.addQuery "state" ""

    let handleOk uri =
      Response.redirectTemporarily (string uri)

    let handleError = ErrorResponse.unexpectedError

    Deps.inject handleDeps handleOk handleError ()

  type Registration = {
    Code: string
    State: string
  }

  let registerHandler redirectUri : HttpHandler =
    let queryMapper (q: QueryCollectionReader) : Result<Registration, HandlerError> =
      Ok(Map<string, string> [])
      |> Result.bind (fun map ->
        let field = "code"

        match q.TryGetStringNonEmpty(field) with
        | Some value -> Ok <| Map.add field value map
        | None ->
          Error
          <| ValidationErrors.create field [ ValidationMessages.optionIsSome field ])
      |> Result.bind (fun map ->
        let field = "state"

        match q.TryGetString(field) with
        | Some value -> Ok <| Map.add field value map
        | None ->
          Error
          <| ValidationErrors.create field [ ValidationMessages.optionIsSome field ])
      |> Result.map (fun map -> {
        Code = Map.find "code" map
        State = Map.find "state" map
      })
      |> Result.mapError QueryValidationError

    let handleDepInj deps queryResult =
      let config = deps.Config.Dropbox
      let clientId = config.ClientId
      let clientSecret = config.ClientSecret

      queryResult
      |> Result.bind (fun query ->
        Api.getAccessToken redirectUri clientId clientSecret query.Code
        |> Result.mapError (fun exc -> UnexpectedError exc))
      |> Result.map (fun access ->
        DateTimeOffset.UtcNow.AddSeconds access.ExpiresIn
        |> Some
        |> Database.OAuthAccess.upsert
          deps.DbConn
          access.AccountId
          "dropbox"
          access.TokenType
          access.AccessToken
          (Some access.RefreshToken))
      |> Result.map (fun _ -> "Successful")

    let handleOk = Response.ofPlainText

    let handleError =
      function
      | QueryValidationError errors -> ErrorResponse.queryValidationErrors errors
      | UnexpectedError exc -> ErrorResponse.unexpectedError exc

    Request.mapQuery queryMapper <| Deps.inject handleDepInj handleOk handleError


(*
def main() -> str:
    """
    https://www.dropbox.com/developers/documentation/http/documentation#oauth2-token

    {
        "access_token": "sl.u.AbX9y6Fe3AuH5o66-gmJpR032jwAwQPIVVzWXZNkdzcYT02akC2de219dZi6gxYPVnYPrpvISRSf9lxKWJzYLjtMPH-d9fo_0gXex7X37VIvpty4-G8f4-WX45AcEPfRnJJDwzv-",
        "expires_in": 14400,
        "token_type": "bearer",
        "scope": "account_info.read files.content.read files.content.write files.metadata.read",
        "refresh_token": "nBiM85CZALsAAAAAAAAAAQXHBoNpNutK4ngsXHsqW4iGz9tisb3JyjGqikMJIYbd",
        "account_id": "dbid:AAH4f99T0taONIb-OurWxbNQ6ywGRopQngc",
        "uid": "12345"
    }
    """
    access_token = wmill.get_variable("u/dmf/dropbox-oauth-access-token")
    if not is_valid(access_token):
        access_token = refresh_access_token()
    assert access_token, access_token
    return access_token


def refresh_access_token() -> str:
    app_key = wmill.get_variable("u/dmf/dropbox-oauth-app-key")
    app_secret = wmill.get_variable("u/dmf/dropbox-oauth-app-secret")
    refresh_token = wmill.get_variable("u/dmf/dropbox-oauth-refresh-token")
    response = httpx.post(
        "https://www.dropbox.com/oauth2/token",
        data={
            "grant_type": "refresh_token",
            "client_id": app_key,
            "client_secret": app_secret,
            "refresh_token": refresh_token,
        },
    )
    data = response.json()
    access_token = data["access_token"]
    wmill.set_variable("u/dmf/dropbox-oauth-access-token", access_token)
    return access_token


def is_valid(access_token: str) -> bool:
    """
    https://www.dropbox.com/developers/documentation/http/documentation#check-user
    """
    response = httpx.post(
        "https://api.dropboxapi.com/2/check/user",
        headers={
            "Authorization": f"Bearer {access_token}",
        },
        json={
            "query": "foobar",
        },
    )
    return response.status_code == 200


1. Retrieve db.access_token
2. Check db.access_token is valid
   1. If not, retrieve db.refresh_token
   2. Refresh access token
   3. Store new db.access_token
3. Return db.access_token
*)
