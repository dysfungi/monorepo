[<AutoOpen>]
module AutoMate.DependencyInjection

open Falco
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging
open Npgsql.FSharp
open System.Data

type DbConnectionFactory = unit -> Npgsql.NpgsqlConnection //IDbConnection

let dbConnectionService
  (dbConfig: Config.DatabaseConfig)
  (services: IServiceCollection)
  =
  let dbConnectionString = Database.buildConnectionString dbConfig
  printfn "Database Connection Params: %s" dbConnectionString

  let dbConnectionFactory () : Npgsql.NpgsqlConnection =
    dbConnectionString |> Sql.connect |> Sql.createConnection

  services.AddSingleton<DbConnectionFactory>(dbConnectionFactory)

type Dependencies = {
  Log: ILogger
  DbConn: Npgsql.NpgsqlConnection
  DbTransaction: IDbTransaction
}

// https://www.pimbrouwers.com/2020-12-08/fsharp-on-the-web-a-guide-to-building-websites-with-falco-dotnet-x-and-aspdotnet-core.html#data-access
type DependencyInjectionHandler<'input, 'output, 'error> =
  Dependencies -> 'input -> Result<'output, 'error>

module Deps =
  let inject
    (depInjHandler: DependencyInjectionHandler<'input, 'output, 'error>)
    (handleOk: 'output -> HttpHandler)
    (handleError: 'error -> HttpHandler)
    (input: 'input)
    : HttpHandler =
    fun ctx ->
      let log = ctx.GetLogger "AutoMate.Services.DepInj"
      let dbConnectionFactory = ctx.GetService<DbConnectionFactory>()
      use dbConnection = dbConnectionFactory ()
      dbConnection.Open()
      use dbTransaction = dbConnection.BeginTransaction()

      let depInj = {
        Log = log
        DbConn = dbConnection
        DbTransaction = dbTransaction
      }

      let respondWith =
        match depInjHandler depInj input with
        | Ok output ->
          dbTransaction.Commit()
          handleOk output
        | Error error ->
          dbTransaction.Rollback()
          handleError error

      respondWith ctx
