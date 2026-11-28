# Apogee information architecture

Owner: **ux**. Status: rev 1 (2026-11-08). Companion to [`design-language.md`](design-language.md); decisions in [`decisions.md`](decisions.md).
Sources: Journeys + SetupJourneys boards (nav), the existing route inventory
(`apps/cadence_web/lib/cadence_web/router.ex`, `frontend/apps/host/src/routes.json`).

Today Cadence is organized by **data type** (catalog, comms, dashboards, requirements…). Apogee is
organized by **what the operator is trying to do**, in two modes:

| Mode | Who, how often | Character |
| --- | --- | --- |
| **Ops** | Operators and shift leads, every shift | Console: fits the viewport, live, the clock is in frame. Fleet-first. |
| **Setup** | Mission engineers and admins, weekly or monthly | Reading/editing pages that scroll. Every change is **staged → diffed → applied as a revision** (`r6`). Includes the Organization group. |

A top-bar **OPS │ SETUP** switch moves between them and keeps the mission. Mobile (J6) is a
reduced Ops for on-call triage only.

---

## 1. Route map

The SPA is served by Phoenix at `/console/*` (catch-all returns the SPA index). Routes carry the
org and mission (decision U1): `O = /console/:orgId`, `M = O/:missionId` (e.g.
`mission-earendil-demo`). `/console` redirects to the user's last mission's Now (or
`O/org/missions` if they have none). Lead owns the router; if it differs, the router wins.

### Ops (rail: numbered 01–07)
| # | Rail item | Route | Board | Notes |
| --- | --- | --- | --- | --- |
| 01 | **Now** | `M/now` | Now (J1) | Landing for Ops. Stat strip, constellation, action queue, fleet matrix, next-2h passes. |
| 02 | **Fleet** | `M/fleet` | – (derive from Now matrix + table) | All spacecraft; filter by plane, profile, state; matrix ⇄ table. Count = fleet size. |
| | spacecraft | `M/fleet/:scId` → tabs `investigate` (default when alarmed) · `telemetry` · `uplink` · `passes` · `configuration` · `history` | Investigate (J2) | Breadcrumb `FLEET / PLANE 07 / EARENDIL-312`; `[` `]` prev/next in plane. Tab is a path segment: `M/fleet/:scId/telemetry`. |
| 03 | **Alarms** | `M/alarms` | – (list) | Active alarms ranked; count in crit tint. `M/alarms/:alarmId` redirects to `M/fleet/:scId/investigate?alarm=:alarmId`. Shows the `off` state when Limits & Alarming isn't installed. |
| 04 | **Commands** | `M/commands` | CommandFlow | Requests grouped by state (draft → verified + off-ramps); count = open requests. |
| | compose | `M/commands/new` (`?targets=<query>&procedure=<id>` prefill) | Compose (C1), Command (J3) | "Command a group" from an alarm opens this prefilled. |
| | request | `M/commands/:requestId` | Approve / Uplink | One URL per request; the view follows its state: **review** (awaiting a second GO, `…/review`), **uplink & verify** (queued → verified, live, `…/uplink`). |
| 05 | **Contacts** | `M/contacts` (Live) | Contacts (J4) | Ground track + 6h fleet Gantt. Rail count = `7 AOS` (in contact now). Sub-tabs below. |
| | plan | `M/contacts/plan?day=2026-11-09` | PassPrediction (K0), SchedulePlan (K1) | Demand list → draft → reserve. Prediction is the "Opportunities" step inside Plan, not a separate destination. |
| | replan | `M/contacts/replan/:stationId` | Replan (K2) | Entered from a station outage (action queue, station row, ⌘K). |
| | review | `M/contacts/review?day=…` | PassReview (K3) | Planned vs flown; reading view, scrolls. |
| | contact | `M/contacts/:contactId` | – | One contact with its state trail; drawer over the Gantt, deep-linkable. |
| 06 | **Telemetry** | `M/telemetry` (Explore) | – | Point search + plots with the ApTimePicker range. Explore · Dashboards tabs; dashboards are rebuilt in the console (L8, screens/Dashboards.md). |
| 07 | **Timeline** | `M/timeline` | – | Fleet-wide event log (ApEventLine), filter by spacecraft/plane/kind, time-picker range. |
| ·· | Setup | → `M/setup` | | Cross-mode link at the rail foot. |
| ·· | Organization | → `O/org/people` | | |

### Setup (rail: Mission 01–09, Organization)
| # | Item | Route | Board |
| --- | --- | --- | --- |
| 01 | **Readiness** | `M/setup` | Setup (S1) |
| 02 | **Spacecraft** | `M/setup/spacecraft` · add `M/setup/spacecraft/new` · one `M/setup/spacecraft/:scId` | AddSpacecraft (S2) |
| 03 | **Profiles** | `M/setup/profiles` · `M/setup/profiles/:profileId[/:section]` | Profile (S4) |
| 04 | **Catalog** | `M/setup/catalog` · import `M/setup/catalog/import[/:importId]` · `M/setup/catalog/:databaseId` | Catalog (S3) |
| 05 | **Comms & routing** | tabs: `M/setup/comms` (routing rules) · `M/setup/comms/transports[/:id]` | – |
| 06 | **Ground stations** | tabs: `M/setup/stations[/:id]` · `M/setup/stations/providers[/:id]` (decision U4) | – |
| 07 | **Contact planning** (DECISIONS #27) | `M/setup/contact-planning[/policy]` · `…/templates/:id` | – (`screens/ContactPlanning.md`) |
| 08 | **Data sources** | `M/setup/data-sources[/:id]` · `M/setup/data-sources/operations` | – |
| 09 | **Apps** | `M/setup/apps[/:appKey]` | – |
| (phase 3) | **Monitoring** (U108, #28) | `M/setup/monitoring` · tabs `limits` · `derived` · `alarm-rules` | – |
| 10 | **Mission settings** **[decision]** | `M/setup/settings[/:section]` | – |
| | staged changes | `M/setup/changes` (review & apply) · `M/setup/revisions[/:rev]` (history, compare, roll back). Target design: `screens/Changes.md` (DECISIONS #1); hidden in v1 (U2). | Setup R2 + staged bar |
| Org | **People & access** | `O/org/people` · `O/org/people/invite` · service identities `O/org/people/services` | People (S5) |
| Org | **Missions** | `O/org/missions` · `New mission` links to the existing mission-create page (DECISIONS #64; no console route for now) | – |
| Org | **Provider accounts** **[decision]** | `O/org/provider-accounts[/:id]` | – |
| Org | **Settings** | `O/org/settings[/:section]` | – |
| Org | **Audit log** | `O/org/audit` | – |

### Account and outside the SPA
| Route | What |
| --- | --- |
| `/console/account` | Your profile, password, sessions (fixes review #18). From the account menu. |
| ~~`/console/notifications`~~ | **Dropped (DECISIONS #64).** Now's attention queue (#54, U31) is the console's notification surface. |
| `/sign-in`, `/invitations/:token`, `/no-organization`, `/admin-mode` | **SPA auth screens** (L5/L6, screens/Auth.md; auth layout, admin mode as a step-up dialog). The SPA redirects to `/sign-in?return_to=…` on 401. |
| `/admin/**` (platform admin) | **Becomes a console admin area** (L7, DECISIONS #75; screens/Admin.md at `/console/admin/**`). Account menu shows `Enter admin mode` / `Admin area` only with the `platform_admin` capability. |

Rules: every screen state worth sharing is in the URL (tab, filters, selected spacecraft, time
range as `from`/`to` ISO or a preset key such as `range=orb6`). Back always works. Mission switch
keeps the current section when the target mission has it, else goes to Now / Readiness.

---

## 2. Navigation

**Top bar** (both modes, design-language §7 ApTopBar): brand → org/mission switcher → OPS│SETUP →
query (⌘K) → fleet posture → clocks → account.

- **Mission switcher** opens a searchable list of the org's missions (name, fleet size, worst state).
  Never a truncated list ("7 of 500" was review #10). Org switching lives in the account menu.
- **Clocks.** Ops: next AOS across the fleet (`AOS T−00:04:12 118·SVB`, links to that contact),
  `UTC`, `MET` (only when the mission defines an epoch; otherwise omitted, not faked: U7). Setup:
  `CONFIG r5` (links to revisions; `r5 → r6 draft` while changes are staged) **only with a mission
  change set (U2)**; otherwise `UTC` alone.
- **Fleet posture** (both modes, at mission scope; replaces the legacy context rail, §11c(C), ux 11-15). It sits in
  the `topbar-status` slot, left of Setup's `CONFIG rN`. It's dashboards' cockpit cluster, without its clock: the
  clocks above already carry UTC.
  - Chips with mark, count and word, only for non-zero states, worst first: `◆ 2 crit · ▲ 1 caution · ▨ 3 stale`
    (▨ = the kit's stale mark, the hatched square; ◆ is only ever crit). Crit and caution link to Alarms (Active);
    stale links to Fleet `?state=stale`.
  - Nothing to report: `■ Fleet nominal` (→ Now). Never nominal while any spacecraft is stale or not heard yet.
  - **Not heard yet** (`never_heard`; U9: `off`, "awaiting first AOS"): a last chip with the off mark, `○ 6 not heard
    yet` → Fleet `?state=never_heard`. It's not a problem state, so it ranks after stale, but it stops the nominal
    claim (U20). When every spacecraft is never heard: `○ No telemetry yet`, the Missions list's words.
  - **Telemetry `degraded`** (the history store didn't answer, so Cadence can't tell stale from never heard): the
    stale and not-heard chips merge into one stale-marked chip, `▨ 9 not heard recently` → Fleet
    `?state=stale,never_heard`. Its title and accessible name say why: "Cadence couldn't read telemetry history,
    so it can't tell which of these were heard before the restart." Crit and caution are unaffected.
  - Ground limits not installed: the crit and caution chips are replaced by `○ Ground limits off` (→ Setup › Apps).
    Stale still counts. Never a clean nominal in that state, as with Alarms.
  - Not loaded yet: nothing, never a placeholder nominal (U20).
  - Live link lost: the chips keep their counts but turn stale-tinted, with `as of 23:52Z`.
  - From 768 to 1599px (dashboards and qa, 11-15: the worded cluster is ~450px): marks and counts only (`◆ 2 ▲ 1
    ▨ 3`). Each link's accessible name and title carries the words ("2 spacecraft critical"). Chips without a
    count keep a short word: `○ Limits off`, `○ No telemetry yet`, `■ Nominal`. Words from 1600px.
    Below 768: not in the header; the tab bar's Alarms count and Now cover it.
  - **The top bar never wraps** (qa, 11-15). Every item is one line and `flex-none`, except the query trigger,
    which is the only one that shrinks: its placeholder truncates with an ellipsis, with a minimum of about 160px.
    If the bar still doesn't fit at that minimum, the posture goes compact before anything else gives way, at any
    width.
  - **When even that doesn't fit** (qa 11-15: Setup is 1358px wide at 1100–1280, so UTC and the account are
    clipped): things give way in this order, each step only while the bar still overflows.
    1. The brand drops its wordmark and keeps the mark (still the home link, named "Cadence").
    2. The scope crumb drops the org name and keeps `EARENDIL ⌄`. The org stays in the switcher list and in the
       crumb's accessible name ("Reflect Orbital / Earendil").
    3. The query becomes an icon button (`⌕ ⌘K`, named "Search"). It opens the same palette.
    4. The clock cluster drops next AOS and MET, and keeps `UTC`.
    5. Last resort (dashboards): the bar wraps to a second row. A wrap is better than a clip.
  - **Never give way:** the mode switch, the posture's marks and counts, Setup's `CONFIG rN`, `UTC` and the account
    menu. Nothing is ever clipped or pushed off-screen: the account menu is always reachable. The posture never hides
    and never shrinks to one worst mark: it's the director's condition for dropping the context rail, and counts are
    what the rail gave.
  - Count changes aren't announced; a new crit flashes the chip once (reduced motion: no flash).
- **Account menu**: name + role, Your account, Switch organization, Platform
  admin (capability-gated; the console admin area, L7), Sign out.

**Rail.** Ops 200px numbered 01–07 with live counts (Fleet size, Alarms open in crit tint,
Commands open, Contacts `n AOS`). Setup 220px with Mission / Organization groups and counts
(spacecraft, profiles, catalog version, stations, sources). Counts come from one bootstrap/summary
endpoint and update live in Ops; a count we can't compute is omitted, never zero.

**Staged changes bar** (Setup, every page): visible whenever the mission has staged, unapplied
changes; Discard / `Review & apply as rN` → `M/setup/changes`. Hidden entirely until a mission
change set exists (U2).

**Keyboard** (shown in ⌘K footer and an `?` overlay):
`⌘K` / `/` query · `G N` Now · `G F` Fleet · `G A` Alarms · `G U` Commands (uplink) · `G C` Contacts ·
`G T` Telemetry · `G L` Timeline · `G S` Setup · `[` `]` previous/next spacecraft (in a spacecraft
context) · `Esc` close overlay. Shortcuts never fire while typing in an input.

**⌘K palette** (J5): one query over spacecraft (name, SCID, plane), telemetry points, commands,
stations, profiles, pages. Results are **actions**: open, plot, "Command EARENDIL-312…" (`⌘↵`),
"Passes for 312". Scoped to the current mission; Setup mode ranks setup objects first.

---

## 3. Mapping today's pages into the new IA

`M` below = `/missions/:mission_id` in the **current** app.

| Today | Goes to | Note |
| --- | --- | --- |
| `/` org home | `/console` → last mission Now; `O/org/missions` | Org home dissolves. |
| `/missions`, `/missions/new` | Org › Missions | |
| `M` mission overview | Ops › Now and Setup › Readiness | Overview splits by mode. |
| `M/spacecraft`, `/new` | Setup › Spacecraft, Add spacecraft (batch) | 1 or 50, same flow. |
| `M/spacecraft/profiles/**` | Setup › Profiles | "Spacecraft Profile" = Spacecraft Type. |
| `S` config hub, `S/identity`, `S/edit`, `S/routing`, `S/commanding` | Setup › Spacecraft › one (identity) + Profile sections; overrides listed on the profile and on Ops › spacecraft › Configuration | Per-spacecraft config becomes the exception (overrides). |
| `S/readiness` | Setup › Readiness findings (grouped by cause) | No per-spacecraft checklist. |
| `S/applications`, `S/applications/:key` (telemetry_decom manage, packet bindings) | Setup › Profiles › section, or Apps › app; deep link out to existing host surface in phase 1 | |
| `M/catalog/**` (databases, revisions, artifacts, imports, upload) | Setup › Catalog (+ import diff) | Artifacts/revisions as tabs on a database. |
| `M/comms` overview | Setup › Readiness "Comms & routing" area | |
| `M/comms/transports/**` | Setup › Comms & routing › Transports | |
| `M/comms/routing/**` | Setup › Comms & routing (rules) | Routes are generated from rules. |
| `M/comms/ground-stations/**` | Setup › Ground stations; station health also on Ops › Contacts Gantt rows | |
| `M/comms/providers/**` | Setup › Ground stations › Providers tab | |
| `M/comms/validation` | Setup › Readiness findings | |
| `/provider-accounts/**` | Org › Provider accounts | Not on the canvas; org-level credentials. |
| `M/ops` landing | Ops › Now | |
| `M/ops/alarms` | Ops › Alarms | |
| `M/ops/timeline` | Ops › Timeline | |
| `M/ops/explore` | Ops › Telemetry (Explore) | |
| `M/ops/dashboards/**` (directory, view, edit, settings, library, playlists, present, shares, snapshots, activity, diagnostics, export) | Ops › Telemetry › Dashboards | See §4: not on the canvas. |
| `M/ops/data-sources/**` | Setup › Data sources | Freshness also on Readiness "Data sources". |
| `M/ops/data-operations/**` | none | Deleted with its backend (#702, decision on #144); no console screen. |
| `M/ops/commands`, `/workspace`, `/new`, `/stages/**` | Ops › Commands, Compose | Stages become the Draft → Staged states of one request. |
| `M/ops/commands/requests/:id`, `/queue`, `/history` | Ops › Commands › request (review / uplink & verify / history) | One URL per request; view follows state. |
| `M/ops/activations` (binding-set activation approvals) | Setup › Changes (approval of an apply) + an action-queue item on Now ("awaits your GO") | Not on the canvas; same two-person rule as commands. |
| `M/ops/planning/**` (runs, new, policy) | Ops › Contacts › Plan | A planning run = a plan draft/revision. Policy → Profile "contact demand" section + Plan settings. |
| `M/ops/requirements/**`, `/requirement-templates` | Ops › Contacts › Plan › Demand list; templates → Profile demand rules | Fixes #08 (requirements are scheduler input). |
| `M/ops/plans/:id` | Ops › Contacts › Plan (reserve step) | |
| `M/ops/contacts/**`, `M/ops/contact-workspace/**` | Ops › Contacts (live), contact drawer | Four separate lists become one contact with one state model. |
| `M/settings/**` | Setup › Mission settings | |
| `/settings/**` | Org › Settings | |
| `M/applications`, `M/applications/:key/:surface` | Setup › Apps (install, disable, uninstall) | The console hosts no app surfaces (#672). |
| `/notifications` | stays on the existing page (DECISIONS #64: no console route) | |
| `/admin/**`, `/admin-mode` | Unchanged (existing host) | Linked from the account menu. |
| Service identities (today in platform admin org detail) | Org › People & access › Service identities | Per S5 step 03. |

---

## 4. Features with no home on the canvas (proposals)

| Feature | Proposal | Needs decision? |
| --- | --- | --- |
| **Dashboards** (authoring, playlists, sharing, snapshots, diagnostics) | **Rebuilt in the console now** (user, L8): Ops › Telemetry › Dashboards, viewer as a takeover (screens/Dashboards.md). | Decided: DECISIONS #11 |
| **Telemetry explore** | Ops › Telemetry, built on ApTimeSeries + ApTimePicker range. | No |
| **Data operations** (backfill/replay) | Setup › Data sources › Operations tab. | No |
| **Activation approvals** | Setup › Changes as approvals; Now action-queue item when it awaits *your* GO. | No |
| **Provider accounts** (org) | Org › Provider accounts. | No |
| **Mission settings** (governance etc.) | Setup › 09 Mission settings. | No |
| **Notifications** | Dropped (#64): the Now attention queue is the console's notification surface. | No |
| **Federated app surfaces** | Removed (#672): Setup › Apps lists apps with their verbs; the console mounts no app surfaces. | No |
| **Mission creation** | Org › Missions › New. Not on the canvas; build as a reading-layout form. | No |
| **Platform admin** | Stays on the existing host, linked from the account menu for `platform_admin`. | Decided: DECISIONS #12 |
| **Fleet, Alarms list, Telemetry, Timeline, Spacecraft tabs other than Investigate** | In the canvas nav but not drawn. ux writes screen specs composed from existing components (stat strip, matrix, table, event line, time series) before they're built. | No |

---

## 5. Layout per screen (console vs reading)

Console (fits viewport, panes scroll): Now, Fleet, Alarms, spacecraft (all tabs), Commands, Compose,
Approve/review, Uplink, Contacts live, Plan, Replan, Telemetry, Timeline.
Reading (page scrolls): Readiness, Spacecraft list/add, Profiles, Catalog, Comms, Stations, Data
sources, Apps, Settings, Changes/Revisions, all Org pages, Pass review, Account.
