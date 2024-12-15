[<AutoOpen>]
module AutoMate.Tests.Core

/// Wrap Expecto without need to supply `message` and enable currying by swapping `expected` and `actual` arguments.
[<RequireQualifiedAccess>]
module Want =
  open Expecto

  /// Want actual to equal expected.
  let equal (expected: 'T) (actual: 'T) =
    let message = $"Wanted {actual} == {expected}"
    Expect.equal actual expected message

  /// Want f to throw an exception.
  let throws f =
    let message = "Wanted a thrown exception"
    Expect.throws f message

  /// Want Ok.
  let isOk actual =
    let message = "Wanted Ok"
    Expect.isOk actual message
