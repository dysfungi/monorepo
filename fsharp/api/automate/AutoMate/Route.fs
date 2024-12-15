module AutoMate.Route

let index = "/"

[<AutoOpen>]
module Meta =
  let internal meta = index + "-"
  let debug = meta + "/debug"
  let liveness = meta + "/liveness"
  let readiness = meta + "/readiness"
  let startup = meta + "/startup"

[<RequireQualifiedAccess>]
module V1 =
  let internal v1 = index + "v1"

  [<RequireQualifiedAccess>]
  module OAuth =
    let internal oauth = v1 + "/oauth"
    let internal register = oauth + "/register"

    [<RequireQualifiedAccess>]
    module Dropbox =
      let register = register + "/dropbox"

  [<RequireQualifiedAccess>]
  module Todoist =
    let internal todoist = v1 + "/todoist"
    let webhookEvents = todoist + "/webhook-events"
