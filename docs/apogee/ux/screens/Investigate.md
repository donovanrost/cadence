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
- **Actions**: `Acknowledge`, `Assign` are **hidden** until the alarm lifecycle exists (U10).
  `Command` (secondary) → `M/commands/new?targets=sc:<id>`.
- **Fact strip** (ApFactStrip): SCID (mono) · Profile (link to Setup profile, name + version) ·
  Orbit (`P07 · slot 12 · #4,812` = plane, slot, orbit number; parts omitted if unknown) · Last LOS
  (`T+00:06:41 FBK`) · **Next AOS** (white top bar, readout: `T−00:38:10 FBK`) · Next eclipse
  (`T−00:59:30`). Unknown facts are omitted (U10); the strip reflows to the facts it has.
- **Tabs** (ApSegmented `tabs`, `role="tablist"`, path segment per tab). Telemetry, Uplink,
  Passes, Configuration, History are specified separately (TBD); until built they render an
  ApEmptyState "Not built yet in the new console" + link to the existing page. **[temporary]**

## B1 · Alarm trend (panel, alert-crit variant: index colored, panel neutral)
Header: index `B1`, title `<POINT SHORT NAME> · <point description> <condition>` (e.g. `VBAT ·
battery voltage below limit`), meta `FIRST CROSSED 2026-10-23 02:08:11Z · UMBRA` (eclipse state
at crossing, only if known).
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
**Hidden until procedures exist (U10).** When present: procedure name (display 24px), one-sentence
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
- No hidden-but-dead controls: Acknowledge/Assign/B3 absent until the backend supports them.
