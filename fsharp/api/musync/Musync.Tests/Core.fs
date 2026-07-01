[<AutoOpen>]
module Musync.Tests.Core

/// Wrap Expecto without needing to supply `message`, and enable currying by
/// swapping `expected`/`actual`. Mirrors the AutoMate.Tests `Want` helper.
[<RequireQualifiedAccess>]
module Want =
  open Expecto

  /// Want actual to equal expected.
  let equal (expected: 'T) (actual: 'T) =
    Expect.equal actual expected $"Wanted {actual} == {expected}"

  /// Want Ok result and return the wrapped value.
  let ok result = Expect.wantOk result "Wanted Ok result"

  /// Want Ok result.
  let isOk result = Expect.isOk result "Wanted Ok result"

  /// Want Error result and return the wrapped value.
  let error result =
    Expect.wantError result "Wanted Error result"

  /// Want Error result.
  let isError result =
    Expect.isError result "Wanted Error result"
