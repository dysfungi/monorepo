module Musync.SetlistCurate

open System
open Musync.Errors
open Musync.Domain
open Musync.Ports
open Musync.Persistence

// Drives the setlist state machine for ONE in-window concert:
//   recompute ProbableSetlist -> store it -> existence check ->
//     confident-exists  => stamp setlist_found_at (TERMINAL, no email)
//     missing + unnotified => send nudge, stamp setlist_notified_at (DEDUPE)
//     missing + notified   => nothing more (already nudged once)
// Kept out of `Program` so it is unit/integration testable with injected
// `ISetlistProvider` / `INotifier` stubs and an injected clock.
//
// The caller (`listCurateWindow`) has already filtered to: not past, within the
// horizon, and `setlist_found_at IS NULL`. RECOMPUTE POLICY: every run (while not
// found) re-derives + overwrites the prediction, so a growing tour history keeps
// sharpening the guess right up until the entry is found.

/// Outcome of a single curate step, for the caller to tally + log.
type CurateStepResult =
  /// A confident Setlist.fm match was found; `setlist_found_at` stamped (terminal).
  | Found
  /// No entry yet — nudge sent and `setlist_notified_at` stamped (first time only).
  | Nudged
  /// No entry yet, but the nudge was already sent on a prior run — prediction was
  /// recomputed/stored, nothing emailed.
  | AlreadyNotified
  /// A prediction or notify failure; recorded (attempts++/last_error) + WARN-logged.
  /// NOT a hard error — the run continues and the next run retries.
  | Failed of string

let private warn (msg: string) =
  eprintfn "[musync] WARN setlist: %s" msg

/// Run the curate state machine for one row. Returns `Error` ONLY for an
/// infrastructure failure (row rehydrate or a DB write) — a provider/notify
/// failure is captured as `Ok (Failed _)` so one bad concert never aborts the run.
let runStep
  (databaseUrl: string)
  (provider: ISetlistProvider)
  (notifier: INotifier)
  (now: unit -> DateTimeOffset)
  (row: ConcertRow)
  : Async<Result<CurateStepResult, MusyncError>> =
  async {
    match toConcert row with
    | Error err -> return Error err
    | Ok concert ->
      // 1. (re)compute the probable setlist.
      let! predicted = provider.PredictSetlist concert.Artist

      match predicted with
      | Error err ->
        let msg = sprintf "%A" err
        warn (sprintf "predict failed (uid=%s): %s" row.SongkickUid msg)

        match recordSetlistError databaseUrl concert.Id msg with
        | Ok() -> return Ok(Failed msg)
        | Error dbErr -> return Error dbErr
      | Ok setlist ->
        // 2. store the recomputed prediction (overwrite policy).
        match
          storeProbableSetlist
            databaseUrl
            concert.Id
            (serializeSetlist setlist)
            setlist.ComputedAt
        with
        | Error dbErr -> return Error dbErr
        | Ok() ->
          // 3. existence check (fail-open: only a confident match => true).
          let! exists = provider.SetlistExists concert

          match exists with
          | Error err ->
            let msg = sprintf "%A" err
            warn (sprintf "existence check failed (uid=%s): %s" row.SongkickUid msg)

            match recordSetlistError databaseUrl concert.Id msg with
            | Ok() -> return Ok(Failed msg)
            | Error dbErr -> return Error dbErr
          | Ok true ->
            // Terminal: a real entry exists — stamp found, never nudge.
            match markSetlistFound databaseUrl concert.Id (now ()) with
            | Ok() -> return Ok Found
            | Error dbErr -> return Error dbErr
          | Ok false ->
            // Missing. Nudge exactly once (dedupe on setlist_notified_at).
            if Option.isSome row.SetlistNotifiedAt then
              return Ok AlreadyNotified
            else
              let! sent = notifier.SendSetlistNudge(concert, setlist)

              match sent with
              | Ok() ->
                match markSetlistNotified databaseUrl concert.Id (now ()) with
                | Ok() -> return Ok Nudged
                | Error dbErr -> return Error dbErr
              | Error err ->
                let msg = sprintf "%A" err
                warn (sprintf "nudge send failed (uid=%s): %s" row.SongkickUid msg)

                match recordSetlistError databaseUrl concert.Id msg with
                | Ok() -> return Ok(Failed msg)
                | Error dbErr -> return Error dbErr
  }
