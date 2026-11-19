# Dashboards in the console (L8, user decision 2026-11-13)

There's no Apogee board. This spec places the cockpit in the console shell. Owner: dashboards (w0R:pG). The
earlier product decisions still hold: edit in place, Grafana-style saving where every save becomes current, with
versions and restore, and server-push live data. Widgets bind telemetry points; limit colours, staleness and
quality come from the ground definitions, never from panel config. Binding modes are fixed, context
(`?spacecraft=`) and constellation.

## Where it sits
- **Rail:** Ops › 06 Telemetry has two views, `Explore` and `Dashboards`, as tabs under its header. There's no new
  rail item. `Dashboards ↗` links became in-console links (IA, OpsLists, Investigate: amended 11-15, §11b).
- **Directory** `M/telemetry/dashboards`: a normal reading page in the shell, with search, a tag filter, starred,
  an ApTable (Name link · Tags (chips) · Spacecraft · Updated by/when) and the primary `New dashboard`. There's no
  folder model, so there's no Folder column (Q4).
- **Entry points for Playlists and Library** (dashboards 178a6c9e4): secondary header buttons left of the primary,
  in the order `Library` · `Playlists` · `New dashboard`. Both are visible to everyone, because anyone can read
  them. They aren't tabs: Explore and Dashboards are views of telemetry, while these belong to dashboards. Their
  pages carry the breadcrumb `DASHBOARDS / PLAYLISTS` (or `/ LIBRARY`) back to the directory. On a phone, the
  buttons wrap under the h1. Spacecraft reads `EARENDIL-312` (fixed), `Chosen when viewing`
  (context) or `Whole fleet` (constellation).
- **Viewer** `M/telemetry/dashboards/:id`: a **console takeover**, like Compose and K1. The rail and top bar give
  way to a takeover header, so the grid gets the full viewport. That's how the cockpit "breaks" the management
  look: dense, full-bleed and header-light. It keeps the same tokens, panel chrome and status grammar, so it still
  reads as Cadence.

## Viewer takeover header (one row, 52px)
`×` (returns to the origin) · mono context `EARENDIL · DASHBOARD` over the title (display 20px) · scope selector
when bound to context (`EARENDIL-312 ▾`, with `[`/`]` for previous/next spacecraft) · ApTimePicker range · refresh
interval · `Edit` · `⋯` (Versions, Share, Kiosk, Inspect…) · right side: the cockpit status cluster, which shows
fleet health counts (crit · caution · stale chips, each linking to Alarms or Fleet) and `UTC 23:55:03`.
- The U38 runtime banner still sits under this header. A live connection loss shows the stale callout, and live
  values go stale-tinted (connection-lost rule).
- **Kiosk** (`⋯ › Kiosk`, or `?kiosk=1`): the header collapses to a 24px status line (title · range · health · UTC).
  Esc leaves kiosk.

## Grid and widgets
- The grid runs to the edges with a 12px gutter. Each widget is an ApPanel (hairline, title 13px display, meta
  right), with no index letters. Widget errors render inside the widget ("This point isn't in the catalog any
  more.") and never break the grid.
- Series colours never use status hues (OpsLists rule). Limit bands and states come from ground definitions.
- **Empty dashboard:** the info callout "Add a widget to start." with the primary `Add widget`.
- **Sections in the viewer** (dashboards, 11-14). Widgets outside any section come first, with no heading. Each
  section then has its title as the heading.
  - The description, when there is one, sits under the title in `text-3`, clamped to 2 lines (the full text in
    its title attribute).
  - Collapse is a disclosure on the heading (▾/▸ before the title; Enter and Space toggle it). A collapsed section
    shows only its heading row, with the meta `3 WIDGETS`. `Start collapsed` sets how it opens. Toggling is per
    viewer and isn't saved. Kiosk and Present use the saved default.
  - A section with no widgets isn't drawn in the viewer.

### Sections in edit mode
- `Add section` (secondary) sits beside `Add widget` in the editing header. It opens a sheet titled `New section`:
  - `Title`, required (≤ 512). Blank: "Give the section a title."
  - `Description`, optional (≤ 4096). Help: "Shown under the title."
  - `Start collapsed` (checkbox). Help: "Viewers see only the title until they open it."
  - Action `Add section`. Like every edit, it changes the draft until `Save…`.
- Each section heading in edit mode has `Edit` (the same sheet, titled `Edit section`, action `Apply`) and a `⋯`
  menu: `Move up` · `Move down` · `Remove section…`. At the ends, Move is disabled with the reason "It's already
  first." / "It's already last."
- **Remove:** an empty section goes at once. A non-empty one first shows a caution callout in place: "Remove the
  section “Power”? Its 3 widgets stay on the dashboard, at the top, outside any section." with `Remove section`
  (danger) and `Cancel`. Widgets go where the server puts them (top, outside any section). There's no re-homing.
- In edit mode, the area outside any section gets a faint `text-4` heading, `Not in a section`, so moved widgets
  can be found. An empty section shows "No widgets yet." under its heading.
- `Add widget` already picks a section, and a new section is offered there at once.

## Edit in place
- `Edit` unlocks the grid. The header shows `EDITING` (caution text) with `Save…` (primary) and `Discard`.
- The widget config is a right-side 400px ApSheet (lead adds the size, K3).
- While editing, live values pause, and a text-3 caption in the header says "Live values paused while editing."
- `Save…` opens a drawer with a message (optional), a changes summary and "Save current range and scope as
  default". Saving creates the new current version.
- **A source isn't answering** (dashboards 6e40e86d0; lead's readiness fix). Save, copy and restore still go through.
  The outcome is a caution callout under the header with `Dismiss`, cleared by another dashboard or a new edit:
  - "Saved. Telemetry wasn't answering when checked at 09:12Z; 3 widgets may stay empty until it does."
  - Degraded: "…was slow when checked at 09:12Z; 1 widget may load slowly or show partial data."
  - `Copied.` / `Restored.` replace `Saved.`. One sentence per source.
  - The realm is named only when it isn't flight ("Telemetry (replay)"). An unknown source reads "A data source".
    Without a check time, drop "when checked at …". The time is §4 (with the date when it isn't today). With 0
    widgets affected, drop the widget clause.
  - Save as copy: the sheet stays open with the note and `Open the copy`, so the note isn't lost on the jump.
- Someone else saved meanwhile: the caution callout "Saved by Mira K. at 02:51Z while you were editing." with
  [Continue editing] [Discard mine]. Continue replays your edits onto the new version and lists any that no longer
  apply.

## Phone (< 768px)
View only. Widgets stack in grid order, one column. There's no Edit, and the header is the mobile header.
- **Viewer header** (dashboards' 390 question, 11-15): at most two rows (~96px), never wrapping into more.
  - Row 1: `×` · the title on one line (truncated; the full name stays in its accessible name) · `⋯`.
  - Row 2: the scope selector `EARENDIL-312 ▾` (fills the row, truncates; no `[`/`]` on phones) · the range button
    in its short form (`Last 1h`, `11-14 02:00–04:00Z`). Both stay visible, because they decide what every plot
    shows. A dashboard without a scope shows the range button alone, right-aligned.
  - The refresh interval moves into `⋯` as `Refresh: every 30 s…`, or `Refresh: off…` when it's off. That item opens
    a sheet with the choices.
    The default range's short form is `Live`; its accessible name keeps the desktop label, `Live · widget windows`.
  - From 768px up, the one-row header may wrap where it doesn't fit.
  - **Fleet health stays on screen** (lead, 11-15). The viewer is a takeover, so the bottom tab bar with its alarm
    count isn't there. In its place goes a 48px bottom bar (`chrome`, hairline top, above the home indicator):
    health on the left, `UTC 23:55Z` on the right.
    - Health uses the cockpit chips with mark and word: `◆ 2 crit · ▲ 1 caution · 3 stale`. Each chip links to
      Alarms or Fleet, as on desktop, and is a 48px target.
    - With nothing to report, it reads `■ Fleet nominal`.
    - Health is never hidden in `⋯`: a status you have to open isn't a status.
    - Kiosk and Present on a phone keep their own 24px status line, which already holds health and UTC.
- **Directory** (dashboards 9b9a99649): Mobile rows, at least 56px. The name link (with ★ and `ARCHIVED`) sits over
  one subtitle line, `EARENDIL-312 · 11-12 02:51Z · Mira K.`. Tags are left off the row; the tag filter stays in
  the toolbar. The `⋯` offers Star only. An unknown part is dropped from the subtitle, never shown as `—`.

## Chart grammar (Q3): uPlot follows ApTimeSeries
The rendering engine differs, but the look is the same.
- **Plot:** well `vacuum` with a `hairline-faint` border; grid `hairline-faint`; axis labels mono 11 `text-4`.
- **Primary series:** `readout`, 1.8px. Min/max envelope: `readout` at 12% behind the line.
- **Limits:** dashed, caution and crit, with the crit wash (`--apogee-wash-crit`) beyond the red limit.
- **Overlays:** now-line white; no-data spans as the stale hatch with "No samples"; legend below in mono 11
  `text-3`.
- **Tooltip:** a `raised` panel with a `line` border, the time in §4 format and values in mono.
- **Series 2–8:** never a hue. Neutral steps and dashes:
  - 2 `text-2` solid
  - 3 `text-3` solid
  - 4 `text-4` solid
  - 5–8 the same four, dashed 4/3
  - Hover or selection brings the series to `readout`. The only colours on a chart are operational states
    (design-language §2).

### Enumerated points (calibration labels, #92 c; a follow-up after the first version)
A point whose engineering value is a label (HK.sc_mode: SAFE / NOMINAL / SCIENCE) is a state, not a number. It
never plots on a numeric axis of raw states.
- **One enumerated point:** a step line with a **categorical y axis**, carrying the defined labels in raw-value order
  (mono 11, `text-3`). Long labels are truncated, with the full label in the tooltip. The tooltip reads "SAFE (2)":
  the label, then the raw value.
- **Several, or mixed with numeric points:** each enumerated point gets its own **state row** above the plot, a
  horizontal band whose segments carry the label inside when it fits (else in the tooltip). The numeric points
  keep the plot below. Two enumerations never share an axis.
- **Colour:** neutral steps as for series 2–8, unless the ground definition gives a state an operational status
  (SAFE = caution). Then that segment takes the status with its mark and word, as for limits. Never colour by the
  label alone.
- A raw value with no label reads "7 (no label)" in `text-4`. It isn't hidden, and it isn't given a made-up name
  (U25).

### Overlays (snapshot `limits` and `events` frames; dashboards asked)
- **Thresholds:** dashed 1px, caution yellow and crit red, with `--apogee-wash-crit` beyond red only (no caution
  wash). They step where a definition changes mid-window, with a 1px vertical tick at the change and the change
  shown in the tooltip ("Limits changed 02:10Z").
- **Limit events:** ApStatusMark shapes (crit diamond, caution triangle) on the series at the sample time, never
  colour alone. Mark only the entry into a state, not every violating sample. When marks would sit closer than
  6px, they merge into one mark with a count in the tooltip ("4 crit entries 02:10Z–02:14Z").
- **Contact intervals:** labelled bands behind the plot, as ApTimeSeries' TimeBand: `raised` fill, station code in
  mono 11 at the top-left. Booked passes are a dashed outline, realized passes are filled. Status other than
  booked or realized (missed, partial) goes in the tooltip in words, not as a colour.
  - **Overlaps** (dashboards, qa look 11-14): overlapping flown passes merge into one 5% tint behind the series, so
    tints never stack. Labels are drawn on top of every band.
  - **Booked vs flown:** where a flown pass covers its booking, only the pass's solid edges are drawn. Where the
    booking reaches past the flown pass (a late start or an early end), the dashed outline is drawn on **that part
    only**, so lost time shows. A booking with no flown pass stays dashed in full.
  - **Realized but never started** (no AOS; closed by the sweep): drawn at its **scheduled** window as a booking
    with no flown pass, dashed in full, with the station code label. The tooltip says "FAI pass · didn't start"
    (U45's words). It's never drawn from realized to the sweep's close: nothing flew in that span. Not (a), hiding
    it, because a pass that didn't start is exactly what an operator needs to see.
    - From domain's frame (`started: false`, `close_reason`): the tooltip adds the reason. window_ended: "FAI pass ·
      didn't start: its window ended first". hand_start_expired: "FAI contact · didn't start: the hand start
      expired". Unknown: no reason.
    - A hand start that never started has no booking, so it's dashed over its realized span with the same
      tooltip, in "contact" words (U46).
- **Point events:** a thin `text-4` vertical line, with the label in the tooltip. Mission events closer than 6px
  merge into one mark, titled "4 events 02:10Z–02:14Z". Watermark and evidence events aren't chart marks: they're
  a stream, not events an operator reads.
- **No glows or box-shadows** anywhere in the chart. Remove the engine's.
- **A range with no samples** (dashboards, 11-15). The time-series widget still draws its frame: the x axis from
  the dashboard's range, no y labels, the stale hatch across the whole plot, and the contact bands and event marks
  over it. A centred `text-3` caption reads "No samples in this range." (the hatch's own word, "samples"). It never
  says why: Cadence can't tell telemetry that was dropped from telemetry that never came (U20). Tiles, tables and
  state widgets keep their plain message. A **live** range draws `now − window … now`, rolling with the
  refresh, with the now-line, because a live pass with no samples matters most.

## Chart tokens (K2): Apogee values for the 29 base `--chart-color-*`
Alpha variants derive from these, so only the bases change. They're RGB triplets.
| Token | Apogee | RGB |
| --- | --- | --- |
| label | text-3 | 157, 170, 184 |
| muted, compare, unknown-surface, border | text-4 | 125, 138, 153 |
| tooltip-surface, current-surface | raised | 15, 20, 27 |
| shadow | black | 0, 0, 0 |
| foreground, text, action, current, current-text, selection | readout | 230, 237, 243 |
| text-strong, highlight | bright | 255, 255, 255 |
| text-secondary | text-2 | 201, 211, 221 |
| panel | panel | 10, 14, 19 |
| surface | vacuum | 5, 7, 10 |
| warning, caution | caution | 255, 176, 32 |
| warning-text | caution-text | 255, 194, 77 |
| warning-surface | caution over panel | 31, 24, 9 |
| critical | crit | 255, 77, 87 |
| success | nominal | 47, 208, 138 |
| revision, backfill | text-3 | 157, 170, 184 |
| stale-surface | stale | 164, 151, 255 |
| retention-surface | text-off | 74, 85, 98 |
`--chart-series-primary: var(--color-readout)` · `--chart-font: 11px var(--font-mono)`. Where they live is lead's
call (K2). The old teal "current" and violet "compare" hues are gone on purpose.

## Snapshots and shares (Q5)
- **Snapshot from the viewer:** freezes the time window you're looking at. A live range (`now-6h`) becomes absolute
  at that moment. It records the definition at the current version.
  - The shared view's header reads `SNAPSHOT · 11-12 21:00Z–23:00Z · v7 · taken by Mira K. at 23:02Z`.
  - There's no live data, no Edit, and the range picker is replaced by that line.
- **Share link:** a live view of the current version. The header reads `SHARED · live · expires 11-20` (or `no
  expiry`). Data visibility: `Definition only` (widgets show "Data isn't shared in this link.") or `With data`.
- **Settings › Sharing tab:** two tables.
  - Shares: link (copy) · Data · Expires · Created by/when · `Revoke` (confirms).
  - Snapshots are taken only in the viewer, where you can see the window (no `Take snapshot` here). The table's
    caption reads "Take a snapshot from the dashboard: set the range, then ⋯ › Take snapshot." with a link to the
    viewer.
  - Snapshots: window · version · taken by/when · open. There's no Delete: snapshots are immutable in the domain
    (fe-setup 294f66b4). If snapshots are ever reachable outside the mission, stopping access becomes a director
    question.
  - Primary: `Create share link` (sheet: data visibility segmented, expiry date optional).

## New dashboard (Q7): a small page, as proposed
`M/telemetry/dashboards/new`, a reading page.
- Fields: Name · Description (optional) · Tags · Spacecraft (`One spacecraft` with a picker / `Chosen when
  viewing` / `Whole fleet`) · Start from (`Empty` / a library template).
- Primary `Create and edit` opens the viewer in edit mode.

## Settings (`…/:id/settings/:tab`), a reading page
Tabs: `General` · `Sharing` · `Activity` · `Diagnostics`.
- **Entry** (fe-setup, 11-14): the viewer's `⋯` menu, after Versions.
  - Authors see `Settings` and get all four tabs, opening on General.
  - Everyone else sees `Activity and diagnostics` (the page isn't settings for them) and gets those two tabs only,
    opening on Activity. General and Sharing are hidden, not disabled.
  - Not on phones, which are view only.
- **General:** name, description, tags, defaults (range, spacecraft). Saving creates a current version, with a
  "Saved as v8" line.
- **Activity:** an event list (save, restore, archive, share, export) with actor and time.
- **Diagnostics:** one row per widget, from what's recorded (no timings until domain records them, U20):
  - status mark and word (`■ OK` / `▲ DEGRADED` / `○ NOT RUN YET` for planned);
  - cache (`Fresh` / `From cache`);
  - the operator action as a sentence when there is one;
  - warnings in words, with codes, severity and retryable in Technical details.
  - Sorted worst first.
- `Archive` sits at the foot of General (danger, confirms, "Archived dashboards leave the directory; their links
  stop working.").

## Library
`…/dashboards/library`: ApTable of reusable widgets (Name · Kind · Used in N dashboards · Updated).
- The row page shows the versions and a preview. The preview's binding line is a `READS` label, then a sentence
  that names the point and says where the spacecraft comes from, because a library item doesn't know its placement
  (fe-ops aed173887):
  - Follows the dashboard: "EPS.batt_soc on the dashboard's spacecraft".
  - One spacecraft: "EPS.batt_soc on one spacecraft, chosen where it's placed".
  - Repeats: "EPS.batt_soc on each spacecraft or resource it repeats over, chosen where it's placed".
- `Rename`.
- `Delete`: refused while it's used, with "Used in 3 dashboards: A, B, C." From the editor's Add widget sheet, a
  `From library` tab inserts one.

## Playlists and present
- **Directory** `…/playlists`: Name · Dashboards (count) · Dwell (`30 s`) · Updated · `Present`.
  - Editor (sheet `wide`): name, dwell, wallboard mode, and an ordered dashboard list (add, ↑ ↓, remove).
  - Delete confirms.
- **Present** (takeover, kiosk by default): each dashboard full-screen in turn. A 24px status line reads `PLAYLIST
  · Ops wall · Power overview · 2 of 5 · next in 0:18`, plus health and UTC. Keys: ←/→ step, Space pauses (`PAUSED`), Esc leaves. A
  dashboard that fails to load shows its error for one dwell and the rotation moves on.
  - **Screen readers** (qa's a11y check b71d635f5): on open, Present puts focus on its own h1, the playlist's name
    in the takeover header (`tabindex=-1`). It doesn't use the shell's `<main>` fallback (fe-ops 2f246c0d2), because
    that h1 sits outside `<main>`. Esc returns focus to the `Present` that opened it.
  - A polite live region names the dashboard first, then its position. The countdown stays out of it:

    | When | Announcement |
    | --- | --- |
    | Open, each step (←/→, auto-advance) | "Power overview, 2 of 5" |
    | Space pauses | "Paused: Power overview, 2 of 5" |
    | Space resumes | "Playing: Power overview, 2 of 5" |
    | A dashboard can't load | "Power overview couldn't load, 2 of 5" |

## Export
`⋯ › Export` downloads the dashboard bundle (JSON). A toast reads "Exported Ops overview v7." There's no import in
this step.
