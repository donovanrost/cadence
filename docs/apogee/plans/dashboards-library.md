# Dashboards slice 8: Library (D21–D22 proposal)

fe-ops, 2026-11-13, for api (cc dashboards, lead, domain). Spec: ux `screens/Dashboards.md` § Library. Plan:
`plans/dashboards.md` (data table D21/D22, "Delete and references", audit). Rulings: DECISIONS #76 Q1 (library
inserts are editor commands, saved through `CurrentVersions`), Q6 (update and delete are new domain functions),
Q10 (refuse while used, then retire; never a hard delete; audited).

All paths under `/api/console/v1/missions/:mission_id/dashboard-library`: a sibling of `/dashboards` (like slice 6's
`/dashboard-playlists`), so `library` never reads as a `:dashboard_id` (dashboards' review). Errors use the console Problem
envelope (`{error: {code, message, details}}`). Invalidation: `dashboards`.

## What exists (read of the domain, 2026-11-13)
- `Reads.Dashboards.Library.load` (author): `items [{id, name, description, latest_version}]` (paged by
  `next_item`), `selected {item, version, widget_json, versions [{version, summary, actor_id, saved_at}],
  consumers {total, rows [{id, name, version, pins [{id, version}]}]}}` (consumers are current drafts).
- `LibraryAuthoring`: create item, add version, add to draft. **No update, no delete** (Q6).
- Not in the list rows: the widget kind, the use count, when and by whom it last changed. The table needs all
  four (Name · Kind · Used in N dashboards · Updated).

## Proposed shapes

### D21 `GET /dashboard-library?q=&page=` (mission member)
```
{items: [{id, name, description, kind, latest_version, used_by_count,
          updated_at, updated_by: {id, name} | null}],
 total, page, pages, page_size, can_edit}
```
- `kind`: the latest version's widget type (`value_tile | time_series | status_matrix | data_table |
  state_timeline | event_timeline | constellation_health`); the console reads it tolerantly.
- `used_by_count`: dashboards whose **current** version places it (the same rule Delete uses).
- Retired items are left out. `q` matches name and description.

### D21 `GET /dashboard-library/:item?version=n` (mission member)
```
{item: {id, name, description, kind, latest_version, updated_at, updated_by},
 version: {version, definition_json, summary, saved_at, saved_by: {id, name} | null},
 versions: [{version, summary, saved_at, saved_by}],          // newest first, ≤ 100
 used_by: {dashboards: [{id, name, placements, pinned_versions: [n]}]},
 can_edit}
```
- `version` defaults to the latest. `definition_json` is the widget definition as text (64-bit safe), the
  same shape a placement embeds; the row page previews it.
- A retired item is `404 library_item_not_found` (its versions stay stored for old dashboard versions).

### D22 writes (author: the editor's `:edit` access)
- `POST /dashboard-library {name, description, definition_json, summary}` → `201 {id, version: 1}`.
- `POST /dashboard-library/:item/versions {definition_json, summary, expected_version}` → `{version}`;
  `409 library_item_changed` with `details {latest_version}`.
- `PATCH /dashboard-library/:item {name?, description?, expected_version}` → the D21 item; `409 library_item_changed`;
  `422 invalid_params` (name blank or over 120 characters).
- `DELETE /dashboard-library/:item?expected_version=n` → `204`, which **retires** the item (Q10).
  `409 library_item_in_use` with `details {used_by: {dashboards: [{id, name, placements}]}}` while any
  current dashboard version places it; `409 library_item_changed` if it moved. Writes the audit record
  "Retired library widget Battery tile" (`target {kind: library_item, id, label}`).
- `403 forbidden` for viewers: "Dashboard editors manage the library."

### Not here
- **Add to dashboard** places a library **reference**, not a copy, so "Used in N dashboards" stays true:
  the editor stages a new authoring command `add_library_widget {placement_id, library_item_id, version,
  section_id}` (dashboards is asking domain; this proposal assumes it), saved through `CurrentVersions` (Q1).
  The console seam is `LibraryPicker.vue`, emitting `{library_item_id, version, name}`, mounted in
  WidgetSheet's `From library` tab by dashboards.
- **Live preview.** v1 previews the definition (kind, title, bound points, display options) from
  `definition_json`. A rendered preview needs the widget evaluated at a context, so it would be a later read
  (`POST /dashboard-library/:item/preview {version, context}` → one widget frame). Say if it's cheap to reuse the
  dashboard preview path.

## Domain (Q6)
`LibraryAuthoring.update_item(scope, mission, item_id, %{name?, description?}, expected_version)` and
`LibraryAuthoring.retire_item(scope, mission, item_id, expected_version)`, the latter refusing with
`{:in_use, used_by}` computed over current versions, and recording the audit entry.
