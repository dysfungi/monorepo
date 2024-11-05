module AutoMate.Program

open Falco
open Falco.Routing
open Falco.HostBuilder

type Health = {
  Status: string
  Results: string list
}

type Alive = { Status: string }
type Ready = { Status: string }
type Startup = { Status: string }

[<EntryPoint>]
let main args =
  webHost args {
    endpoints [
      get "/" (Response.ofPlainText "Hello world")
      // https://learn.microsoft.com/en-us/azure/architecture/patterns/health-endpoint-monitoring
      // https://andrewlock.net/deploying-asp-net-core-applications-to-kubernetes-part-6-adding-health-checks-with-liveness-readiness-and-startup-probes/#the-three-kinds-of-probe-liveness-readiness-and-startup-probes
      get "/-/alive" (Response.ofJson { Status = "OK" })
      get // TODO: latency for readiness checks?
        "/-/ready"
        (Response.ofJson {
          Status = "OK"
          Results = []
        })
      get
        "/-/startup"
        (Response.ofJson {
          Status = "OK"
          Results = []
        })
    ]
  }

  0
