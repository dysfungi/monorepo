module Musync.Errors

/// The failure surface for musync. Every port and use case returns
/// `Result<_, MusyncError>` so failures are explicit and total.
///
/// WHY a single DU: it keeps the error channel closed and pattern-matchable
/// end-to-end (source -> domain -> calendar/setlist/notify -> persistence),
/// rather than leaking adapter-specific exception types across seams.
type MusyncError =
  /// Domain validation failed; carries one message per invalid field.
  | ValidationError of string list
  /// A show source (e.g. Songkick ICS feed) could not be read/parsed.
  | SourceError of string
  /// A calendar target (e.g. SMTP iCal invite) failed to deliver.
  | CalendarError of string
  /// A setlist provider (e.g. Setlist.fm) failed to predict/lookup.
  | SetlistError of string
  /// A notifier (e.g. email nudge) failed to deliver.
  | NotifyError of string
  /// A persistence operation (e.g. the concerts table) failed.
  | PersistenceError of string
