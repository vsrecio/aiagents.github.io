# AGENTS.md

This file documents how to maintain the organizers, volunteers, and sponsors content on the Containers Day site. For dev commands, build/deploy details, and general architecture, see `CLAUDE.md`.

After any change below, verify with `make serve` and check both the Spanish page and its `/en/...` counterpart.

## Sessionize sync

Sessions, speakers and the whole agenda are fetched from the Sessionize API at **build time** — nothing about them lives in this repo. Editing the Schedule Builder does not change the published site until a build runs.

**Sessionize has no webhooks.** The API is read-only and pull-based, so polling is the only integration available; anything promising push notifications (see the deleted `webhook-receiver.js` in commit `4616952`) was built against a feature that does not exist.

`.github/workflows/hugo.yaml` polls every 15 minutes. A `check` job hashes the two feeds the site renders — `/view/GridSmart` (agenda) and `/view/all` (speaker pages) — and compares that digest against the payload of the last successful deploy via the Actions cache. Unchanged means no build and no deploy, so the schedule stays cheap.

Expect **15–30 minutes** from edit to live: GitHub's scheduler drifts under load, and Sessionize serves its own ~4 minute cache (`Cache-Control: max-age=240`) on top.

To publish immediately, `make sync`. It dispatches the build, waits for it, and then checks that every session in the feed actually reached the page — a green workflow only means the build ran, not that the schedule you edited is the one on the site. It needs an authenticated `gh`; the equivalent by hand is **Actions tab → Deploy Hugo site to Pages → Run workflow**, or `gh workflow run "Deploy Hugo site to Pages"`. Manual runs and pushes bypass the digest check entirely.
- If the edit was *just* made, clear the Sessionize cache first from the event's Get Code page, otherwise the build may fetch the stale cached payload.

The `SESSIONIZE_ID` env var at the top of the workflow must stay in sync with `params.themes.event.sessionizeId` in `hugo.yaml`.

### Event-day sync

The `*/15 * * * *` poll is a promise GitHub does not keep: scheduled workflows are throttled and dropped under load, and on 22 August 2026 that line fired every **25–56 minutes**. A schedule change made mid-morning sat unpublished for most of an hour while the event was already running.

So there is a second schedule, `*/5 * * * *`, that only does work while the event is on. A cron expression cannot read site config, so it fires year-round and `.github/scripts/event-window.sh` throws away the ticks that land outside the event: it reads `startDate`, `endDate` and `utcOffset` from `params.themes.event` in `hugo.yaml` — the same params the countdowns and the agenda read — and sets the `active` output the rest of the `check` job keys off. **Move the event in `hugo.yaml` and the dense poll window moves with it; there is no date written down twice and nothing to edit in the workflow.** A multi-day `startDate`/`endDate` span covers every day in it.

What is never gated: pushes, manual dispatches and the year-round `*/15` poll always check Sessionize. Only the dense tick can be skipped, and a skipped tick exits in seconds without touching the API. The script also **fails open** — an unreadable or unparseable `hugo.yaml` polls anyway and annotates the run, because a stale agenda during the event is a worse failure than a wasted build.

Twelve attempts an hour instead of four does not defeat GitHub's throttling, it only shortens the expected wait; **it is not a 15 minute guarantee.** Nothing in GitHub Actions can promise one. If the agenda on the site has to match the agenda on the wall within minutes, drive it by hand:

```shell
make sync
```

A manual dispatch bypasses the digest check and deploys unconditionally, so it is always safe to run when nothing has changed, and it takes about a minute. On event day, run it after every Schedule Builder change rather than trusting the poll. If the verification at the end reports sessions missing from the page, the build read Sessionize's ~4 minute cache: clear it on the event's Get Code page and run `make sync` again.

To test the gate without waiting for a schedule, run the script directly — `CONFIG` points it at a doctored copy of the config:

```shell
GITHUB_OUTPUT=/dev/stdout CONFIG=/tmp/hugo.yaml \
  EVENT_NAME=schedule EVENT_SCHEDULE='*/5 * * * *' DENSE_CRON='*/5 * * * *' \
  bash .github/scripts/event-window.sh
```

Editing anything under `.github/workflows/` needs a credential with the `workflow` OAuth scope — a `gh`-issued HTTPS token does not have it, so push over SSH.

## Event dates and times

Every date and time the site counts against lives in `hugo.yaml` under `params.themes.event`. **Do not hardcode a date in a template or in JavaScript** — a past incident left `¡Es Hoy!` frozen in the topbar and the wrong weekday in a tooltip because the date was written into `baseof.html`.

```yaml
startDate: '2026-08-22'   # YYYY-MM-DD
endDate: '2026-08-22'
startTime: '09:00'        # local wall clock, HH:MM
endTime: '23:59'          # when the countdown retires and the thank-you takes over
utcOffset: '-04:00'       # the venue's offset (America/Santo_Domingo)
```

`themes/event/layouts/partials/event-datetime.html` turns those into one RFC 3339 timestamp. Call it instead of writing a date yourself:

```go-html-template
{{ partial "event-datetime.html" (dict "event" .Site.Params.themes.event "which" "start") }}
{{ partial "event-datetime.html" (dict "event" .Site.Params.themes.event "which" "end") }}
```

Two consumers today, both driven off that partial so their clocks can't drift apart:

- **Topbar ticker** (`themes/event/layouts/_default/baseof.html`) — counts down to `start`; once `end` passes it removes `.topbar-countdown` from the DOM entirely.
- **Hero meta band** (`partials/countdown.html`, fed by `partials/sections/hero-slider.html`) — days/hours/minutes/seconds before `start`, `countdown.ended` ("the event has started") between `start` and `end`, then `countdown.thanks` ("thank you / see you next year") after `end`. Both strings are in `i18n/es.yaml` and `i18n/en.yaml`.

Human-readable dates are formatted from the same config: `{{ .Site.Params.themes.event.startDate | time.AsTime | time.Format ":date_full" }}`. Never type the date out in prose in a template — the one remaining hand-written date is in `params.themes.event.description` (SEO copy) and must be updated by hand when the event moves.

To move the event, change `startDate`/`endDate` (and the description) — nothing else. Verify with `make serve`: the topbar should show a live `NNd HHh MMm SSs` ticker and the hero should show four counters agreeing with it.

### Simulating another date

There is no date-override flag. To see the site as it will look during or after the event, temporarily set `startDate`/`endDate` to a past date and reload — `hugo server` picks up `hugo.yaml` changes, but restart it if a rebuild sticks on an error page. **Revert before committing.** For the agenda's "happening now" state, don't touch config: run this in the browser console on `/agenda`, since that logic reads the session times from the page, not from `hugo.yaml`:

```js
for (let i = 1; i < 5000; i++) clearInterval(i);
const now = new Date('2026-08-22T11:00:00-04:00');
document.querySelectorAll('[data-session]').forEach(c => {
  c.classList.toggle('session-card--live', now >= new Date(c.dataset.start) && now < new Date(c.dataset.end));
});
```

## Agenda content (`/agenda`)

The page is `content/sessions/_index.md` (Spanish, `url: /agenda`) and `content/en/sessions/_index.md` (`url: /en/agenda`), rendered by `themes/event/layouts/sessions/list.html`. The `_content.gotmpl` next to them generates one content page per session — **never create or edit those by hand.**

**What comes from Sessionize (not editable here):** session titles, abstracts, speakers, start/end times, room assignments, and the order of the day. Change them in the Sessionize Schedule Builder and wait for the poll (see *Sessionize sync* above) or trigger the workflow manually. Nothing in this repo can override a session's time or room.

**What is editable here:**

- **Page intro, title, description** — the front matter and body of `content/sessions/_index.md` and its `/en/` twin.
- **All UI copy** — `i18n/es.yaml` and `i18n/en.yaml`, keys under `sessions_page.*` (search placeholder, filter legends, `grid_hint`, `no_matches`, `live_now`, `jump_now`) and `session_label.*` (the topic pill labels). A topic with no `session_label.<slug>` key renders as an **empty pill** — `T` returns an empty string for a missing key — so add the key in both files whenever a new topic appears in Sessionize.
- **Floor pills** — `params.themes.event.roomFloors` in `hugo.yaml` maps a room name to a floor and a colour, and `partials/session-floor.html` puts the pill on the card and in the popup. Sessionize names the room but never says where it is, so this is the only place that knows. Only sessions starting at or after `roomFloors.from` (13:00) get one — the morning slot in those rooms is registration, staffed at the door — and a room that isn't listed gets nothing, which is how Salón Principal and Virtual stay bare. The pill sets its own `color` next to its `background`, per the contrast rule below; if you change a colour, keep white text above 4.5:1 on it or set `text` alongside. The floor also joins the card's search haystack, so "piso 5" finds the fifth-floor track.
- **Topic pills** — derived from Sessionize session categories, collapsed behind a `<details>` in `list.html` because there are enough of them to push the schedule below the fold. Room pills stay expanded.
- **Break and ceremony cards** — sessions Sessionize marks as service sessions render as gray "Receso" cards and are hidden as soon as any filter is applied. Whether something counts as a break is decided in `list.html`; see commit `446d35f` for the Opening Remarks case.
- **Live mode (event day only)** — between `startDate` and `endDate` the agenda stops trusting its own HTML. It polls the Sessionize GridSmart feed directly from the browser every 60 seconds (the API sends `Access-Control-Allow-Origin: *`, so no proxy is involved) and compares each session's time, room and title against what the build put on the page. They almost always agree and nothing happens. When they do not, the built grid and the filter bar are hidden and the schedule is re-rendered **from the feed** as a flat chronological list, under an amber "Datos en vivo desde Sessionize" notice. The grid is not rebuilt client-side on purpose: its rows and spans are computed at build time, and a session whose time moved cannot be dropped into a row that no longer matches it — the list trades layout for truth. It is temporary. The next deploy changes the stamp, the poller above reloads, and the grid returns. Live mode also has no session popups and no avatars, since both are build-time resources and a session added mid-event has neither.

  Everything it needs — the feed URL, the event window, the floor colours, the label strings — is rendered into `data-` attributes on the `[data-agenda-live]` section. **Do not hardcode any of it in the script**; that is the same mistake as the frozen date in `baseof.html`.
- **Stale-tab refresh** — GitHub Pages serves the agenda with `cache-control: max-age=600`, and an attendee who opened it in the morning keeps that tab all day, so a schedule change reaches nobody until they reload. Nothing can purge their browser from here, so `list.html` fingerprints the schedule it was built from (session ids, times, rooms — not abstracts, which should not cost a reload) into `/agenda-stamp.json` and embeds the same digest on the page. The page re-checks that file on load, on every return to the tab, and every 60 seconds, with both a cache-busting query and `cache: no-store` so neither the CDN nor the browser can answer it stale. A changed digest reloads a hidden tab silently and shows a "La agenda cambió" bar on a visible one. It follows that **an attendee still sees the old schedule for up to a minute, and only if their tab has network** — it is a safety net, not a broadcast channel. The stamp is 28 bytes, so a minute is cheap; a shorter interval buys little, since a schedule change still has to clear Sessionize's ~4 minute cache and a full build first.
- **Live-session behavior** — `list.html` adds `.session-card--live` plus an "En curso" chip to whatever session is running, shows the "Ahora mismo" jump button, and on load scrolls to the live session (skipped when the URL has a `#hash`, so deep links still win).

After changing agenda copy, check both `/agenda` and `/en/agenda`, and confirm the topic filter still narrows the schedule.

## Contrast rule (applies to every template and stylesheet)

**Light background → dark text. Dark background → light text.** Never leave it to inheritance.

`body` is dark navy (`--bg-dark`) with light text (`rgba(255,255,255,0.8)`), so *any* element that paints a light background must also set its own `color`, or its contents inherit white-on-white. This has already caused two rounds of unreadable text (`.section-container--dimmed`, the agenda `.schedule` section).

Whenever you add a `background`/`background-color`:

- Light surface → set `color: var(--text-dark)` (or `--color-primary-darkest` in legacy theme CSS). Secondary text: `--text-muted` / `#33475b`.
- Dark surface → set `color: var(--text-light)` or white.
- Set the pair **on the container**, not on each child — one declaration covers everything nested inside.
- Watch for `all: unset` in the legacy theme CSS: it resets `color` to `inherit`, so those elements depend entirely on the container being correct.

Target WCAG AA (4.5:1 for body text, 3:1 for large text). The site tokens already satisfy this: `--text-dark #1a2a36` (13.8:1 on white), `--text-muted #64748b` (4.8:1), `--accent #2378b0` (5.0:1). `--accent-light #5dade2` is **only 2.0:1 on white** — decorative use only, never text.

## Organizers

Organizers are **data-driven** — `data/organizers.json` at the repo root, a single list shared by both languages, loaded in templates as `site.Data.organizers`. It's rendered as `.organizer-card` blocks by `themes/event/layouts/miscellaneous/organizers.html` on `/organizers` (and `/en/organizers`).

Each entry:
```json
{
    "id": "<slug>",
    "name": "Full Name",
    "image": "/images/<slug>.jpg",
    "alt": "Optional alt text (defaults to name)",
    "roleKey": "cd_organizer_role_<slug>",
    "hidden": false,
    "socials": [
        { "type": "linkedin", "url": "https://..." }
    ]
}
```
`socials[].type` must be `linkedin` or `instagram` (the only icons/hover styles wired up in the template — see `$socialIcons`/`$socialLabels` in `organizers.html`); add a new type there first if a person uses a different network. `hidden: true` keeps an entry in the list (and its i18n/photo) without rendering it — used to pull someone from the page without deleting their data.

### Add an organizer

1. Add a square headshot to `static/images/<slug>.jpg`.
2. Append an entry to `data/organizers.json` (see shape above), with a new, unique `roleKey`.
3. Add the matching `roleKey` to **both** `i18n/es.yaml` and `i18n/en.yaml` with the Spanish and English role text.

### Remove an organizer

- To hide them but keep their data (reversible): set `"hidden": true` on their entry.
- To fully delete: remove their entry from `data/organizers.json`, delete the `roleKey` from both `i18n/es.yaml` and `i18n/en.yaml`, and delete the now-unused photo from `static/images/` if it isn't reused elsewhere.

## Sponsors

Sponsors **are** pure data — `data/sponsors.json` at the repo root, a single list shared by both languages, loaded in templates as `site.Data.sponsors`. This drives the `/sponsors` page, the homepage sponsor carousel, and the logo strip at the bottom of `/organizers`.

### Add a sponsor

1. Add the logo file to `assets/logos/` (this is processed by Hugo's asset pipeline via `resources.Get` — **not** `static/logos/`, which is for unprocessed static assets).
2. Append an entry to `data/sponsors.json`:
   ```json
   {
       "logo": "logos/<file>.png",
       "url": "https://sponsor-site-or-social-link/",
       "name": "Sponsor Name",
       "description": "One-line description shown with the logo.",
       "tier": "platinum"
   }
   ```
   `tier` is `platinum` | `gold` | `silver` | `community` and must match a key in `params.themes.event.sponsorTiers` (still in `hugo.yaml` — only the sponsor list itself moved to JSON).
3. `community`-tier sponsors show only on `/sponsors` and in the `/organizers` footer strip. `platinum`/`gold`/`silver` sponsors also appear in the homepage carousel (`partials/sections/our-sponsors.html`).

### Remove a sponsor

Delete its entry from `data/sponsors.json`. Optionally delete the now-unused logo from `assets/logos/` if nothing else references it.

### Initiative partners (related, separate list)

`params.themes.event.initiativePartners` is a separate list for non-sponsor program partners (e.g. funding bodies, academic partners). Same add/remove process as sponsors, but entries only have `logo`, `url`, `name`, and an optional `wide: true` for a wider logo — no `tier` or `description`.

## Volunteers

Unlike organizers and sponsors, there is **no roster stored in the repo**. `/volunteers` (`content/volunteers.md` + `content/en/volunteers.md`, layout `volunteers`) just wraps a hero + intro paragraph around an embedded **Google Form**, rendered by `themes/event/layouts/miscellaneous/volunteers.html`.

The site has no backend or database (static Hugo build on GitHub Pages), so the actual form — fields, options, required/optional flags, and any conditional logic — lives entirely on **Google Forms' side**, not in this repo. The embedded iframe just points at `params.themes.event.volunteersFormUrl` (a `forms.gle` link) in `hugo.yaml`, with `?embedded=true` appended in the template to get Google's frameless embed view. Submissions land in the linked Google Form's Responses tab (and its linked Sheet, if one is attached).

### Edit the form

- **Fields, options, conditional logic**: edit directly at the form's edit URL in Google Forms — there is nothing to change in this repo for question content.
- **Swap in a different Google Form** (or point at a new one): update `volunteersFormUrl` in `hugo.yaml` (`params.themes.event`) to the new form's `forms.gle` (or full `docs.google.com/forms/.../viewform`) URL. No template changes needed.
- **Embed height**: Google's embed has no dynamic-height API like Tally did, so the iframe uses a fixed `height="1200"` in `volunteers.html`. If a new form is noticeably longer/shorter, adjust that value so the form doesn't scroll inside its own box.
- **Menu entry**: `hugo.yaml` → `menus.main` (`identifier: volunteers`) in both the `es` and `en` language blocks.
- **Response notifications**: enable "Get email notifications for new responses" in the form's Responses tab (⋮ menu) in Google Forms — not configured in this repo.

### If you'd rather not depend on Google Forms

Swap the iframe's `src` for a different form service, or replace the whole block with a `mailto:`-based custom HTML form (fields built in this repo, no external dependency, but no dashboard/spreadsheet of applicants either) — see the git history of `volunteers.html` for a previous mailto-based version to start from.
