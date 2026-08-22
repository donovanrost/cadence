# Design: Catalog UI — Progressive Disclosure and Family Removal

- Status: draft
- Created: 2026-04-21
- Scope: catalog index, catalog database detail, catalog revision detail
- Related: [2026-04-20 Catalog Database and Revision Library](2026-04-20-catalog-database-revision-library-design.md)

## Summary

The catalog UI landed with both upload forms always expanded inline, and with
`catalog_family` badges on every surface. This design does two narrowly-scoped
changes:

1. Move both upload forms behind progressive disclosure — a dedicated page for
   creating a new catalog database, and an inline reveal for adding a revision
   to an existing database.
2. Remove the `catalog_family` badge, column, and classification from the UI.
   The domain concept stays intact: importer detection, persisted
   `catalog_family` values, and compatibility validation are unchanged.

This track does not touch domain code, the catalog library spec, or other
planned polish (Operations HUD, revision depth, empty-state copy overhaul).

## Problem

Two issues on the current catalog surfaces:

- The catalog index always shows the full "Create catalog database revision"
  upload card above the database list. The database detail page always shows
  the "Add revision" card above the revision history. Both push the data a
  user came to look at below the fold and make the pages feel heavy.
- The `catalog_family` badge is visible on four surfaces (index table, database
  header, revision history table column, revision detail header). It does not
  drive any operator decision today, and it adds visual noise to pages that
  are already dense with provenance and import state.

## Goals

- Replace the always-open upload card on the catalog index with a button that
  navigates to a dedicated "New catalog database" page.
- Replace the always-open "Add revision" card on the database detail page with
  a toggle that reveals the form in place.
- Remove every visible Family badge and column from the three catalog LiveViews
  and the shared Catalog.Components module.
- Preserve the existing backend behavior around family detection, persistence,
  and validation.

## Non-goals

- Polish sweep (Operations HUD aesthetic, `hud-corners`, paneled tiles, status
  bar). That is a separate track.
- Revision depth — diffs between revisions, surfacing `notes`, richer snapshot
  summaries.
- Empty-state copy overhaul beyond the minimum required by the CTA change.
- Any change to `Cadence.Catalog` domain functions, schemas, or validators.
- Any change to `Cadence.Catalog.Registry` importer detection.
- Modal dialogs as a disclosure pattern. The app has no modal precedent and
  the upload form needs enough room for importer detection output and upload
  errors.

## Current State

Relevant files:

- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex`
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_revision_show_live.ex`
- `apps/cadence_web/lib/cadence_web/live/catalog/components.ex`
- `apps/cadence_web/lib/cadence_web/router.ex`

Current Family usages in the UI:

- `catalog_index_live.ex` — `Family` column in the databases table.
- `catalog_database_show_live.ex` — badge in the page header, `Family` column
  in the revision history table.
- `catalog_revision_show_live.ex` — badge in the page header.
- `Catalog.Components` — `catalog_family_badge/1` component, plus the
  `detected_preview` component (which also renders a family badge next to a
  detected importer).

## Disclosure Pattern

### New catalog database — dedicated page

Create `CadenceWeb.CatalogDatabaseNewLive` at
`apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_new_live.ex`.
It mirrors the shape of `CadenceWeb.SpacecraftNewLive` and
`CadenceWeb.MissionNewLive`.

Behavior:

- Mounts inside the existing catalog `live_session`, so it gets the same
  on-mount hooks and layouts.
- Sets `assigns.nav_item = :catalog` for sidebar highlighting.
- Sets `assigns.page_title = "New catalog database"`.
- Renders a single centered card with the form fields: `name`,
  `revision_label` (optional), `revision_notes` (optional textarea), and a
  `live_file_input` for the source artifact.
- Reuses `upload_card/1` and `detected_preview/1` from `Catalog.Components`
  to render the form and show the detected importer. The family badge inside
  `detected_preview/1` is removed as part of the Family removal section
  below. `upload_card/1` stays in place — it retains exactly one caller
  (the new page), but it continues to live in the shared components module
  because its siblings there (`snapshot_summary_card`, `diagnostic_list`,
  `detected_preview`, `upload_error_alert`) form a cohesive module.
- Submits via `phx-submit="save"`.
- On success, it runs the same three-step sequence currently in
  `CatalogIndexLive.perform_upload/3`:
  1. `Catalog.create_database/3`
  2. `Catalog.Artifact.build_from_upload/4`
  3. `Catalog.start_revision_import/7`
  Then it `push_navigate`s to the import run detail page.
- `Cancel` renders as a `<.link navigate>` back to `/catalog`.

Route added inside the catalog live session in `router.ex`:

```elixir
live "/missions/:mission_id/catalog/new",
     CatalogDatabaseNewLive, :new
```

### Catalog index changes

- Remove the `<.upload_card ...>` call and its assigns/event handlers from
  `CatalogIndexLive`. The `handle_event("validate" | "cancel_upload" | "save",
  ...)` clauses (all of which match `catalog_database` params on the index)
  move to `CatalogDatabaseNewLive`, along with `allow_upload(:artifact, ...)`,
  the `:database_form` assign, and the `create_catalog_database/6`,
  `revision_metadata/1`, `detect_from_uploads/1`, `uploader_identity/1`,
  `empty_database_form/0`, `normalize/1`, and `slugify/1` helpers.
- Add a `+ New database` primary button in the page header, styled
  `btn btn-primary`, with `navigate={~p"/missions/#{mission_id}/catalog/new"}`.
- The existing empty-state card (`No catalog databases yet`) gains a
  `+ New database` link styled as `btn btn-primary btn-sm`, pointing at the
  same route. Copy is unchanged.

### Add revision — inline reveal

- Add a new assign `@show_revision_form` that defaults to `false` in
  `CatalogDatabaseShowLive.mount/3`.
- Add a `+ Add revision` primary button in the top-right of the page header
  row, next to the existing title and family badge (badge itself is removed
  per the Family Removal section). When the form is open, the same button
  becomes `Cancel` (ghost variant). Both are wired to a single
  `phx-click="toggle_revision_form"` event.
- `toggle_revision_form` flips `@show_revision_form`. Cancelling also calls
  `cancel_upload(socket, :artifact, entry.ref)` for any in-progress uploads and
  resets `@revision_form` to `empty_revision_form/0`.
- The existing `revision_upload_card/1` private component is wrapped in
  `<%= if @show_revision_form do %>`.
- Nothing else on the page changes. The revision history, import attempts,
  database metadata card, and runtime-usage placeholder stay as-is.

## Family Removal

Scope is UI only. No domain code is touched. The backend continues to set
`catalog_family` on databases, revisions, artifacts, and import runs; the
importer registry continues to report it via `descriptor.catalog_family`;
validation rules continue to enforce family compatibility.

Changes:

- `Catalog.Components.catalog_family_badge/1` is deleted. Private
  `family_badge_class/1` and `family_label/1` helpers go with it.
- In `detected_preview/1`, the `<.catalog_family_badge ...>` invocation inside
  the `{:ok, ...}` branch is removed. The descriptor's `display_name` is still
  shown.
- `CatalogIndexLive`: `Family` column removed from the databases table (both
  `<thead>` and `<tbody>`).
- `CatalogDatabaseShowLive`: `<.catalog_family_badge family={@database.catalog_family} />`
  removed from the page header; `Family` column removed from the revision
  history table.
- `CatalogRevisionShowLive`: `<.catalog_family_badge family={@revision.catalog_family} />`
  removed from the page header.

After these edits, `catalog_family_badge/1` has no callers. Deleting the
function (and its helpers) is preferable to leaving dead code.

## Files Touched

Edited:

- `apps/cadence_web/lib/cadence_web/router.ex` — add route
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex` — drop
  upload card + Family column, add CTA button
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex`
  — toggleable "Add revision" reveal, drop Family badge and column
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_revision_show_live.ex`
  — drop Family badge from header
- `apps/cadence_web/lib/cadence_web/live/catalog/components.ex` — delete
  `catalog_family_badge/1` + helpers; remove family badge from
  `detected_preview/1`

Created:

- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_new_live.ex`

Test updates:

- `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`
  — upload-flow assertions move to the new page test. Index test covers: list
  rendering without Family column, presence of `+ New database` link pointing
  at `/catalog/new`, empty-state CTA.
- `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs`
  — add coverage for: form hidden on initial render, click `+ Add revision`
  reveals the form, click `Cancel` hides it, submit still navigates to import
  run detail. Remove Family column assertions.
- `apps/cadence_web/test/cadence_web/live/catalog/catalog_revision_show_live_test.exs`
  — remove Family badge assertion.

Test created:

- `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_new_live_test.exs`
  — full upload flow: form renders, file upload + detection, submit creates
  database and starts import, redirect to import run detail, failure branch
  flashes an error.

## Test IDs

Preserved:

- `#catalog-database-list`
- `#catalog-revision-upload-form`
- `#catalog-revision-history`
- `#catalog-import-attempts`
- `#catalog-runtime-usage-summary`

Moved:

- `#catalog-database-form` moves from the index to `CatalogDatabaseNewLive`.

Added:

- `#add-revision-toggle` on the button that opens/closes the add-revision
  reveal.
- `#new-database-link` on the `+ New database` primary button on the catalog
  index.

## Behavior Matrix

| Surface | Before | After |
|---|---|---|
| Catalog index: upload form | Always expanded card | `+ New database` button → `/catalog/new` |
| Catalog index: Family column | Visible | Removed |
| New database page | Does not exist | Dedicated LiveView |
| Database detail: add-revision form | Always expanded card | Hidden by default; `+ Add revision` toggles |
| Database detail: Family badge in header | Visible | Removed |
| Database detail: Family column in revisions | Visible | Removed |
| Revision detail: Family badge | Visible | Removed |
| Importer detection | Shown with family badge | Shown without family badge |
| Domain `catalog_family` | Persisted, validated | Unchanged |

## Risks

- Moving upload logic duplicates a small amount of code between
  `CatalogDatabaseNewLive` (create new database) and
  `CatalogDatabaseShowLive` (add revision to existing). This is acceptable —
  they are different flows (one creates a database, one does not) and the
  overlap is the `consume_uploaded_entries` + `Artifact.build_from_upload`
  shape, which is already small.
- Hook-based toggles invite regressions where leftover upload entries persist
  after `Cancel`. Tests must cover the cancel path explicitly.

## Rollout

Single PR. No data migration, no feature flag. Tests gate the change.
