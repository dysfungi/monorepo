// https://www.pimbrouwers.com/2020-12-08/fsharp-on-the-web-a-guide-to-building-websites-with-falco-dotnet-x-and-aspdotnet-core.html#data-access
// https://www.compositional-it.com/news-blog/mirco-orms-and-f/
// https://github.com/pimbrouwers/Donald
// https://github.com/Dzoukr/Dapper.FSharp
// https://github.com/JordanMarr/SqlHydra
// https://blog.tunaxor.me/blog/2021-11-12-Data-Access-In-Fsharp.html

module AutoMate.Database

open Dapper.FSharp
open Dapper.FSharp.PostgreSQL
open Npgsql.FSharp
open System
open System.Data

OptionTypes.register ()

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
  Provider: string
  TokenType: string
  AccessToken: string
  RefreshToken: string option
  ExpiresAt: DateTimeOffset option
  AccountId: string option
}

let oauthAccessTable = table'<OAuthAccess> "oauth_access"

module OAuthAccess =
  let internal readRow (read: RowReader) : OAuthAccess = {
    Id = read.uuid "id"
    CreatedAt = read.datetimeOffset "created_at"
    UpdatedAt = read.datetimeOffset "updated_at"
    Provider = read.text "provider"
    TokenType = read.text "token_type"
    AccessToken = read.text "access_token"
    RefreshToken = read.textOrNone "refresh_token"
    ExpiresAt = read.datetimeOffsetOrNone "expires_at"
    AccountId = read.textOrNone "account_id"
  }

  let create
    (conn: Npgsql.NpgsqlConnection)
    (provider: string)
    (tokenType: string)
    (accessToken: string)
    (refreshToken: string option)
    (expiresAt: DateTimeOffset option)
    (accountId: string option)
    : OAuthAccess =
    (*
    task {
      let oauthAccess = {
        Id = Guid.Empty
        CreatedAt = DateTimeOffset.MinValue
        UpdatedAt = DateTimeOffset.MinValue
        Provider = provider
        TokenType = tokenType
        AccessToken = accessToken
        RefreshToken = refreshToken
        ExpiresAt = expiresAt
        AccountId = accountId
      }
      let! rows =
        insert {
          for oa in oauthAccessTable do
          value oauthAccess
          excludeColumn oa.Id
          excludeColumn oa.CreatedAt
          excludeColumn oa.UpdatedAt
        } |> conn.InsertOutputAsync<OAuthAccess, OAuthAccess>
      return rows |> Seq.head
    }
    |> Async.AwaitTask
    |> Async.RunSynchronously
      *)

    conn
    |> Sql.existingConnection
    |> Sql.query
      "INSERT INTO oauth_access
       ( provider
       , token_type
       , access_token
       , refresh_token
       , expires_at
       , account_id
       )
       VALUES
       ( @provider
       , @token_type
       , @access_token
       , @refresh_token
       , @expires_at
       , @account_id
       )
       RETURNING *;"
    |> Sql.parameters [
      "@provider", Sql.text provider
      "@token_type", Sql.text tokenType
      "@access_token", Sql.text accessToken
      "@refresh_token", Sql.textOrNone refreshToken
      "@expires_at", Sql.timestamptzOrNone expiresAt
      "@account_id", Sql.textOrNone accountId
    ]
    |> Sql.executeRow readRow

  let update
    (conn: Npgsql.NpgsqlConnection)
    (accessToken: string)
    (expiresAt: DateTimeOffset option)
    : OAuthAccess =
    conn
    |> Sql.existingConnection
    |> Sql.query
      "UPDATE oauth_access
       SET access_token = @access_token
       WHERE id IN (
         SELECT id
         FROM oauth_access
         ORDER BY created_at
         LIMIT 1
       )
       RETURNING *;"
    |> Sql.parameters [ "@access_token", Sql.text accessToken ]
    |> Sql.executeRow readRow
