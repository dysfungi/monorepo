namespace AutoMate.Domain

type Trigger = {
  Id: string
  Type: string
  Name: string
  Enabled: bool
}

type Action = {
  Id: string
  Type: string
  Name: string
  Enabled: bool
}

type Constraint = {
  Id: string
  Type: string
  Name: string
  Enabled: bool
}

type Automation = {
  /// Triggered by any.
  Triggers: Trigger list

  /// Actioned in order.
  Actions: Action list

  /// Constrained by all.
  Constraints: Constraint list
}
