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

  /// Want Some option and return wrapped value.
  let wantSome opt =
    Expect.wantSome opt "Wanted Some option"

  /// Want Some option.
  let isSome opt = Expect.isSome opt "Wanted Some option"
  /// Want Ok result and return wrapped value.
  let wantOk result = Expect.wantOk result "Wanted Ok result"
  /// Want Ok result.
  let isOk result = Expect.isOk result "Wanted Ok result"

  /// Want Error result.
  let isError result =
    Expect.isError result "Wanted Error result"
