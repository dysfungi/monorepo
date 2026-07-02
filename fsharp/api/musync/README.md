# musync — Live Show Sync Engine

Self-hosted, developer-first **concert-lifecycle automation** running on the Vultr
K8s cluster. Greenfield F# service (`net9.0`), **ports-and-adapters** (hexagonal),
with **Postgres as the single source of truth** — no always-on service; all work
runs from scheduled CronJobs and is idempotent.

## What it does

musync automates the manual fan-out triggered by buying a concert ticket. The MVP
covers two moments in a show's lifecycle:

1. **On purchase (months out)** — poll the Songkick attendance feed, persist the
   shows you're _Going_ to, and email a **timed Proton calendar invite** (ICS
   `METHOD:REQUEST`) enriched with doors/show times, openers, and ticket vendor.
2. **~3 days before the show** — predict the setlist from the artist's recent tour
   history and, if Setlist.fm has no entry yet, email a setlist-assist nudge with
   a create deep-link.

### MVP flow

```
Songkick attendance ICS  ──►  concerts (Postgres, source of truth)
                                   │
        ┌──────────────────────────┴───────────────────────────┐
        ▼                                                        ▼
poll-songkick  (~3h CronJob)                        curate-preshow (daily CronJob)
  fetch Going shows                                   for shows ~3 days out:
  enrich from concert page                              predict setlist (tour history)
  upsert concerts                                       if no Setlist.fm entry yet →
  send timed calendar invite  ─────►  Proton            email setlist-assist nudge
  (ICS-by-email, SMTP)                Calendar
```

## Architecture

Hexagonal — the domain never imports an adapter; everything crosses a port as
`Async<Result<_, MusyncError>>` so I/O failures stay on the error channel.

| Port               | Adapter                      | Responsibility                                                 |
| ------------------ | ---------------------------- | -------------------------------------------------------------- |
| `IShowSource`      | `Adapters/Songkick.fs`       | Songkick attendance ICS → _Going_ concerts                     |
| `IShowEnricher`    | `Adapters/SongkickEnrich.fs` | Concert-page JSON-LD → doors/show/openers/vendor (best-effort) |
| `ICalendarTarget`  | `Adapters/CalendarEmail.fs`  | Timed VEVENT delivered as ICS-by-email (`METHOD:REQUEST`)      |
| `ISetlistProvider` | `Adapters/Setlist.fs`        | Setlist.fm read: predict + existence check                     |
| `INotifier`        | `Adapters/Notifier.fs`       | SMTP: setlist nudge + consolidated stuck-item alert            |

Two Kubernetes CronJobs (`concurrencyPolicy: Forbid`, hardened pod spec):

- **`poll-songkick`** — ~every 3h: ingest → enrich → upsert → send calendar invites.
- **`curate-preshow`** — daily: setlist prediction + pre-show nudge for shows in the window.

### Reliability — virtual dead-letter queue (no deadman)

There is **no external deadman / paging**. Each delivery step is idempotent, so a
failed run self-heals on the next scheduled run. Per-step DLQ columns
(`*_first_failed_at` / `*_alerted_at`) track how long a step has been stuck; only
when a step stays unreconciled for **>24h** does musync send a single **self-notify
email** to the user (a notification, not a page). Success clears the DLQ state.

## Data model

`concerts` is the source of truth. Delivery state (calendar `content_hash` /
SEQUENCE, `setlist_notified_at` / `setlist_found_at`, per-step DLQ timestamps) lives
alongside the show so any run can safely resume. Short-lived predictions
(`probable_setlist`) are cache only — purged once a real setlist is found and after
the show is past (see Setlist.fm retention below). Schema in `db/schema.sql`;
migrations in `db/migrations/` (dbmate).

## Build / test / run / deploy

Tasks run via [`mise`](https://mise.jdx.dev) — address this project with
`mise run //fsharp/api/musync:<task>` from the monorepo root, or bare `mise run
<task>` from `fsharp/api/musync`.

```sh
mise run build            # dotnet build Musync.sln
mise run test             # dotnet test (Expecto — 76 tests, 0 skipped)

mise run up               # docker compose: Postgres + apply migrations, wait healthy
mise run dbmigrate        # dbmate up  (containerized one-shot)
mise run dbrollback       # dbmate down
mise run down             # stop stack
mise run cleandocker      # stop + drop volumes

mise run dockerbuild      # docker compose build images
```

**Deploy** — colocated OpenTofu stack in `terraform/` (prefer `tofu`, not
`terraform`): namespace, `vultr-managed-postgres`, ESO `ExternalSecret` sourced from
the 1Password `Frankenstructure` vault, the two CronJobs, and the CI `deploy-musync`
job. Merging to `main` applies canonically via CI; a musync-scoped `tofu apply` can
run the live e2e out of band.

## External-service assumptions to re-verify

musync depends on several **unofficial / brittle** external surfaces. These are the
standing checklist — re-verify each before trusting or extending the integration,
since none are contractually stable.

### Setlist.fm ([ToS](https://www.setlist.fm/help/terms) · [API ToS](https://www.setlist.fm/help/api-terms))

- **Non-commercial only.** The free API key is non-commercial; **any revenue from a
  musync deployment requires a commercial license.**
- **Attribution required.** Any surfaced setlist data must credit "Source:
  setlist.fm" with a link that is **not** `rel="nofollow"`.
- **Retention = short cache only.** Do not durably store setlist content. musync
  purges `probable_setlist` on setlist-found and once a show is past.
- **Use the API — do not scrape** setlist.fm.
- **Rate limits:** default **2 req/s · 1,440 req/day** (ample for single-tenant);
  upgradable to **16 req/s · 50,000 req/day** on request (multi-tenant only).
- **Matching:** read-only REST; artists are matched by **name + date + venue** (no
  MBID is available from Songkick). Watch the XML→JSON quirk where a single element
  deserializes as an object rather than a one-item array.
- **If musync ever goes multi-tenant:** add a privacy policy and honor the API ToS
  "no competing service" clause.

### Songkick (unofficial — no supported API)

- Songkick has **no supported public API** (commercial-only; Suno-owned since 2025).
- **Attendance ICS feed** (`.../users/<user>/calendars.ics?filter=attendance`,
  public username-based): entries are **date-only** (floating `DATE`, no time) and
  are discriminated as _Going_ by a `DESCRIPTION` beginning **"You're going"** —
  **undocumented, may change without notice.** Re-verify the feed shape and the
  discriminator string.
- **Concert-page JSON-LD scrape** (doors/show times, openers, ticket vendor): brittle
  HTML scraping and a **separate ToS surface** from the feed. Enrichment is
  best-effort and must never block the calendar send. Re-verify the page markup.

### Proton Calendar (no API / no CalDAV)

- Proton exposes **no API and no CalDAV**, so musync delivers invites via
  **ICS-by-email** (`METHOD:REQUEST`, musync-owned `UID` + `SEQUENCE`, organizer =
  the SMTP relay identity, attendee = the user). Re-verify that Proton still ingests
  an emailed invite into the calendar.

### SMTP (Proton relay)

- Outbound mail goes through the Proton SMTP relay. **Vultr blocks port 25** —
  musync must use **587 (STARTTLS)** or **465 (implicit SSL)**. Verify the
  host/port/security triple matches the relay's current config.

### `dockerconfigjson` (image-pull secret — do not delete)

- The `dockerconfigjson` tofu variable is the **sole image-pull path** for the
  frankistry container registry (`var → kubernetes_secret.cr →
imagePullSecrets`, `terraform/cronjobs.tf`). There is no shared cluster pull
  secret. **Removing it → `ImagePullBackOff` on every musync pod.**

## Not in this PR (post-MVP)

YouTube Music playlist sync (ytmusicapi sidecar) and Logseq notes (outbox +
Mac-side drainer), both fed from the shared `ProbableSetlist`; post-show setlist
updates, cancellation handling, and Last.fm scrobble integration.
