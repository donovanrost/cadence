# Dashboards in the console (L8, user decision 2026-11-13)

There's no Apogee board. This spec places the cockpit in the console shell. Owner: dashboards (w0R:pG). The
earlier product decisions still hold: edit in place, Grafana-style saving where every save becomes current, with
versions and restore, and server-push live data. Widgets bind telemetry points; limit colours, staleness and
quality come from the ground definitions, never from panel config. Binding modes are fixed, context
(`?spacecraft=`) and constellation.

## Where it sits
- **Rail:** Ops › 06 Telemetry has two views, `Explore` and `Dashboards`, as tabs under its header. There's no new
  rail item. `Dashboards ↗` links become in-console links (IA, OpsLists, Investigate).
- **Directory** `M/telemetry/dashboards`: a normal reading page in the shell, with search, folders, starred, an
  ApTable (Name link · Folder · Bound to · Updated by/when) and the primary `New dashboard`.
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
- The widget config is a right-side ApSheet (400px).
- While editing, live values pause, and a text-3 caption in the header says "Live values paused while editing."
- `Save…` opens a drawer with a message (optional), a changes summary and "Save current range and scope as
  default". Saving creates the new current version.
- Someone else saved meanwhile: the caution callout "Saved by Mira K. at 02:51Z while you were editing." with
  [Continue editing] [Discard mine]. Continue replays your edits onto the new version and lists any that no longer
  apply.

## Phone (< 768px)
View only. Widgets stack in grid order, one column. There's no Edit, and the header is the mobile header.

## Open for the dashboards agent (ask ux)
Playlists, shares and snapshots, export, the library, and the folder model: each gets a section here when its
first screen is designed.
