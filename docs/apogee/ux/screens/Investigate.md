# Investigate (J2 · respond to an alarm)

Route `M/fleet/:scId/investigate[?alarm=:alarmId]` (default tab when the spacecraft has an active
alarm; otherwise the spacecraft opens on `telemetry`) · Ops rail 02 Fleet active · **console layout**
· Board `Investigate.dc.html`. Owner: fe-ops. Data and gaps: `docs/apogee/plans/ops.md` §J2.

**Question:** "What's wrong with 312, is it spreading, what do I do?" **Target: 3 moves**: see the
trend against limits → see the sisters with the same signature → prepare the procedure (→ Compose /
Command a group, prefilled).

## Layout
```
breadcrumb FLEET / PLANE 07 / EARENDIL-312                     [ 311   313 ]
EARENDIL-312  [◆ CRITICAL · POWER]                 Acknowledge  Assign  Command
fact strip: SCID │ Profile │ Orbit │ Last LOS │ Next AOS (white bar) │ Next eclipse
tabs: Investigate · Telemetry · Uplink · Passes · Configuration · History
┌ B1 alarm trend (flex none) ────────────────┐ ┌ aside 380px ───────────────┐
│                                            │ │ B3 Recommended procedure   │
├ B2 Event log (flex 1, scrolls) ────────────┤ │ B4 Plane 07 · same sig.    │
│                                            │ │   (flex 1, scrolls)        │
└────────────────────────────────────────────┘ │ Technical details <details>│
                                               └────────────────────────────┘
```
Main `padding 12px 20px 14px`, gap 10. The spacecraft header (breadcrumb → tabs) is shared by all
spacecraft tabs; only the area below the tabs changes.

## Shared spacecraft header (all tabs)
- **Breadcrumb**: `FLEET` → `M/fleet`, `PLANE 07` → `M/fleet?plane=7` (omitted without plane
  metadata), current name. Prev/next buttons step through the plane by slot (else by SCID), with
  `aria-label="Previous spacecraft, EARENDIL-311"`; keys `[` `]`. They keep the current tab.
- **Title**: entity title (name) + the hero status tag: worst active state + subsystem
  (`◆ CRITICAL · POWER`, with crit wash). No alarm: state word only (`■ NOMINAL`, hatched `STALE ·
  LAST TLM 47m`, dashed `AWAITING FIRST AOS`).
- **Actions**: `Acknowledge`, `Assign` (minimal alarm lifecycle, DECISIONS #6; hidden until its
  endpoints ship, U10). Acknowledge = compact secondary, records who/when, tag gains `· ACK MIRA K.`;
  Assign opens a popover: operator picker (on-shift first) + hand-off note (required on hand-off).
  Auto-clear when back in limits shows a nominal callout in B1.
  `Command` (secondary) → `M/commands/new?targets=sc:<id>`.
- **Fact strip** (ApFactStrip): SCID (mono) · Profile (link to Setup profile, name + version) ·
  Orbit (`P07 · slot 12 · #4,812` = plane, slot, orbit number; parts omitted if unknown) · Last LOS
  (`T+00:06:41 FBK`) · **Next AOS** (white top bar, readout: `T−00:38:10 FBK`) · Next eclipse
  (`T−00:59:30`). Unknown facts are omitted (U10); the strip reflows to the facts it has.
- **Tabs** (ApSegmented `tabs`, `role="tablist"`, path segment per tab). All tabs are
  specified below; until built they render an
  ApEmptyState "Not built yet in the new console" + link to the existing page. **[temporary]**

## B1 · Alarm trend (panel, alert-crit variant: index colored, panel neutral)
Header: index `B1`, title `<POINT SHORT NAME> · <point description> <condition>` (e.g. `VBAT ·
battery voltage below limit`), meta `FIRST CROSSED 2026-10-23 02:08:11Z · UMBRA` (eclipse state
at crossing, only if known), preceded by the source tag (U16): `LIVE`, or `GROUND LIMITS · EVALUATED
T+3m` (then the Now readout is labeled `AT EVALUATION`, not `NOW`).
- **Readouts** tile row: `Now` (value + unit, crit/caution tint + left inset bar when out of limits),
  `Red limit`, `Rate` (per orbit when orbit period is known, else per hour), plus up to one
  correlated point when the backend supplies one (e.g. `Solar array −18 %`).
- **Chart** (ApTimeSeries): primary point white; added points `text-4` (max 3, chips with remove);
  dashed limit lines from the limit intervals (they can change over the window); crit wash below the
  red limit; umbra bands only when eclipse data exists; now-line. Range `micro` segmented
  `1H · 6 ORB · 24H` (`6 ORB` default; falls back to `6H` without orbit period). Add-point chip
  with a search input over this spacecraft's points (same search as ⌘K Telemetry).
- Legend line + one **finding sentence** in stale-text when the backend provides a correlation;
  otherwise no sentence (never generated client-side).
- `aria-label`: "Battery voltage over 6 orbits, falling from 26.8 to 23.4 V and crossing the 24 V red
  limit in the last orbit" (built from first/last/min values and limit crossings).
- **Data:** alarm `{id, state, severity, point: {id, name, short_name, description, unit},
  condition, first_crossed_at, value_now, limits: {red_low, red_high, yellow_low, yellow_high}}`;
  history decimated for the range `[{t, v}]`; limit intervals `[{from, to, red_low…}]`; optional
  `eclipses [{from, to}]`, `orbit_period_s`, `correlated: {point, delta_pct, sentence}`.
- **No active alarm** (`?alarm` absent/resolved): B1 shows the most recently resolved alarm with a
  `nominal` callout "Resolved at 02:31:07Z · back in limits", or, if none, the tab isn't the default.

## B2 · Event log (ApEventLine, scrolls)
Header meta link `FULL TIMELINE →` (`M/timeline?sc=<id>`). Newest first, limit crossings, contacts
(AOS with duration and volume), commands (released / verified / failed), plan events. Mark by kind:
crit/caution for limit events, `live` white square for AOS, `neutral` for plan/operator events.
- **Data:** `[{at, kind, severity?, text, link?}]` for this spacecraft, last 24 h, paged.
- **Empty:** "No events in the last 24 h."

## B3 · Recommended procedure (emphasized panel)
**Deferred (DECISIONS #5): omit this panel.** Spec kept for later. When present: procedure name (display 24px), one-sentence
plan including the timing consequence ("Uplinks at the Fairbanks AOS in 38 minutes, 21 minutes before
the next eclipse"), command preview (mono, numbered lines, well background), primary
`Prepare · 312 + 3 sisters` (→ Compose with targets + procedure) and secondary `Prepare · 312 only`.
The sister count comes from B4; if B4 is empty only the single-target button shows (as primary).

## B4 · Plane NN · same signature (pane, scrolls)
Header meta `3 OF 49`. Mini plane-ring SVG (selected spacecraft crit + labelled, sisters in their
state) then rows: mark, name link (display 15px), mono `24.6 V · AOS T−52m SVB`, 80×24 sparkline in
the row's state color (`aria-hidden`).
- v1 rule (ops plan): same plane + same point currently caution or critical. Header title stays
  "same signature" only if the backend computes similarity; otherwise title `Plane 07 · same point
  in limits` **[decision]** so we don't claim analysis we didn't do.
- **Data:** `[{sc: {id, name, scid}, state, value_now, unit, next_aos?, spark: [v…]}]`, plane size.
- **Empty:** `nominal` callout "No other spacecraft in plane 07 show this." **No plane metadata:**
  hide B4; B3 (if present) shows the single-target button only.

## Tab · Telemetry (`M/fleet/:scId/telemetry[?points=a,b,c&range=6h]`) (fe-ops' layout, worded)
**Question:** "What is every value on this spacecraft doing now, and how has one been trending?" Console
layout. T1 scrolls. Reads only M23, M10, M11 and M8.
```
┌ T1 Points (360, pane, scrolls) ┐ ┌ T2 Plot · up to 3 points (ApTimePicker, default 6 h) ──────┐
│ search · filter chips           │ ├ T3 Values · focused point (last 20 samples, scrolls) ──────┤
└─────────────────────────────────┘ └──────────────────────────────────────────────────────────────┘
```
- **T1 Points:**
  - Search (label, key).
  - Chips: `Out of limits N` · `Stale N` · `All`. The default is All, sorted with out-of-limits first, then by
    subsystem.
  - Row: state mark (crit / caution / stale hatch / nominal; dashed `off` with `No limits`), label (600) with
    (api's `has_limits`, 11-15: `has_limits: false` reads `No limits`, titled "No limits are defined for this
    point."; `has_limits: true` with `limit_state: no_data` reads `Not checked yet`, titled "Limits are defined,
    but no sample has been checked yet.", also dashed `off`; neither is ever the nominal mark or counted in
    `Out of limits`)
    the mono key under it, latest value + unit (U24 units, readout when live), age `T+2s` (stale per the
    server, U9).
  - A checkbox pins up to 3 points to T2. A 4th is disabled with the reason "Plot up to 3 points".
- **T2 Plot:**
  - One point: limit bands from M11, as on B1.
  - 2–3 points: **stacked small multiples sharing the time axis**, one per point with its own unit and bands.
    Never two y-axes on one plot.
  - Pass spans as faint AOS–LOS bands with station codes, and the live tail from M8.
  - Hover shows a crosshair readout of every plotted value at that time.
  - Links: `Open in Explore` (same points and range), `Dashboards` (in the console:
    Telemetry › Dashboards, L8).
- **T3 Values:** the focused point's samples in the range (time to the second, value + unit, limit state),
  newest first, plus `Export CSV`. Clicking a plot focuses it.
- **Empty and errors:**
  - No points: "EARENDIL-001 has no telemetry points yet (its profile defines none)."
  - No data in range: "No samples between 11-12 02:00Z and 08:00Z.", with the plot axis kept.
- **Mobile:** T1 only. A point opens its own plot view (1 point).

## Tab · Uplink (`M/fleet/:scId/uplink`) (api-ops' draft, worded)
**Question:** "Can I command this spacecraft now, and what's going up?" Console layout, no page scroll at
1440×900. U3 and U4 scroll. The header meta carries the route: `ROUTE · CCSDS TC · RULE "BLOCK 1 · ALL STATIONS"`
(details in Technical details).
```
┌ U1 Now (strip): live or next commandable pass · readiness · Recover ───────────────────────┐
┌ U2 Next commandable passes (3) ┐ ┌ U3 Queued on its lane (scrolls) ──────────────────────┐
└────────────────────────────────┘ └───────────────────────────────────────────────────────┘
┌ U4 Released · last 24 h (scrolls) ──────────────────────────────────────────────────────┐
```
- **U1 Now:** one row.
  - In contact: `IN CONTACT · KIR · LOS T−00:06:12`, then readiness in U33 words (`UPLINK READY`, or
    `CAN'T COMMAND: <reason>` with `Recover uplink` when it can help).
  - Not in contact: `NEXT COMMANDABLE PASS · KIR 02:31Z · T−01:12:00`, readiness if already known.
  - No commandable pass booked: caution "No pass with uplink is booked for EARENDIL-001.", with the link
    `Open Contacts`.
  - Primary `Command EARENDIL-001` → Compose prefilled (desktop only; hidden under 768).
- **U2 Next commandable passes (3):** station code · provider · AOS (§4 short) + `T−` · duration · uplink
  evidence (`Booked`, or `Attested · uplink unconfirmed` in caution, per U32/#46). A pass without a command
  window isn't listed. Fewer than 3 → "Only 1 commandable pass is booked in the next 24 h."
- **U3 Queued on its lane** (release order):
  - Position (mono `01`), command mnemonic + args summary, and its group (link → request).
  - Release rule (`At next AOS` / `Not before 03:00Z`), expiry (`expires 04:00Z` when `not_after` is set),
    and the pass it's waiting for.
  - When that pass is blocked, the U33 group line. Empty: "Nothing is queued for EARENDIL-001."
- **U4 Released · last 24 h:** time (§4) · command · group link · delivery and verification in CommandFlow C3's
  state words (`Sent`, `Acknowledged`, `■ VERIFIED`, `◆ VERIFY FAILED`, hatched `UNVERIFIABLE · NO TLM`,
  `No verifier`). Newest first. Empty: "Nothing was released to EARENDIL-001 in the last 24 h."
- **Mobile:** U1 and U3, read-only. No Compose.
- Words come from U33 (readiness), CommandFlow (delivery states) and U32 (attested). No new state words.

## Tab · Passes (`M/fleet/:scId/passes`)
**Question:** "When is this spacecraft heard, and how did its recent passes go?" Console layout, no page scroll
at 1440×900. P3 and P4 scroll. No money (U34).
```
┌ P1 Coverage (strip) ────────────────────────────────────────────────────────────────────┐
┌ P2 Passes · −24 h … +24 h (ApGantt, one lane, now-line) ────────────────────────────────┐
┌ P3 Upcoming (scrolls) ───────────────┐ ┌ P4 Recent · 7 days (scrolls) ───────────────────┐
```
- **P1 Coverage:**
  - Last contact (`LOS T+00:06:41 FBK`) and next contact (`AOS T−00:38:10 KIR`).
  - Passes in the next 24 h (`9 passes`).
  - Longest gap in the next 24 h (`5h 40m`, caution when no pass is booked in the next 6 h, per U35).
  - Today against the contact rule (`3 of 3 contacts today · rule met`, or `2 of 3` caution). `—` with a
    reason when no rule covers it (`no contact rule`, link → Contact planning).
- **P2:** the Contacts Gantt for this spacecraft only, with the same bar grammar (done, missed, conflict,
  unconfirmed hatched, now-line). Click a bar → the contact drawer (`M/contacts/:contactId`).
- **P3 Upcoming:**
  - Columns: station code · provider · AOS (§4 short) + `T−` · duration · `Up/down` or `Down only` · the state
    word (`Requesting` / `Requested` / `Booked` / `Unconfirmed` / `Canceling`, per lead's contactStateWord).
  - A U33 tag only when the uplink isn't ready, and the queued command groups count when > 0 (`2 queued`).
  - Row → the contact drawer. Empty: "No passes booked for EARENDIL-001 in the next 24 h." + `Open Contacts`.
- **P4 Recent · 7 days:**
  - Columns: station · planned AOS–LOS · actual AOS–LOS · outcome (`Realized` / `Partial` / `Missed` /
    `Ended · not verified`) · cause and owner in words · received bytes.
  - Newest first. Each day header links to Pass review (K3) for that day.
  - Empty: "No passes in the last 7 days."
- **Actions:** none here (Release lives in the contact drawer). Links: `Open in Contacts`, and `Plan <day>` → K1.
- **Mobile:** P1 + P3.

## Tab · Configuration (`M/fleet/:scId/configuration`)
**Question:** "What is this spacecraft running, and what changed?" It's **read-only** in Ops. Editing lives in
Setup › Spacecraft (U6), linked as `Edit in Setup` (org admins).
- **G1 Running:**
  - Profile + pinned version (`Earendil Block 1 — Demo · v6`, link).
  - Catalog revision **running** vs the profile's (`rev 15`; when they differ, caution "Running rev 14; the
    profile is on rev 15. See Readiness.").
  - Identity (name, SCID, NORAD id or `not set`), and plane · slot when known.
- **G2 Differs from its profile:** this spacecraft's overrides only, as field label · profile value (text-4)
  → this spacecraft's value. Units per U24. Empty: "Uses its profile as is."
- **G3 Routing:** transports and routing rules that apply (station or provider · role · rule name), the same
  words as Setup › Ground stations.
- **G4 Pending:** staged or in-review change sets that touch it ("r9 · in review · changes TM frame length"),
  linking to Changes. Hidden when there are none.
- **G5 Recent revisions** (last 5 applied): `r8 · 11-09 10:52Z · Mira K. · Changed spacecraft profile …`, in the
  same sentences as the Changes revision list (rollback review). Link `All revisions` → Changes.
- Archived spacecraft: a stale callout "Archived 11-10 by Mira K. It isn't commanded or planned." with the
  rest read-only as usual.
- **Mobile:** G1 + G5.

## Tab · History (`M/fleet/:scId/history[?episode=:id]`) (fe-ops' proposal, refined)
**Question:** "Has this happened before, and how did it end?" v1 covers this spacecraft's **alarm episodes**.
Everything else that happened to it (commands, config revisions, passes) is in Timeline: the link
`Everything on EARENDIL-001 → Timeline` opens Timeline filtered to this spacecraft.
```
counts strip: ALARM EPISODES · 7 DAYS 3 · 30 DAYS 11 · 90 DAYS 24
┌ H1 Episodes (360, pane, scrolls) ┐ ┌ H2 Selected episode (chart) ─────────────────────────────┐
│ newest first                     │ ├ H3 Prior occurrences of this alarm (table, scrolls) ──────┤
└──────────────────────────────────┘ └───────────────────────────────────────────────────────────┘
```
- **Counts strip:** episodes (not alarms, U23) per window. Show `—` with a reason if a window is longer than
  retention ("kept for 30 days").
- **H1 rows:**
  - Status mark (crit diamond / caution triangle, U16 source tag `CATALOG` / `GROUND LIMITS`).
  - Point and condition in words ("VBAT below red low").
  - Opened (§4 short form) and duration (`2h 14m`, or `OPEN · T+00:42:10` in readout while active).
  - `ACK MIRA K.` chip when acknowledged.
  - Default selection: the active episode, else the most recent. The URL carries `?episode=`.
- **H2:** B1's chart component for the episode's point.
  - Window: from 2 h before the episode opened to 2 h after it cleared (or now).
  - Limit bands from M11, and the episode's span shaded with its severity wash.
  - Header meta: `PEAK 22.1 V · 11-09 03:12Z`. The server doesn't record a peak, so it's derived from the chart's
    min/max buckets (min for low conditions, max for high). Omit it for catalog alarms, which have no direction.
  - Link `Open in Telemetry` with the same range.
- **H3:** the same point and condition, newest first.
  - Columns: opened · cleared · duration · first → last value · acknowledged by (`—` if not) · how it ended
    (`Back in limits` / `Source stopped reporting it` / `Still open`).
  - Clearing is always automatic. The human act is acknowledging, which has its own column.
  - No peak column: it would need each prior episode's telemetry.
  - Summary line above it: "4th time in 30 days · median 38m".
  - A `choice` `This alarm │ All conditions on VBAT` widens it to every condition on the point.
- **Empty:** "No alarm episodes on EARENDIL-001 in the last 90 days." (neutral, not nominal: no alarms isn't
  the same as healthy).
- **Mobile:** H1 only. An episode opens as its own view (chart, then table).
- Layout: console layout (no page scroll at 1440×900); H1 and H3 scroll.

## Technical details (`<details>`)
Mono key/values: point id, profile id, spacecraft id, alarm id. Collapsed by default.

## States
Loading: header renders from the fleet cache immediately (name/state), panels show `LOADING…`.
Live: value, readouts, chart tail and event log update over the spacecraft channel; the chart
appends without rescaling more than once per minute. Connection lost: stale callout under the tabs;
live readouts go stale-tinted. Unknown spacecraft id: full-page empty state "No spacecraft
EARENDIL-999 in this mission" + `Back to fleet`.

## Acceptance (for qa)
- J2 in ≤3 moves from Now: Engage → (look) → Prepare.
- No page scroll at 1440×900; B2 and B4 scroll.
- `[` / `]` move within the plane and keep the tab; disabled at the ends with a reason in the label.
- No hidden-but-dead controls: Acknowledge/Assign absent until their endpoints ship; B3 absent (deferred).
