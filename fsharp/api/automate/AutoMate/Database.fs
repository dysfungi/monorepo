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
open AutoMate.Utilities

OptionTypes.register ()

let buildConnectionString username password host port dbname sslMode =
  let sslMode': SslMode =
    match Str.toLower sslMode with
    | "disable" -> SslMode.Disable
    | "prefer" -> SslMode.Prefer
    | "require" -> SslMode.Require
    | _ -> failwith "Valid $DATABASE_SSLMODE required"

  Sql.host host
  |> Sql.database dbname
  |> Sql.password password
  |> Sql.port port
  |> Sql.sslMode sslMode'
  |> Sql.username username
  |> Sql.formatConnectionString

module OAuth =
  type Provider = {
    Name: string
    AuthorizeUrl: string
    RefreshUrl: string option
    TestUrl: string option
  }
