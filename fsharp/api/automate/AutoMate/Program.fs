module AutoMate.Program

open Falco
open Falco.Routing
open Falco.HostBuilder
open Microsoft.AspNetCore.Hosting
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.Hosting
open Microsoft.Extensions.Logging
//open Serilog

module ErrorController =
  let notFound: HttpHandler =
    Response.withStatusCode 404 >> Response.ofPlainText "Not Found"

  let unauthenticated: HttpHandler =
    Response.withStatusCode 401 >> Response.ofPlainText "Unauthenticated"

  let unauthorized: HttpHandler =
    Response.withStatusCode 403 >> Response.ofPlainText "Forbidden"

[<EntryPoint>]
let main args =
  let config = Config.getAll args
  printfn "Config: %A" config

  let configureHost (host: IHostBuilder) =
    // https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.hosting.ihostbuilder
    //host.AddSerilog()
    host

  let configureWebHost (webHost: IWebHostBuilder) =
    // https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.hosting.iwebhostbuilder
    //webHost.UseHttpSys()
    webHost

  let configureLogging (log: ILoggingBuilder) =
    // https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.logging.iloggingbuilder
    // https://learn.microsoft.com/en-us/aspnet/core/fundamentals/logging/#configure-logging
    log.ClearProviders() |> ignore
    //log.AddJsonConsole()
    log.AddConsole()

  webHost args {
    host configureHost
    web_host configureWebHost
    logging configureLogging
    not_found ErrorController.notFound

    endpoints [
      get Route.index <| Response.ofPlainText "Hello, world!"
      any Route.Meta.debug Response.debugRequest
      get Route.Meta.liveness Liveness.handle
      get Route.Meta.readiness Readiness.handle
      get Route.Meta.startup Startup.handle
      get Route.V1.OAuth.Dropbox.register OAuth.Dropbox.handleRegister
      post Route.V1.Todoist.webhookEvents Todoist.SyncApi.WebhookEvent.handler
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
