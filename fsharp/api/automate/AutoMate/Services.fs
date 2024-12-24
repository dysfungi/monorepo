[<AutoOpen>]
module AutoMate.Services

open Falco
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging
open Npgsql.FSharp
open System.Data

type DbConnectionFactory = unit -> Npgsql.NpgsqlConnection //IDbConnection

let configureDbConnectionService
  (dbConfig: Config.DatabaseConfig)
  (services: IServiceCollection)
  =
  let dbConnectionString = Database.buildConnectionString dbConfig
  printfn "Database URL: %s" dbConnectionString

  let dbConnectionFactory () : Npgsql.NpgsqlConnection =
    dbConnectionString |> Sql.connect |> Sql.createConnection

  services.AddSingleton<DbConnectionFactory>(dbConnectionFactory)

type DependencyInjections = {
  Log: ILogger
  DbConn: Npgsql.NpgsqlConnection
  DbTransaction: IDbTransaction
}

type DependencyInjectionHandler<'input, 'output, 'error> =
  DependencyInjections -> 'input -> Result<'output, 'error>

module DepInj =
  let run
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
