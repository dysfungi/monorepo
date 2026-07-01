module Musync.CalendarSync

open System
open Musync.Errors
open Musync.Ports
open Musync.Persistence

// Drives the calendar state machine for ONE concert: Tx A (decide + bump/clear)
// -> send the invite -> Tx B (mark sent | record error). Kept out of `Program`
// so it is unit/integration testable with an injected `ICalendarTarget` stub and
// an injected clock (no wall-clock flakiness).

/// Outcome of a single calendar step, for the caller to tally + log.
type CalStepResult =
  /// (Re)sent at the given SEQUENCE and stamped `calendar_sent_at`.
  | Sent of int
  /// Hash unchanged and already delivered — nothing to do.
  | Skipped
  /// The send attempt failed; the error was recorded and WARN-logged. NOT a hard
  /// error: the run continues and the next run retries the same UID+SEQUENCE.
  | SendFailed of string

let private warn (msg: string) =
  eprintfn "[musync] WARN calendar: %s" msg

/// Run the state machine for one row. Returns `Error` ONLY for an infrastructure
/// failure in a DB transaction (Tx A / Tx B) — a send failure is captured as
/// `Ok (SendFailed _)` so a single bad invite never aborts the whole poll.
let runStep
  (databaseUrl: string)
  (target: ICalendarTarget)
  (now: unit -> DateTimeOffset)
  (row: ConcertRow)
  : Async<Result<CalStepResult, MusyncError>> =
  async {
    match toConcert row with
    | Error err -> return Error err
    | Ok concert ->
      let uid = Calendar.uidFor concert.Id
      let hash = Calendar.contentHash concert

      match prepareCalendarInvite databaseUrl concert.Id uid hash with
      | Error err -> return Error err
      | Ok decision ->
        if not decision.NeedsSend then
          return Ok Skipped
        else
          // Carry the Tx-A sequence (it may have just been bumped) into the send.
          let toSend = {
            concert with
                CalendarSequence = decision.Sequence
                CalendarUid = Some decision.Uid
          }

          let! sendResult = target.SendInvite toSend

          match sendResult with
          | Ok() ->
            match markCalendarSent databaseUrl concert.Id (now ()) with
            | Ok() -> return Ok(Sent decision.Sequence)
            | Error err -> return Error err
          | Error sendErr ->
            let msg = sprintf "%A" sendErr

            warn (
              sprintf
                "invite send failed (id=%O uid=%s seq=%d): %s"
                concert.Id
                uid
                decision.Sequence
                msg
            )

            match recordCalendarError databaseUrl concert.Id msg with
            | Ok() -> return Ok(SendFailed msg)
            | Error err -> return Error err
  }
