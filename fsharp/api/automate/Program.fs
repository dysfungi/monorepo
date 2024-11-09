namespace AutoMate

[<AutoOpen>]
module Program =
  open Falco
  open Falco.Routing
  open Falco.HostBuilder

  module Health =
    type Alive = { Status: string }
    type Ready = { Status: string }
    type Startup = { Status: string }

  open Health

  [<EntryPoint>]
  let main args =

    webHost args {
      endpoints [
        get "/" (Response.ofPlainText "Hello world")
        get "/v1/todoist/webhook-events" (Todoist.WebhookEvent.handler)
        // https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring
        // https://andrewlock.net/deploying-asp-net-core-applications-to-kubernetes-part-6-adding-health-checks-with-liveness-readiness-and-startup-probes/#the-three-kinds-of-probe-liveness-readiness-and-startup-probes
        get "/-/alive" (Response.ofJson { Status = "OK" })
        get // TODO: latency for readiness checks?
          "/-/ready"
          (Response.ofJson { Status = "OK" })
        get "/-/startup" (Response.ofJson { Status = "OK" })
      ]
    }

    0
