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
// Recipient split (Phase 4): `From`/ORGANIZER = `smtp.From` (the musync send
// address); `To`/ATTENDEE = `userEmail` (the user's primary Proton mailbox, from
// Config.UserEmail). This closes the Phase-3 gap where both were `smtp.From`.

type SmtpCalendarTarget(smtp: SmtpConfig, userEmail: string) =
  let sender = EmailSender(smtp)

  interface ICalendarTarget with
    member _.SendInvite(concert) =
      async {
        use message = Musync.Calendar.buildMessage concert smtp.From userEmail
        let! result = sender.Send message
        // EmailSender is port-agnostic (Result<_, string>); map onto CalendarError.
        return result |> Result.mapError CalendarError
      }
