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
      get "/" (Response.ofPlainText "Hello world")
      post
        "/v1/todoist/webhook-events"
        Integrations.Todoist.SyncApi.WebhookEvent.handler
      // https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring
      // https://andrewlock.net/deploying-asp-net-core-applications-to-kubernetes-part-6-adding-health-checks-with-liveness-readiness-and-startup-probes/#the-three-kinds-of-probe-liveness-readiness-and-startup-probes
      get "/-/alive" Alive.handle
      get // TODO: latency for readiness checks?
        "/-/ready"
        Ready.handle
      get "/-/startup" Startup.handle
      any "/-/debug" Response.debugRequest
    ]
  }

  0
