module AutoMate.Program

open Falco
open Falco.FSharpJson
open Falco.Routing
open Falco.HostBuilder
open Microsoft.AspNetCore.Authentication
open Microsoft.AspNetCore.Hosting
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Hosting
open Microsoft.Extensions.Logging
open Npgsql.FSharp
open System
open System.Reflection
//open Serilog

let configureLogging (config: Config.LoggingConfig) (log: ILoggingBuilder) =
  // https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.logging.iloggingbuilder
  // https://learn.microsoft.com/en-us/aspnet/core/fundamentals/logging/#configure-logging
  log.ClearProviders() |> ignore

  match config.Format with
  | Config.LogFormat.Json -> log.AddJsonConsole()
  | Config.LogFormat.Plain -> log.AddConsole()
  |> ignore

  log.SetMinimumLevel(config.Level) |> ignore

  log

let configureServices (services: IServiceCollection) =
  // https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.dependencyinjection.authenticationservicecollectionextensions.addauthentication?view=aspnetcore-9.0
  (*
  services
    .AddAuthentication(fun options ->
      // https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.authentication.authenticationoptions?view=aspnetcore-9.0
      options.DefaultAuthenticationScheme <- JwtBearerDefaults.AuthenticationScheme
      options.DefaultSigninScheme <- JwtBearerDefaults.AuthenticationScheme
      options.DefaultChallengeScheme <- "TODO"
    )
    .AddOAuth(
      "dropbox", fun options ->
        options.ClientId <- "TODO"
        options.ClientSecret <- "TODO"
    )
  *)
  services.AddFalco() |> ignore

let configureHost (host: IHostBuilder) =
  // https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.hosting.ihostbuilder
  //host.AddSerilog()
  host

let configureWebHost (webHost: IWebHostBuilder) =
  // https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.hosting.iwebhostbuilder
  //webHost.UseHttpSys()
  webHost.ConfigureServices(configureServices)

let postOauthHandler: HttpHandler =

  let handleDeps deps input =
    Database.OAuthAccess.upsert
      deps.DbConn
      "derek"
      "dropbox"
      "bearer"
      "foobar"
      None
      None
    |> Ok

  let handleOk r = Respond.ofJson r

  let handleError = ErrorResponse.badRequest

  Deps.inject handleDeps handleOk handleError ()

let putOauthHandler: HttpHandler =

  let handleDeps deps input =
    Database.OAuthAccess.update deps.DbConn "derek" "dropbox" "foofoo" None |> Ok

  let handleOk r = Respond.ofJson r

  let handleError = ErrorResponse.badRequest

  Deps.inject handleDeps handleOk handleError ()

[<EntryPoint>]
let main args =
  let config = Config.load ()
  printfn "Config - %A" config

  let dropboxOauthRegisterRedirectUri =
    Url.build config.Dropbox.RedirectBaseUrl
    |> Url.replacePath Route.V1.OAuth.Dropbox.register
    |> Unwrap.ok

  webHost args {
    host configureHost
    web_host configureWebHost
    logging (configureLogging config.Logging)
    not_found ErrorController.notFound
    add_service (configService config)
    add_service (dbConnectionService config.Database)
    //add_service oauthService

    endpoints [
      get Route.index <| Response.ofPlainText "Hello, world!"
      any Route.Meta.debug Response.debugRequest
      get Route.Meta.config configHandler
      get Route.Meta.liveness Liveness.handler
      get Route.Meta.readiness Readiness.handler
      get Route.Meta.startup Startup.handler
      get Route.Meta.version
      <| Response.ofPlainText (
        Assembly.GetExecutingAssembly().GetName().Version.ToString()
      )
      get
        Route.V1.OAuth.Dropbox.register
        (OAuth.Dropbox.registerHandler dropboxOauthRegisterRedirectUri)
      get Route.V1.OAuth.Dropbox.authorize OAuth.Dropbox.authorizeHandler
      post Route.V1.Todoist.webhookEvents Todoist.SyncApi.WebhookEvent.handler
      post "/oauth" postOauthHandler
      put "/oauth" putOauthHandler
    ]
  }

  0

(*
  Todoist Webhook Event -> Create Dropbox File / Add Logseq Page

  Todoist:
    Decode JSON
    Route event back to App

  App:
    Subscribe to Todoist events
    | Comment -> Comment handler; Enrich handler; Logger handler
    | _ -> ignore
    Comment * Handler:
      Transform event
      Logseq handle comment
    Enrich Handler:
      Setup Todoist client
        Get OAuth credentials
      Fetch related data
      | Task -> Task fetched handler
      | Section -> Section fetched handler
      | Project -> Project fetched handler
    Task Fetched Handler:
      Transform task for Logseq
      Logseq handle task
    Section Fetched Handler:
      Transform section for Logseq
      Logseq handle section
    Project Fetched Handler:
      Transform project for Logseq
      Logseq handle project

  Transform:
    Match event
    | Comment -> Map Markdown to Logseq bullets
    | _ -> ignore

  Logseq:
    Provider = Dropbox
    Setup Logseq client
      Setup Provider client
        Get OAuth credentials
    Handle event
    | Comment -> Create page
    | _ -> ignore

*)
