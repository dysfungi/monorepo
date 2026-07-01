module Musync.Adapters.Notifier

open System
open System.Text
open MimeKit
open MimeKit.Text
open Musync.Errors
open Musync.Config
open Musync.Domain
open Musync.Ports
open Musync.Email

// OUTBOUND `INotifier`: the pre-show setlist nudge. Builds a plain+HTML email —
// the predicted setlist as an ordered list, the Setlist.fm "create" deep-link,
// and the show details — and delivers it via the SAME reusable `EmailSender` the
// calendar path uses (no second SMTP client). `From` = `smtp.From` (musync send
// address); `To` = `userEmail` (the user's Proton mailbox, Config.UserEmail).
//
// `buildNudgeMessage` is PURE (a deterministic function of its inputs) so the
// content is unit/integration testable without a live relay.

let private showLine (concert: Concert) : string =
  sprintf
    "%s at %s — %s, %s"
    (ArtistName.value concert.Artist)
    concert.Venue
    concert.City
    concert.Country

/// Plain-text body: numbered predicted setlist + the create link. An empty
/// prediction (debut artist / no tour history) still nudges — the user may know
/// the setlist even when Setlist.fm has no tour history to rank.
let private plainBody
  (concert: Concert)
  (setlist: ProbableSetlist)
  (createUrl: string)
  : string =
  let sb = StringBuilder()
  sb.AppendLine(showLine concert).AppendLine() |> ignore

  sb
    .AppendLine("No Setlist.fm entry was found for this show yet.")
    .AppendLine("Predicted setlist (ranked from the artist's recent shows):")
    .AppendLine()
  |> ignore

  if List.isEmpty setlist.Songs then
    sb.AppendLine("  (no recent tour history to predict from)") |> ignore
  else
    for song in setlist.Songs do
      sb.AppendLine(sprintf "  %d. %s" song.Position song.Name) |> ignore

  sb.AppendLine().AppendLine(sprintf "Create it on Setlist.fm: %s" createUrl)
  |> ignore

  sb.ToString()

/// HTML body: same content as an ordered list + an anchor to the create page.
let private htmlBody
  (concert: Concert)
  (setlist: ProbableSetlist)
  (createUrl: string)
  : string =
  let escape (s: string) =
    s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")

  let items =
    setlist.Songs
    |> List.map (fun song -> sprintf "    <li>%s</li>" (escape song.Name))
    |> String.concat "\n"

  let list =
    if List.isEmpty setlist.Songs then
      "  <p><em>No recent tour history to predict from.</em></p>"
    else
      sprintf "  <ol>\n%s\n  </ol>" items

  sprintf
    "<p>%s</p>\n<p>No Setlist.fm entry was found for this show yet. Predicted setlist \
     (ranked from the artist's recent shows):</p>\n%s\n<p><a href=\"%s\">Create it on \
     Setlist.fm</a></p>"
    (escape (showLine concert))
    list
    (escape createUrl)

/// Build the nudge MIME message. `fromAddress` = musync send address; `toAddress`
/// = the user's mailbox. Caller owns disposal.
let buildNudgeMessage
  (fromAddress: string)
  (toAddress: string)
  (concert: Concert)
  (setlist: ProbableSetlist)
  : MimeMessage =
  let createUrl = Musync.Adapters.Setlist.createSetlistUrl concert

  let msg = new MimeMessage()
  msg.From.Add(MailboxAddress("musync", fromAddress))
  msg.To.Add(MailboxAddress("musync", toAddress))

  msg.Subject <-
    sprintf "Setlist nudge: %s at %s" (ArtistName.value concert.Artist) concert.Venue

  let plain = new TextPart(TextFormat.Plain)
  plain.Text <- plainBody concert setlist createUrl
  let html = new TextPart(TextFormat.Html)
  html.Text <- htmlBody concert setlist createUrl

  let alternative = new MultipartAlternative()
  alternative.Add plain
  alternative.Add html
  msg.Body <- alternative
  msg

let private stepLabel (step: StuckStep) : string =
  match step with
  | StuckStep.Calendar -> "calendar"
  | StuckStep.Setlist -> "setlist"

let private stuckLine (item: StuckItem) : string =
  sprintf
    "- %s [%s] first failed %s; last error: %s"
    (ArtistName.value item.Artist)
    (stepLabel item.Step)
    (item.FirstFailedAt.ToString("u"))
    (item.LastError |> Option.defaultValue "(none)")

/// Build the consolidated stuck-work alert: ONE plain-text email to the user
/// listing each stuck (concert, step) with its first-failure time and last error.
let buildStuckAlertMessage
  (fromAddress: string)
  (toAddress: string)
  (items: StuckItem list)
  : MimeMessage =
  let msg = new MimeMessage()
  msg.From.Add(MailboxAddress("musync", fromAddress))
  msg.To.Add(MailboxAddress("musync", toAddress))
  msg.Subject <- sprintf "musync: %d item(s) stuck >24h" (List.length items)

  let sb = StringBuilder()

  sb
    .AppendLine("These musync delivery steps have been failing for over 24 hours:")
    .AppendLine()
  |> ignore

  for item in items do
    sb.AppendLine(stuckLine item) |> ignore

  let plain = new TextPart(TextFormat.Plain)
  plain.Text <- sb.ToString()
  msg.Body <- plain
  msg

/// `INotifier` adapter. Delivers both the nudge and the stuck-work alert via the
/// reused `EmailSender`, mapping the raw send error onto `NotifyError`.
type SmtpNotifier(smtp: SmtpConfig, userEmail: string) =
  let sender = EmailSender(smtp)

  interface INotifier with
    member _.SendSetlistNudge(concert, setlist) =
      async {
        use message = buildNudgeMessage smtp.From userEmail concert setlist
        let! result = sender.Send message
        return result |> Result.mapError NotifyError
      }

    member _.SendStuckAlert(items) =
      async {
        use message = buildStuckAlertMessage smtp.From userEmail items
        let! result = sender.Send message
        return result |> Result.mapError NotifyError
      }
