# Design: Telemetry Decom Configuration UI Redesign

- Status: draft
- Created: 2026-04-23
- Scope: LiveView redesign of `/missions/:mission_id/spacecraft/:spacecraft_id/telemetry_decom`
- Related specs: [2026-04-23 Application APID Selection](./2026-04-23-application-apid-selection-design.md)

## Summary

The current Telemetry Decom configuration page is a functional first pass: four
stacked cards (Status, Configuration, Packet Definitions preview, Apply) with a
free-form comma-and-range text input for handled APIDs. Operators have no way
to discover which APIDs exist in the selected catalog revision, what those
packets carry, or how their selection overlaps with other applications on the
same spacecraft — they have to leave the page and browse the catalog to decide
what to type.

This design replaces the page with a single-card composition whose centerpiece
is a **per-APID table with inline progressive disclosure**. Operators select
APIDs by checkbox, see packet names and rates inline, and expand a row to read
a packet's description and drill into its entry fields — all without leaving
the page. Preview stats and the apply action remain on the same surface.

## Problem

The current page has three specific issues, in order of impact:

1. **No discoverability.** The handled-APIDs input is free-form text
   (`1, 2, 5-8, 42`). To know what APIDs exist in the revision and what they
   mean, operators have to navigate to the catalog and read packet
   definitions elsewhere. The configure surface doesn't tell them what they
   are configuring.
2. **Visual composition is generic.** Four same-weight `bg-base-200` cards
   stacked vertically give the page a settings-dump feel. There is no
   hierarchy between the operational frame (status / apply) and the
   configuration body, and the preview is always below the fold.
3. **Save/Apply flow has two verbs for what feels like one decision.**
   Operators must click Save before Apply, with no clear mental model of why.

Non-problems (explicitly): the backend model is correct, the preview content is
correct, the status taxonomy is correct.

## Goals

- Make APIDs and their packet definitions discoverable on the configure page
  itself.
- Compose the page in a way that reads as an ops console, not a settings form.
- Reduce the save/apply surface to a single explicit action: **Apply mission
  changes**. Configuration saves are implicit.
- Surface overlap with other applications on the same spacecraft inline on each
  row.
- Keep the page under the 400-line file-size rule by extracting the APID table
  component.

## Non-goals

- Packet groups, packet classes, saved APID sets, or any selection primitive
  beyond APID. Deferred per the APID selection spec.
- Editing packet definitions or entries. This view is read-only for catalog
  content.
- A "paste APIDs" escape hatch. May be added later if operators request it.
- Any change to the spacecraft show page's Telemetry Decom summary.
- Any change to `Cadence.Applications.TelemetryDecom` beyond a small helper for
  conflict detection.
- Any change to CSS. All composition uses existing daisyUI / Tailwind / HUD
  utilities.

## Page Composition

One `card bg-base-200` replaces the four stacked cards. The card body is
divided into five sections separated by thin dashed dividers, top to bottom:

1. **Status line.** `status_dot` + status label (`Applied`, `Configured`,
   `Outdated`, `Disabled`, `Not configured`) + revision name + "Saved N ago"
   on the right.
2. **Catalog revision.** `hud-label` + `<.input type="select">`, narrow
   (~280px). Changing the revision triggers a re-fetch of available APIDs and
   a re-validation of the current selection against the new revision.
3. **Handled APIDs.** `hud-label` with a live count (`6 / 12`), followed by a
   controls row (filter input on the left, "Select all unclaimed" and "Clear"
   on the right), then the APID table described below.
4. **Preview strip.** Four tiles in a `grid grid-cols-2 md:grid-cols-4 gap-3`:
   Matched packets, Compiled defs, Unassigned APIDs, Notices. When the
   diagnostics list is non-empty, it renders directly below the tiles.
5. **Apply row.** Right-aligned `btn btn-primary` ("Apply mission changes")
   and `btn btn-ghost` ("Disable", when enabled).

The breadcrumb link back to the spacecraft show page and the page title sit
above the card, unchanged from today.

## APID Table

### Row unit

The row unit is the APID, not the packet definition. This is consistent with
the APID selection spec: applications claim APIDs, and claiming an APID claims
every packet definition under it. APIDs with multiple definitions appear as a
single row whose name column reads `"Payload Frames (2 defs)"`.

### Columns

| Column | Source |
|---|---|
| Checkbox | selection state |
| Chevron `›` | expansion state (rotates when open) |
| APID | `packet.apid` |
| Packets | primary packet `name`; or `"<first name> (N defs)"` for N > 1 |
| Defs | count of packets sharing this APID |
| Rate | first def's `expected_rate_hz`, or `—` |
| Conflict | name of another enabled app on this spacecraft already claiming this APID, else `—` |

### Selection semantics

Toggling a row's checkbox immediately updates the in-memory selection set and
re-runs the preview computation. Rows whose APID is already claimed by a
different enabled application on this spacecraft render with a disabled
checkbox and a conflict tag in the Conflict column.

### Filter

A text input above the table narrows the visible rows to those whose APID
number or packet name contains the filter string. Filter state is a socket
assign updated via `phx-change`; re-render is LiveView-driven but cheap since
it's a pre-fetched list in memory. The filter does not change the selection or
the preview — it only hides rows from view.

### Bulk actions

- **Select all unclaimed** — checks every APID in the revision whose row is
  not in conflict with another enabled application.
- **Clear** — empties the selection set.

Both re-run the preview immediately.

### Expansion

Clicking anywhere on a row (except the checkbox) toggles expansion.
Expansion state is a `MapSet` of expanded APIDs on the LiveView socket.
Multiple rows may be open at once. The chevron in the row rotates 90° when
open.

## Progressive Disclosure

Three levels:

### Level 1 — row

Default state. Columns listed above. Compact.

### Level 2 — expanded row

Rendered as an indented block directly below the row, with a left border in
the primary accent color. Content:

- The APID's **short description** (from the first packet's
  `short_description`, falling back to the first 160 characters of
  `description`). If all definitions lack both fields, the section is omitted.
- One **definition block** per packet definition. Each block has:
  - packet `name` (prominent),
  - a meta line: `apid=N · type=N · N b` (size_bits),
  - an "expand entries" affordance on the right.

For APIDs with a single definition, the single definition block is visible by
default (no collapse). For APIDs with multiple definitions, each block is
collapsible independently.

### Level 3 — entries table

Expanding a definition block reveals a compact entries table, rendered from
`Packet.entries`:

| name | type | size | description |
|---|---|---|---|
| `bus_voltage` | `float32` | `32 b` | Primary bus voltage (V) |

The first 20 entries render inline with a "show N more entries…" footer
revealing the rest. Entries are read-only.

## Save Model

The current page has two buttons: **Save configuration** (persist to DB) and
**Apply mission changes** (publish to live mission). Operators have no mental
model for when to click Save separately from Apply.

This design eliminates the explicit Save button. Every configuration-changing
interaction — revision select, checkbox toggle, bulk action — debounces by
~300 ms and calls `TelemetryDecom.configure/4`. On success, the status line
flips to "Saved N ago." On failure, an inline error appears next to the
offending control and the selection state rolls back to the last-saved state.

**Apply mission changes** remains the only explicit button. It publishes the
saved state to the live mission.

## Validation and Error States

### Conflict (APID claimed by another app)

Inline in the row: disabled checkbox, conflict app name in the Conflict
column. No toast, no modal. Requires a new helper:

```elixir
# Cadence.Applications.TelemetryDecom
@spec list_apid_conflicts(organization_id, mission_id, spacecraft_id) ::
        %{non_neg_integer() => String.t()}
def list_apid_conflicts(org, mission, spacecraft)
```

Returns a map of APID → other-application display-name for every APID claimed
by a different enabled application on this spacecraft.

### Unknown APIDs after revision change

When the selected revision changes and some currently-selected APIDs are not
present in the new revision, a warning banner renders above the APID table:

> ⚠ 2 previously selected APIDs are not in this revision: 77, 99. **Drop
> them?**

Clicking the action strips the unknown APIDs from the selection and triggers
an autosave.

### Empty revision list

Unchanged from today: "No telemetry catalog revisions available for this
mission yet. Import a catalog revision first." + link to the catalog route.

### Server error on save

Inline error line near the affected control (e.g., below the revision select
or the APID table). Selection state rolls back to the last-saved state.

## Data Dependencies

### Already available

- `Cadence.Catalog.list_revisions/2`
- `Cadence.Applications.TelemetryDecom.fetch_config/3`
- `Cadence.Applications.TelemetryDecom.configure/4`
- `Cadence.Applications.TelemetryDecom.preview/3` — returns `selected_packets`,
  `unassigned_apids`, `compilation.compiler_result.{packet_definitions,
  diagnostics}`
- `Cadence.Applications.TelemetryDecom.status/2`
- `Cadence.Catalog.Telemetry.Packet` — fields: `apid`, `name`, `description`,
  `short_description`, `size_bits`, `expected_rate_hz`, `entries`
- `Cadence.Catalog.Telemetry.PacketEntry` — fields for the entries table

### New

- `Cadence.Applications.TelemetryDecom.list_apid_conflicts/3`, as above.
- `Cadence.Applications.TelemetryDecom.list_available_apids/3` (or similar)
  that returns the sorted list of APIDs in a revision with their packet list
  and aggregate metadata, so the LiveView does not re-derive this on every
  keystroke. Exact shape to be chosen during implementation.

## Module Boundaries

The current `SpacecraftTelemetryDecomLive` is 440 lines and will grow. To stay
under the 400-line file-size rule:

- `CadenceWeb.SpacecraftTelemetryDecomLive` — LiveView shell: mount, event
  handlers, status/preview computation, top-level render. Target < 300 lines.
- `CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable` — stateless function
  component rendering the APID table, expansion blocks, and entries tables.
  Receives assigns for rows, selection set, expansion set, conflict map,
  filter string. Target < 250 lines.

Event handling (checkbox toggle, row click, entry expansion, filter input,
bulk actions) stays on the LiveView; the component renders markup only.

## UI Rules Compliance

This design respects the project's non-negotiable UI rules (see `CLAUDE.md`):

- **No new CSS.** Composition uses existing daisyUI classes (`card`,
  `btn btn-primary`, `btn btn-ghost`, `btn btn-sm`), Tailwind utilities, and
  existing HUD utilities (`hud-label`, `hud-grid`, `hover-glow-cyan`).
- **No raw HTML form inputs.** Revision select uses `<.input type="select">`.
  Filter input uses `<.input type="text">`. Checkboxes are the only exception
  that needs discussion during implementation — if a plain `<input
  type="checkbox">` inside a table row is unacceptable, we add a
  `<.input type="checkbox">` wrapper or extract a small `<.apid_checkbox>`
  helper; no new CSS.
- **No render function over 50 lines.** The APID table component and each of
  its sub-functions (row, expanded block, entries table) stay under 50.
- **No file over 400 lines.** Both modules target well under this.
- **Match existing templates first.** The card composition and `hud-label`
  divider pattern already exists in `SpacecraftShowLive` and the catalog
  views; we reuse those patterns.

## Testing

Integration tests live in
`apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs`
(already present). New coverage:

- toggling an APID checkbox autosaves and updates the preview count
- changing revision with a selection that becomes partially invalid shows the
  "drop unknowns" banner; clicking the action autosaves
- an APID in conflict with another enabled application renders disabled and
  cannot be toggled
- expanding a row shows the description and definition blocks; expanding a
  definition block shows the entries table
- the filter input narrows the visible rows
- "Select all unclaimed" and "Clear" modify the selection
- Apply and Disable still work as today

## Implementation Notes / Open Questions

- **Checkbox in a table row** — the project's UI rule says "never write raw
  HTML form inputs, use `<.input>`." For a single toggle inside a dense row
  this may be overkill; we'll resolve during implementation by either
  wrapping with `<.input type="checkbox">` (with a label-less variant) or
  adding a small private component. No new CSS either way.
- **Autosave debounce duration** — 300 ms is a starting point. If it feels
  laggy during testing, reduce to 150 ms.
- **Keyboard access** — row expansion should also be triggered by pressing
  Enter or Space when the row is focused. Standard a11y expectation; flag as
  a follow-up if it grows the scope too much.
- **Filter scope** — an in-memory substring match over the pre-fetched APID
  list is proposed. If a revision has thousands of APIDs this may need to
  page at the data layer; leave as a follow-up unless early feedback shows
  render lag.
