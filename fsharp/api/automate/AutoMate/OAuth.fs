module AutoMate.OAuth

open AutoMate.Services
open AutoMate.Utilities
open Falco

module Dropbox =
  open AutoMate.Dropbox

  let handleRegister2: HttpHandler =
    fun ctx ->
      let q = Request.getQuery ctx
      let code = q.GetString("code", "")
      let state = q.GetString("state", "")
      Response.ofPlainText "Successful" ctx

  let handleRegister: HttpHandler =
    fun ctx ->
      let dbConnectionFactory = ctx.GetService<DbConnectionFactory>()
      let dbConnection = dbConnectionFactory ()

      let handleQuery (q: QueryCollectionReader) =
        let code = q.GetString("code", "TODO")
        let state = q.GetString("state", "TODO")

        let redirectUri =
          Url.parseAbsolute ("TODO" + Route.V1.OAuth.Dropbox.register) |> Unwrap.ok

        let clientId = "TODO"
        let clientSecret = "TODO"
        let offlineAccess = Api.getAccessToken redirectUri clientId clientSecret code
        "Successful"

      Request.mapQuery handleQuery Response.ofPlainText ctx


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
