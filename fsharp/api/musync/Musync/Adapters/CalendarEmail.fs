module Musync.Adapters.CalendarEmail

open Musync.Errors
open Musync.Config
open Musync.Ports
open Musync.Email

// OUTBOUND `ICalendarTarget` adapter: builds the ICS-by-email invite (pure
// `Calendar` module) and delivers it via the reusable `EmailSender`. Proton has
// no calendar-write API, so this is the whole "write" path — the user's native
// client ingests the emailed METHOD:REQUEST invite.
//
// Self-invite: the invite's From/To/ORGANIZER/ATTENDEE are all the user's own
// mailbox (`smtp.From`). Whether the recipient should instead be the user's
// PRIMARY Proton address (vs the musync send address) is a live-apply question —
// see the phase notes.

type SmtpCalendarTarget(smtp: SmtpConfig) =
  let sender = EmailSender(smtp)

  interface ICalendarTarget with
    member _.SendInvite(concert) =
      async {
        use message = Musync.Calendar.buildMessage concert smtp.From
        let! result = sender.Send message
        // EmailSender is port-agnostic (Result<_, string>); map onto CalendarError.
        return result |> Result.mapError CalendarError
      }
