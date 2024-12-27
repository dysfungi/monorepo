[<AutoOpen>]
module AutoMate.DependencyInjection

open Falco
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Logging
open Npgsql.FSharp
open System.Data

let configService (config: Config.AppConfig) (services: IServiceCollection) =
  services.AddSingleton<Config.AppConfig>(config)

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
  Config: Config.AppConfig
  Logger: ILogger
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
      let logger = ctx.GetLogger "AutoMate.DependencyInjection.Deps.inject"
      let config = ctx.GetService<Config.AppConfig>()
      let dbConnectionFactory = ctx.GetService<DbConnectionFactory>()
      use dbConnection = dbConnectionFactory ()
      dbConnection.Open()
      use dbTransaction = dbConnection.BeginTransaction()

      let depInj = {
        Config = config
        Logger = logger
        DbConn = dbConnection
        DbTransaction = dbTransaction
      }

      let respondWith =
        try
          match depInjHandler depInj input with
          | Ok output ->
            logger.LogDebug("Committing transaction")
            dbTransaction.Commit()
            logger.LogDebug("Committed transaction")
            handleOk output
          | Error error ->
            logger.LogWarning("Rolling back transaction for handled error")
            dbTransaction.Rollback()
            logger.LogDebug("Rolled back transaction for handled error")
            handleError error
        with exc ->
          logger.LogError(exc, "Rolling back transaction for unhandled error")
          dbTransaction.Rollback()
          logger.LogTrace(exc, "Rolled back transaction for unhandled error")
          ErrorResponse.internalServerError exc

      respondWith ctx
