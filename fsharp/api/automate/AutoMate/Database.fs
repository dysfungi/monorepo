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

OptionTypes.register ()

let connectionString =
  Sql.host "postgres" // |> Sql.database "automate_api"
  |> Sql.username "postgres"
  |> Sql.password "postgres"
  |> Sql.port 5432
  |> Sql.formatConnectionString

module OAuth =
  type Provider = {
    Name: string
    AuthorizeUrl: string
    RefreshUrl: string option
    TestUrl: string option
  }
