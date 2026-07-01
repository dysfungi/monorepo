module Musync.Calendar

open System
open System.Globalization
open System.Security.Cryptography
open System.Text
open Ical.Net
open Ical.Net.CalendarComponents
open Ical.Net.DataTypes
open Ical.Net.Serialization
open MimeKit
open MimeKit.Text
open Musync.Domain

// PURE calendar projection. Given a `Concert`, this module produces:
//   1. `contentHash` — a stable SHA-256 over ONLY the material identity
//      (artist · show date · venue), used by the state machine to decide whether
//      to (re)send. It deliberately EXCLUDES times/openers/vendor/description/
//      location so late enrichment or the user's own hand-edits never trigger a
//      clobbering resend — only a true reschedule or relocation does.
//   2. `buildIcs`     — the iCalendar (RFC-5545) text: a TIMED VEVENT with a
//      musync-owned UID, METHOD:REQUEST, and organizer/attendee self-invite.
//   3. `buildMessage` — the `text/calendar; method=REQUEST` MIME message the
//      Proton client ingests.
// No I/O, no clock, no DB — every output is a deterministic function of the
// Concert (+ CalendarSequence for the ICS SEQUENCE line).

/// musync-owned UID for a concert's calendar event. STABLE across resends — it
/// is the correctness boundary: the same UID+SEQUENCE is idempotent in the
/// user's calendar, so a crash-driven resend updates rather than duplicates.
let uidFor (id: Guid) : string =
  sprintf "concert-%s@musync.frank.sh" (id.ToString())

/// The venue-local calendar date of the show. Convert the stored instant into the
/// venue tz and take its date; on an unknown tz id, fall back to UTC (the zone
/// `Songkick.resolveStart` would have stored).
let private localYmd (startsAt: DateTimeOffset) (tz: string) : int * int * int =
  let local =
    try
      let zone = TimeZoneInfo.FindSystemTimeZoneById tz
      TimeZoneInfo.ConvertTime(startsAt, zone)
    with _ ->
      startsAt.ToUniversalTime()

  local.Year, local.Month, local.Day

/// The venue-local wall-clock for an instant (used to render DTSTART and the
/// doors/show times). Unknown tz id falls back to the UTC wall time.
let private localWall (instant: DateTimeOffset) (tz: string) : DateTime =
  try
    let zone = TimeZoneInfo.FindSystemTimeZoneById tz
    TimeZoneInfo.ConvertTime(instant, zone).DateTime
  with _ ->
    instant.UtcDateTime

/// Human clock label, e.g. 19:00 -> "7 PM", 19:30 -> "7:30 PM".
let private clockLabel (dt: DateTime) : string =
  let pattern = if dt.Minute = 0 then "h tt" else "h:mm tt"
  dt.ToString(pattern, CultureInfo.InvariantCulture)

/// A Google Maps search deep-link for "<venue>, <city>".
let private mapsLink (venue: string) (city: string) : string =
  let query = Uri.EscapeDataString(sprintf "%s, %s" venue city)
  sprintf "https://www.google.com/maps/search/?api=1&query=%s" query

/// The event's start as a venue-local wall time: doors if known, else show, else a
/// labeled 19:00 fallback on the show date. Drives DTSTART.
let private startLocal (c: Concert) : DateTime =
  match c.EventStartAt with
  | Some instant -> localWall instant c.Tz
  | None ->
    let (y, m, d) = localYmd c.StartsAt c.Tz
    DateTime(y, m, d, 19, 0, 0)

/// Exactly the fields projected onto the VEVENT (shared by `buildIcs` and
/// `buildMessage`). NOT hashed — see `contentHash`.
type private Projected = {
  Summary: string
  Location: string
  Description: string
  Tz: string
  Start: DateTime
  End: DateTime
}

let private project (c: Concert) : Projected =
  let artist = (ArtistName.value c.Artist).Trim()
  let venue = c.Venue.Trim()
  let city = c.City.Trim()
  let start = startLocal c
  // Fixed 23:30 (11:30 PM) venue-local end unless a real end is known (it isn't —
  // Songkick's `endDate` is a date-only placeholder).
  let ending = DateTime(start.Year, start.Month, start.Day, 23, 30, 0)

  let label (instant: DateTimeOffset option) =
    instant
    |> Option.map (fun i -> clockLabel (localWall i c.Tz))
    |> Option.defaultValue "?"

  let vendor =
    c.TicketVendor |> Option.map (fun t -> t.Name) |> Option.defaultValue "?"

  let openers =
    if List.isEmpty c.Openers then
      "?"
    else
      String.concat ", " c.Openers

  {
    Summary = sprintf "%s @ %s" artist venue
    Location = mapsLink venue city
    Description =
      sprintf
        "App: %s\nOpeners: %s\nSeats: ?\nDoors: %s\nShow: %s\n\n%s"
        vendor
        openers
        (label c.DoorsAt)
        (label c.ShowAt)
        (c.SongkickEventUrl |> Option.defaultValue "?")
    Tz = c.Tz
    Start = start
    End = ending
  }

/// SHA-256 (lowercase hex) over ONLY the material identity — artist · venue-local
/// show date · venue — in a fixed, labelled order. This is the clobber-safety
/// boundary: the hash moves only on a reschedule (date) or relocation (venue), so
/// the state machine never resends over the user's hand-edits for late enrichment
/// or template changes.
let contentHash (c: Concert) : string =
  let artist = (ArtistName.value c.Artist).Trim()
  let venue = c.Venue.Trim()
  let (y, m, d) = localYmd c.StartsAt c.Tz

  let canonical =
    [
      "ARTIST=" + artist
      "DATE=" + sprintf "%04d%02d%02d" y m d
      "VENUE=" + venue
    ]
    |> String.concat "\n"

  canonical
  |> Encoding.UTF8.GetBytes
  |> SHA256.HashData
  |> Array.map (fun b -> b.ToString "x2")
  |> String.concat ""

/// Build the iCalendar text for a concert. Because Proton has no calendar-write
/// API, musync mails an invite the native client ingests. `organizerAddress` is
/// the musync SEND address (ORGANIZER); `attendeeAddress` is the user's own
/// mailbox (ATTENDEE) — the invitee whose calendar the event lands in. SEQUENCE
/// comes from `c.CalendarSequence`.
let buildIcs
  (c: Concert)
  (organizerAddress: string)
  (attendeeAddress: string)
  : string =
  let p = project c

  let cal = Calendar()
  cal.Method <- "REQUEST"

  let evt = CalendarEvent()
  evt.Uid <- uidFor c.Id
  evt.Sequence <- c.CalendarSequence
  evt.Summary <- p.Summary
  evt.Location <- p.Location
  evt.Description <- p.Description
  // Timed VEVENT: DTSTART;TZID=<venue IANA> at the resolved start, DTEND at 23:30.
  // The 7-arg CalDateTime ctor sets HasTime, so these serialize as zoned datetimes.
  evt.Start <-
    CalDateTime(
      p.Start.Year,
      p.Start.Month,
      p.Start.Day,
      p.Start.Hour,
      p.Start.Minute,
      0,
      p.Tz
    )

  evt.End <-
    CalDateTime(p.End.Year, p.End.Month, p.End.Day, p.End.Hour, p.End.Minute, 0, p.Tz)

  evt.Organizer <- Organizer("mailto:" + organizerAddress)
  let attendee = Attendee("mailto:" + attendeeAddress)
  attendee.ParticipationStatus <- "NEEDS-ACTION"
  attendee.Rsvp <- true
  evt.Attendees.Add attendee

  cal.Events.Add evt
  CalendarSerializer().SerializeToString cal

/// Wrap the ICS as a `multipart/alternative` (text/plain + text/calendar;
/// method=REQUEST) message. `From` = `organizerAddress` (musync send address);
/// `To` = `attendeeAddress` (the user's mailbox). Caller owns disposal.
let buildMessage
  (c: Concert)
  (organizerAddress: string)
  (attendeeAddress: string)
  : MimeMessage =
  let p = project c
  let ics = buildIcs c organizerAddress attendeeAddress

  let msg = new MimeMessage()
  msg.From.Add(MailboxAddress("musync", organizerAddress))
  msg.To.Add(MailboxAddress("musync", attendeeAddress))
  msg.Subject <- p.Summary

  let plain = new TextPart(TextFormat.Plain)
  plain.Text <- p.Description

  // text/calendar; method=REQUEST; charset=utf-8 — the part Proton ingests.
  let calPart = new TextPart("calendar")
  calPart.ContentType.Parameters.Add("method", "REQUEST")
  calPart.ContentType.Parameters.Add("name", "invite.ics")
  calPart.Text <- ics

  let alternative = new MultipartAlternative()
  alternative.Add plain
  alternative.Add calPart
  msg.Body <- alternative
  msg
