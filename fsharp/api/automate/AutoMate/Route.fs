module AutoMate.Route

let index = "/"

[<AutoOpen>]
module Meta =
  let private meta = index + "-"
  let config = meta + "/config"
  let debug = meta + "/debug"
  let liveness = meta + "/liveness"
  let readiness = meta + "/readiness"
  let startup = meta + "/startup"

[<RequireQualifiedAccess>]
module V1 =
  let private v1 = index + "v1"

  [<RequireQualifiedAccess>]
  module OAuth =
    let private oauth = v1 + "/oauth"
    let private authorize = oauth + "/authorize"
    let private register = oauth + "/register"

    [<RequireQualifiedAccess>]
    module Dropbox =
      let private suffix = "/dropbox"
      let authorize = authorize + suffix
      let register = register + suffix

  [<RequireQualifiedAccess>]
  module Todoist =
    let private todoist = v1 + "/todoist"
    let webhookEvents = todoist + "/webhook-events"
