module Musync.Ports

open Musync.Errors
open Musync.Domain

// Hexagonal ports (interfaces only — adapters land in later phases). Every
// method is `Async<Result<_, MusyncError>>` so I/O failures stay on the error
// channel rather than throwing across the seam.

/// Source of truth for what shows the user is going to (e.g. Songkick ICS).
type IShowSource =
  abstract member FetchGoingConcerts: unit -> Async<Result<Concert list, MusyncError>>

/// Where calendar invites are delivered (e.g. an iCal email via SMTP).
type ICalendarTarget =
  abstract member SendInvite: Concert -> Async<Result<unit, MusyncError>>

/// Predicts setlists and reports whether an actual setlist has been posted.
type ISetlistProvider =
  abstract member PredictSetlist:
    ArtistName -> Async<Result<ProbableSetlist, MusyncError>>

  abstract member SetlistExists: Concert -> Async<Result<bool, MusyncError>>

/// Sends the pre-show setlist nudge for a concert, plus the daily consolidated
/// alert for work that has stayed stuck past the self-heal window.
type INotifier =
  abstract member SendSetlistNudge:
    Concert * ProbableSetlist -> Async<Result<unit, MusyncError>>

  abstract member SendStuckAlert: StuckItem list -> Async<Result<unit, MusyncError>>
