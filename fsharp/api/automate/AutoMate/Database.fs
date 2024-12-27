// https://www.pimbrouwers.com/2020-12-08/fsharp-on-the-web-a-guide-to-building-websites-with-falco-dotnet-x-and-aspdotnet-core.html#data-access
// https://www.compositional-it.com/news-blog/mirco-orms-and-f/
// https://github.com/pimbrouwers/Donald
// https://github.com/Dzoukr/Dapper.FSharp
// https://github.com/JordanMarr/SqlHydra
// https://blog.tunaxor.me/blog/2021-11-12-Data-Access-In-Fsharp.html

module AutoMate.Database

open Npgsql.FSharp
open System
open System.Data

let buildConnectionString (db: Config.DatabaseConfig) =
  let sslMode: SslMode =
    match db.SslMode with
    | Config.DbSslMode.Disable -> SslMode.Disable
    | Config.DbSslMode.Prefer -> SslMode.Prefer
    | Config.DbSslMode.Require -> SslMode.Require

  Sql.host db.Host
  |> Sql.database db.Name
  |> Sql.password db.Password
  |> Sql.port db.Port
  |> Sql.sslMode sslMode
  |> Sql.username db.Username
  |> Sql.formatConnectionString

type OAuthProviders =
  | Dropbox
  | Todoist

type OAuthAccess = {
  Id: Guid
  CreatedAt: DateTimeOffset
  UpdatedAt: DateTimeOffset
  AccountId: string
  Provider: string
  TokenType: string
  AccessToken: string
  RefreshToken: string option
  ExpiresAt: DateTimeOffset option
}

module OAuthAccess =
  let internal readRow (read: RowReader) : OAuthAccess = {
    Id = read.uuid "id"
    CreatedAt = read.datetimeOffset "created_at"
    UpdatedAt = read.datetimeOffset "updated_at"
    AccountId = read.text "account_id"
    Provider = read.text "provider"
    TokenType = read.text "token_type"
    AccessToken = read.text "access_token"
    RefreshToken = read.textOrNone "refresh_token"
    ExpiresAt = read.datetimeOffsetOrNone "expires_at"
  }

  let upsert
    (conn: Npgsql.NpgsqlConnection)
    (accountId: string)
    (provider: string)
    (tokenType: string)
    (accessToken: string)
    (refreshToken: string option)
    (expiresAt: DateTimeOffset option)
    : OAuthAccess =
    conn
    |> Sql.existingConnection
    |> Sql.query
      "INSERT INTO oauth_access
       ( account_id
       , provider
       , token_type
       , access_token
       , refresh_token
       , expires_at
       )
       VALUES
       ( @account_id
       , @provider
       , @token_type
       , @access_token
       , @refresh_token
       , @expires_at
       )
       ON CONFLICT (account_id, provider)
       DO UPDATE
       SET token_type = @token_type
         , access_token = @access_token
         , refresh_token = @refresh_token
         , expires_at = @expires_at
       RETURNING *;"
    |> Sql.parameters [
      "@account_id", Sql.text accountId
      "@provider", Sql.text provider
      "@token_type", Sql.text tokenType
      "@access_token", Sql.text accessToken
      "@refresh_token", Sql.textOrNone refreshToken
      "@expires_at", Sql.timestamptzOrNone expiresAt
    ]
    |> Sql.executeRow readRow

  let update
    (conn: Npgsql.NpgsqlConnection)
    (accountId: string)
    (provider: string)
    (accessToken: string)
    (expiresAt: DateTimeOffset option)
    : OAuthAccess =
    conn
    |> Sql.existingConnection
    |> Sql.query
      "UPDATE oauth_access
       SET access_token = @access_token
         , expires_at = @expires_at
       WHERE account_id = @account_id
         AND provider = @provider
       RETURNING *;"
    |> Sql.parameters [
      "@account_id", Sql.text accountId
      "@provider", Sql.text provider
      "@access_token", Sql.text accessToken
      "@expires_at", Sql.timestamptzOrNone expiresAt
    ]
    |> Sql.executeRow readRow
