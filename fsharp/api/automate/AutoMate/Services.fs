module AutoMate.Services

open Microsoft.Extensions.DependencyInjection
open Npgsql.FSharp

type DbConnectionFactory = unit -> Sql.SqlProps

let configureDbConnectionService
  (dbConfig: Config.DatabaseConfig)
  (services: IServiceCollection)
  =
  let dbConnectionString = Database.buildConnectionString dbConfig
  printfn "Database URL: %s" dbConnectionString
  let dbConnectionFactory () = Sql.connect dbConnectionString
  services.AddSingleton<DbConnectionFactory> dbConnectionFactory
