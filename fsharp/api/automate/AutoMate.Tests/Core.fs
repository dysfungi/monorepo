[<AutoOpen>]
module AutoMate.Tests.Core

/// Wrap Expecto without need to supply `message` and enable currying by swapping `expected` and `actual` arguments.
[<RequireQualifiedAccess>]
module Want =
  open Expecto

  /// Want actual to equal expected.
  let equal (expected: 'T) (actual: 'T) =
    Expect.equal actual expected $"Wanted {actual} == {expected}"

  /// Want f to throw an exception.
  let throws f =
    Expect.throws f "Wanted a thrown exception"

  /// Want Ok and retun wrapped value.
  let wantOk result = Expect.wantOk result "Wanted Ok result"
  /// Want Ok.
  let isOk result = Expect.isOk result "Wanted Ok result"
