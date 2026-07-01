module Musync.Calendar

open System
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
//   1. `contentHash` — a stable SHA-256 over ONLY the VEVENT-projected fields,
//      used by the state machine to detect a material change (and bump SEQUENCE).
//   2. `buildIcs`     — the iCalendar (RFC-5545) text: an ALL-DAY VEVENT with a
//      musync-owned UID, METHOD:REQUEST, and organizer==attendee self-invite.
//   3. `buildMessage` — the `text/calendar; method=REQUEST` MIME message the
//      Proton client ingests.
// No I/O, no clock, no DB — every output is a deterministic function of the
// Concert's show fields (+ CalendarSequence for the ICS SEQUENCE line). The
// hash deliberately excludes CalendarSequence and all delivery/setlist state so
// those columns can never churn the hash.

/// musync-owned UID for a concert's calendar event. STABLE across resends — it
/// is the correctness boundary: the same UID+SEQUENCE is idempotent in the
/// user's calendar, so a crash-driven resend updates rather than duplicates.
let uidFor (id: Guid) : string =
  sprintf "concert-%s@musync.frank.sh" (id.ToString())

// Songkick gives a bare floating DATE (no showtime — see Phase 2), so the venue-
// local calendar date is the canonical "show date". Convert the stored instant
// back into the venue tz and take its date; on an unknown tz id, fall back to
// UTC (the same zone `resolveStart` would have stored).
let private localYmd (startsAt: DateTimeOffset) (tz: string) : int * int * int =
  let local =
    try
      let zone = TimeZoneInfo.FindSystemTimeZoneById tz
      TimeZoneInfo.ConvertTime(startsAt, zone)
    with _ ->
      startsAt.ToUniversalTime()

  local.Year, local.Month, local.Day

/// Exactly the fields projected onto the VEVENT. Shared by `contentHash`,
/// `buildIcs`, and `buildMessage` so the hash and the emitted event can never
/// disagree on what was sent.
type private Projected = {
  Artist: string
  Venue: string
  City: string
  Country: string
  Year: int
  Month: int
  Day: int
  DtStart: string
  DtEnd: string
  Location: string
  Description: string
}

let private project (c: Concert) : Projected =
  // Trim everywhere; case-fold ONLY the country code (a case-insensitive 2-letter
  // token). Artist/venue/city keep their case so a real display change (e.g. a
  // capitalization fix in the feed) still yields a new hash and a resend.
  let artist = (ArtistName.value c.Artist).Trim()
  let venue = c.Venue.Trim()
  let city = c.City.Trim()
  let country = c.Country.Trim().ToUpperInvariant()
  let (y, m, d) = localYmd c.StartsAt c.Tz
  // All-day VEVENT: DTEND is the EXCLUSIVE next day (RFC-5545 all-day convention).
  let endDate = DateTime(y, m, d).AddDays 1.0

  {
    Artist = artist
    Venue = venue
    City = city
    Country = country
    Year = y
    Month = m
    Day = d
    DtStart = sprintf "%04d%02d%02d" y m d
    DtEnd = endDate.ToString "yyyyMMdd"
    Location = sprintf "%s, %s, %s" venue city country
    Description =
      sprintf
        "%s at %s (%s, %s). Added to your calendar by musync."
        artist
        venue
        city
        country
  }

/// SHA-256 (lowercase hex) over a canonical, fixed-order serialization of the
/// VEVENT-projected fields. Labelled `KEY=value` lines joined by '\n' keep field
/// boundaries unambiguous. Includes the literal all-day marker so a hypothetical
/// switch to a timed event would change the hash.
let contentHash (c: Concert) : string =
  let p = project c

  let canonical =
    [
      "VALUE=DATE"
      "SUMMARY=" + p.Artist
      "DTSTART=" + p.DtStart
      "DTEND=" + p.DtEnd
      "LOCATION=" + p.Venue + "|" + p.City + "|" + p.Country
      "DESCRIPTION=" + p.Description
    ]
    |> String.concat "\n"

  canonical
  |> Encoding.UTF8.GetBytes
  |> SHA256.HashData
  |> Array.map (fun b -> b.ToString "x2")
  |> String.concat ""

/// Build the iCalendar text for a concert. `userAddress` is the user's own
/// mailbox: because Proton has no calendar-write API, musync mails the user an
/// invite that the native client ingests — so ORGANIZER and ATTENDEE are the
/// SAME address (a self-invite). SEQUENCE comes from `c.CalendarSequence`.
let buildIcs (c: Concert) (userAddress: string) : string =
  let p = project c

  let cal = Calendar()
  cal.Method <- "REQUEST"

  let evt = CalendarEvent()
  evt.Uid <- uidFor c.Id
  evt.Sequence <- c.CalendarSequence
  evt.Summary <- p.Artist
  evt.Location <- p.Location
  evt.Description <- p.Description
  // Date-only CalDateTime + IsAllDay => DTSTART;VALUE=DATE / DTEND;VALUE=DATE.
  evt.Start <- CalDateTime(p.Year, p.Month, p.Day)
  let e = DateTime(p.Year, p.Month, p.Day).AddDays 1.0
  evt.End <- CalDateTime(e.Year, e.Month, e.Day)
  evt.IsAllDay <- true

  let mailto = "mailto:" + userAddress
  evt.Organizer <- Organizer(mailto)
  let attendee = Attendee(mailto)
  attendee.ParticipationStatus <- "NEEDS-ACTION"
  attendee.Rsvp <- true
  evt.Attendees.Add attendee

  cal.Events.Add evt
  CalendarSerializer().SerializeToString cal

/// Wrap the ICS as a `multipart/alternative` (text/plain + text/calendar;
/// method=REQUEST) message. Self-invite => From == To == `userAddress`. Caller
/// owns disposal of the returned message.
let buildMessage (c: Concert) (userAddress: string) : MimeMessage =
  let p = project c
  let ics = buildIcs c userAddress

  let msg = new MimeMessage()
  msg.From.Add(MailboxAddress("musync", userAddress))
  msg.To.Add(MailboxAddress("musync", userAddress))
  msg.Subject <- sprintf "%s at %s" p.Artist p.Venue

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
