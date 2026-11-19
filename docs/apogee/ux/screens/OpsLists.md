# Fleet, Alarms, Telemetry, Timeline (Ops rail items without a board)

These four are in the canvas nav (Journeys "One console, labeled") but not drawn. They're built
only from existing components (design-language §7), so they need no new visual language. All are
**console layout**. Owner: fe-ops. Data: reuse the Now/Investigate payloads where noted.

---

## Fleet (`M/fleet`, rail 02, count = fleet size)
**Question:** "Show me the spacecraft that match X." It's the accessible, filterable twin of the
Now matrix.
```
lbl "EARENDIL · FLEET"   h1 "500 spacecraft"             [Matrix | Table]
filter row: chips plane · profile · state · in contact · search (name or SCID)
stat strip (same 6 tiles as Now, filtered)
┌ F1 Matrix or table (flex 1, scrolls) ───────────────────────────────────┐
```
- **Filters** in the URL (`?plane=7&state=crit,caution&profile=…&q=31`). State filter is a
  multi-select of the state words with marks. "Clear filters" link when any is set.
- **Matrix view:** ApFleetMatrix at a larger cell size (12–16px); non-matching cells drawn at 25%
  opacity, never hidden (fleet first: you still see where they sit).
- **Table view (default under 1100px and for screen readers):** ApTable: Name (link → spacecraft)
  · SCID (mono) · State (mark + word, e.g. `◆ Critical · VBAT`) · Plane · slot (mono) · Profile ·
  Last TLM (mono `2s`, stale-tinted past the threshold) · Next contact (`T−38m FBK`, omitted when
  unknown). Sort by state precedence by default, then name. Virtualized past 200 rows; footer
  count `500 OF 500`.
- **Sticky headings** (lead and fe-ops, 11-15: option A). The table panel is its own scroll box, both ways, so the
  heading row stays while rows scroll and horizontal scroll still works on phones. Conditions:
  - The panel fills to the viewport bottom, and **the page itself doesn't scroll**: one vertical scroller, never two.
  - Below 360px of available height (a short window, or a phone in landscape), it falls back to C: the page
    scrolls, and the headings scroll with it.
  - The **Name** column is sticky on the left while scrolling sideways, so a row's state never loses its
    spacecraft.
  - The scroll box is the kit's focusable, named region ("Fleet table"). Arrow keys and PgUp/PgDn scroll it.
    Tabbing to a row's link scrolls the row into view below the sticky heading, never under it.
- **Empty filter result:** "No spacecraft match plane 07 + critical." + `Clear filters`.
- Data: the Now per-spacecraft list + `last_tlm_at`, `next_contact`.

## Alarms (`M/alarms`, rail 03, count = active alarms in crit tint)
**Question:** "What's out of limits right now, and who has it?"
```
lbl "EARENDIL · ALARMS"   h1 "17 active"            tabs: Active 17 · Acknowledged 4 · Cleared (24 h)
┌ L1 Alarm table (flex 1, scrolls) ─────────────────────────┐ ┌ L2 By point (aside 340) ┐
```
- **L1:** ApTable rows sorted by severity then first-crossed (oldest first): mark + severity word ·
  Spacecraft (link → `M/fleet/:id/investigate?alarm=…`) · Point (short name + description) · Now
  vs limit (`23.1 V / 24.0 V`, state-tinted) · First crossed (`T+34m`, abs in title) · Owner
  (`ACK MIRA K.` / `Unassigned`, DECISIONS #6; column absent until the lifecycle ships) · Next
  contact. Source tag per row (U16: `LIVE` / `GROUND LIMITS · EVALUATED T+3m`). Group identical point+condition across many spacecraft into one expandable row
  ("VBAT below limit · 3 spacecraft in plane 07").
- **L2 By point:** count of active alarms per point (bar meter, `cell-empty` track, state fill),
  click filters L1. Helps spot "is it spreading".
- **Not set up:** if Limits & Alarming isn't installed, h1 `Ground limits off`, an `off` callout
  "Limits & Alarming is not installed, so only flight-event alarms appear." + `Install` (→ Setup ›
  Apps), and the table shows flight-event alarms only. Never a clean "0 active" in that state.
- **Empty:** nominal callout "No active alarms. Last cleared 01:12Z on EARENDIL-047."

## Telemetry (`M/telemetry`, rail 06)
**Question:** "Plot this point for these spacecraft over that window."
```
lbl "EARENDIL · TELEMETRY"   h1 "Explore"      (Explore · Dashboards are tabs under the header, L8)
┌ T1 Points (aside 320, scrolls) ┐ ┌ T2 Plot (flex) ──────────────────────────────────┐
│ search · spacecraft chips      │ │ range: ApTimePicker range variant (presets first) │
│ point list (name, desc, unit)  │ │ ApTimeSeries, one series per sc×point (max 6)     │
└────────────────────────────────┘ ├ T3 Values table (flex none, 180px, scrolls) ──────┤
```
- Spacecraft chips (from ⌘K or `?sc=`) + point search over the catalog. Selecting a point adds a
  series; series colors are **not** status hues: white, `text-2`, `text-3`, `text-4`, dashed white,
  dotted white (6 max) **[decision]**, so color never implies a state.
- Limits from the limit intervals drawn as in B1 when exactly one point is plotted.
- T3: latest value per series (mono, state-tinted against limits, unit, receipt time).
- The spacecraft Telemetry tab (`M/fleet/:id/telemetry`) is this same screen scoped to one
  spacecraft (T1 lists its points; no spacecraft chips).
- **Empty:** "Pick a point to plot" with three suggested points (most recently plotted by you).

- **Canned questions (legacy L20): parked** (DECISIONS #75). The legacy Explore page stays until the user
  revisits them. Meanwhile each question has a console home, and Explore's empty
  state (no points chosen) lists them as four links, with no query engine:
  - `Recent anomalies` → Alarms (Cleared · 24 h tab);
  - `What changed` → Timeline filtered to config;
  - `Missing telemetry` → Readiness › Data sources;
  - `Link health` → Contacts by station.

## Timeline (`M/timeline`, rail 07)
**Question:** "What happened, in order?" (fleet-wide event log + shift handover.)
```
lbl "EARENDIL · TIMELINE"   h1 "Last 24 h"       range: ApTimePicker range · filters: kind · sc · plane
┌ E1 Density strip (flex none, 48px): events per 15 min, stacked by state, now-line ┐
┌ E2 Event log (flex 1, scrolls): ApEventLine rows grouped by hour headers           ┐
```
- Kinds: limit, flight event, contact (AOS/LOS/missed), command (released/verified/failed), config
  (`Config r6 applied`), operator (ack/assign/hand-off note). Each row: time (mono), mark, sentence
  with linked entities.
- E1 is a brush: drag to narrow the range (updates the URL).
- **Live:** new events appear at the top with a 2s `raised` wash; the list doesn't jump if the user
  has scrolled (show `3 new events ↑` pill instead).
- **Empty range:** "No events between 02:00Z and 03:00Z."

## Acceptance (for qa)
- Fleet table and matrix show the same set for the same filters; filters live in the URL.
- Alarms never shows "0 active" while ground limits are not installed.
- Telemetry series colors never use status hues.
- Timeline live updates don't move the scroll position.
