module Musync.Tests.SongkickEnrichTests

open System
open System.IO
open Expecto
open Musync.Domain
open Musync.Adapters.SongkickEnrich

// Unit tests for the PURE `parseConcertPage` — no network. Driven by two captured
// fixtures: the REAL Songkick page (show time only; doors/openers/vendor absent =>
// None) and a synthetic FULL page exercising every present path. `startDate` has no
// tz offset, so the parser interprets it in the venue IANA zone passed in.

let private venueTz = "America/Los_Angeles"

let private fixture (name: string) =
  Path.Combine(AppContext.BaseDirectory, "fixtures", name) |> File.ReadAllText

let private parse (name: string) =
  parseConcertPage venueTz (fixture name) |> Want.ok

[<Tests>]
let songkickEnrichTests =
  testList "songkick enrich" [
    testList "real page (mostly unknown)" [
      testCase "startDate -> ShowAt, interpreted in the venue zone"
      <| fun _ ->
        let e = parse "songkick_concert_page.html"
        // 2026-08-17T19:00:00 in America/Los_Angeles (PDT, -07:00) == 02:00Z next day.
        Want.equal
          (Some(DateTime(2026, 8, 18, 2, 0, 0)))
          (e.ShowAt |> Option.map (fun d -> d.UtcDateTime))

      testCase "absent doorTime / openers / seller => None or empty"
      <| fun _ ->
        let e = parse "songkick_concert_page.html"
        Want.equal None e.DoorsAt
        Want.equal [] e.Openers
        Want.equal None e.TicketVendor
    ]

    testList "full page (all fields present)" [
      testCase "doors and show times parse in the venue zone"
      <| fun _ ->
        let e = parse "songkick_concert_page_full.html"
        // Sept LA is still PDT (-07:00): doors 19:00 -> 02:00Z, show 20:00 -> 03:00Z.
        Want.equal
          (Some(DateTime(2026, 9, 6, 2, 0, 0)))
          (e.DoorsAt |> Option.map (fun d -> d.UtcDateTime))

        Want.equal
          (Some(DateTime(2026, 9, 6, 3, 0, 0)))
          (e.ShowAt |> Option.map (fun d -> d.UtcDateTime))

      testCase "openers are the performers AFTER the headliner"
      <| fun _ ->
        let e = parse "songkick_concert_page_full.html"

        Want.equal
          [
            "First Opener"
            "Second Opener"
          ]
          e.Openers

      testCase "ticket vendor comes from offers[].seller (name + deep-link url)"
      <| fun _ ->
        let e = parse "songkick_concert_page_full.html"

        Want.equal
          (Some {
            Name = "AXS"
            Url = "https://www.axs.com/events/123456/the-headliners-tickets"
          })
          e.TicketVendor
    ]

    testCase "venue tz drives the absolute instant (naive startDate)"
    <| fun _ ->
      // Same fixture, different zone => a different instant, proving we do NOT
      // trust a host-local offset for the tz-less startDate.
      let inLa =
        parseConcertPage "America/Los_Angeles" (fixture "songkick_concert_page.html")
        |> Want.ok

      let inNy =
        parseConcertPage "America/New_York" (fixture "songkick_concert_page.html")
        |> Want.ok

      Want.equal false (inLa.ShowAt = inNy.ShowAt)

    testCase "array-valued @type (['MusicEvent','Event']) is recognized"
    <| fun _ ->
      let html =
        """<html><head><script type="application/ld+json">"""
        + """[{"@type":["MusicEvent","Event"],"startDate":"2026-09-05T20:00:00","""
        + """"performer":[{"name":"Head"},{"name":"Op1"}]}]</script></head></html>"""

      let e = parseConcertPage venueTz html |> Want.ok
      Want.equal true (Option.isSome e.ShowAt)
      Want.equal [ "Op1" ] e.Openers

    testCase "headliner is dropped by position even when it has no name"
    <| fun _ ->
      let html =
        """<html><head><script type="application/ld+json">"""
        + """[{"@type":"MusicEvent","performer":[{"@type":"MusicGroup"},{"name":"RealOpener"}]}]"""
        + """</script></head></html>"""

      let e = parseConcertPage venueTz html |> Want.ok
      Want.equal [ "RealOpener" ] e.Openers

    testCase "no MusicEvent JSON-LD => Error (page shape change)"
    <| fun _ ->
      parseConcertPage venueTz "<html><head></head><body>nope</body></html>"
      |> Want.isError
  ]
