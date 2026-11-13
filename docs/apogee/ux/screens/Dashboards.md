# Dashboards in the console (L8, user decision 2026-11-13)

There's no Apogee board. This spec places the cockpit in the console shell. Owner: dashboards (w0R:pG). The
earlier product decisions still hold: edit in place, Grafana-style saving where every save becomes current, with
versions and restore, and server-push live data. Widgets bind telemetry points; limit colours, staleness and
quality come from the ground definitions, never from panel config. Binding modes are fixed, context
(`?spacecraft=`) and constellation.

## Where it sits
- **Rail:** Ops › 06 Telemetry has two views, `Explore` and `Dashboards`, as tabs under its header. There's no new
  rail item. `Dashboards ↗` links become in-console links (IA, OpsLists, Investigate).
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

## Edit in place
- `Edit` unlocks the grid. The header shows `EDITING` (caution text) with `Save…` (primary) and `Discard`.
- The widget config is a right-side 400px ApSheet (lead adds the size, K3).
- While editing, live values pause, and a text-3 caption in the header says "Live values paused while editing."
- `Save…` opens a drawer with a message (optional), a changes summary and "Save current range and scope as
  default". Saving creates the new current version.
- Someone else saved meanwhile: the caution callout "Saved by Mira K. at 02:51Z while you were editing." with
  [Continue editing] [Discard mine]. Continue replays your edits onto the new version and lists any that no longer
  apply.

## Phone (< 768px)
View only. Widgets stack in grid order, one column. There's no Edit, and the header is the mobile header.
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
- **Point events:** a thin `text-4` vertical line, with the label in the tooltip.
- **No glows or box-shadows** anywhere in the chart. Remove the engine's.

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
- The row page shows the versions and a preview.
- `Rename`.
- `Delete`: refused while it's used, with "Used in 3 dashboards: A, B, C." From the editor's Add widget sheet, a
  `From library` tab inserts one.

## Playlists and present
- **Directory** `…/playlists`: Name · Dashboards (count) · Dwell (`30 s`) · Updated · `Present`.
  - Editor (sheet `wide`): name, dwell, wallboard mode, and an ordered dashboard list (add, ↑ ↓, remove).
  - Delete confirms.
- **Present** (takeover, kiosk by default): each dashboard full-screen in turn. A 24px status line reads `PLAYLIST
  · Ops wall · 2 of 5 · next in 0:18`, plus health and UTC. Keys: ←/→ step, Space pauses (`PAUSED`), Esc leaves. A
  dashboard that fails to load shows its error for one dwell and the rotation moves on.

## Export
`⋯ › Export` downloads the dashboard bundle (JSON). A toast reads "Exported Ops overview v7." There's no import in
this step.
