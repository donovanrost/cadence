# Design: Catalog Database and Revision Library

- Status: superseded by ADR-020
- Created: 2026-04-20
- Scope: first-class mission-scoped catalog databases, immutable catalog revisions, and upload/import UX changes
- Related ADRs: [001](../../decisions/001-mission-scoped-runtime-and-selector-model.md), [008](../../decisions/008-multi-format-catalog-import-architecture.md), [009](../../decisions/009-canonical-telemetry-catalog-model.md), [010](../../decisions/010-canonical-command-catalog-model.md)

> Historical design record. Its separate command/telemetry snapshot model was
> removed by ADR-020 and must not be used as an implementation contract.

## Summary

Cadence currently persists uploaded catalog artifacts, import runs, and canonical
command/telemetry snapshots. Those pieces are sufficient for the first upload
UI, but they do not yet express the product concept operators need:

> A mission has a library of catalog databases, and each database has immutable
> revisions.

This design adds a first-class catalog library layer above the existing import
substrate:

1. catalog database
2. catalog revision
3. source artifact
4. import run
5. canonical command and telemetry snapshots
6. separate runtime binding/materialization

The catalog library answers "what mission definitions are available?" Runtime
binding answers "where does this revision apply?"

That separation is important for heterogeneous missions. The same APID can mean
different things for different spacecraft or source endpoints within one
mission. A catalog revision may define APID `42`, but APID `42` only gains
runtime meaning after a later source-scoped binding chooses that revision for a
specific runtime scope.

## Problem

The current UI and backend model expose low-level import objects directly:

- artifacts
- import runs
- telemetry snapshots
- command snapshots

That makes sense architecturally, but it is not the right primary product
language. Users generally think in terms of mission databases and versions:

- "Upload the FSW 3.7 database."
- "This is revision 2026-04-20 of the payload catalog."
- "Use the bus catalog for these spacecraft."
- "Compare the new catalog revision against the active one."

Without a first-class database/revision layer, Cadence has to infer library
meaning from artifact names, snapshot IDs, or import runs. That creates several
problems:

1. Upload history and revision history become the same thing, even though failed
   imports and retry attempts are not meaningful catalog revisions.
2. The UI has no durable parent object to show as a mission catalog library.
3. Revision labels, release notes, and operator intent have no natural home.
4. Runtime binding flows would need to point at snapshots or import runs
   directly, which leaks implementation detail.
5. Heterogeneous missions become harder to explain because "uploaded file" can
   be mistaken for "this applies to the spacecraft."

## Goals

- Introduce a mission-scoped catalog database as the durable library item.
- Introduce immutable catalog revisions as successful imported versions of a
  catalog database.
- Keep existing artifacts, import runs, and snapshots as provenance and
  implementation substrate.
- Support combined command-and-telemetry uploads that produce one revision with
  both canonical snapshot families.
- Keep runtime materialization and activation separate from library import.
- Give the UI a clear, operator-facing model without coupling it to low-level
  runtime internals.
- Preserve heterogeneous mission semantics: catalog revisions do not directly
  belong to spacecraft.

## Non-goals

- Designing the full source endpoint/runtime binding UI.
- Automatically activating or materializing a revision after import.
- Replacing canonical command or telemetry snapshot models.
- Building a full catalog item explorer for every command, point, packet, and
  type.
- Designing source-format-specific diffing beyond revision-level metadata.
- Supporting mutable catalog revisions. Revisions are immutable once created.
- Supporting mission-supplied executable plugins.

## Current State

The current backend already has the lower layers:

- `Cadence.Catalog.Artifact` preserves uploaded source material.
- `Cadence.Catalog.ImportRun` records an importer execution attempt.
- `Cadence.Catalog.Telemetry.Snapshot` stores immutable canonical telemetry
  output from an import run.
- `Cadence.Catalog.Command.Snapshot` stores immutable canonical command output
  from an import run.
- Runtime materialization can compile a telemetry snapshot into a generated
  governed binding set.

The current web UI exposes:

- a mission catalog upload page
- an artifact detail page
- import run status and diagnostics
- command and telemetry snapshot summary pages

What is missing is the library/revision layer above those details.

## Core Concept

Cadence should model the catalog as a mission-scoped library:

```text
Mission
  Catalog Database
    Catalog Revision
      Source Artifact
      Import Run
      Telemetry Snapshot
      Command Snapshot
```

The catalog database is the durable user-facing object. The revision is the
immutable imported version. The artifact/import/snapshot records remain the
audit trail and canonical data produced by import.

Runtime usage remains separate:

```text
Catalog Revision
  -> Runtime Binding / Materialization
     -> Active Binding Set
        -> Source-scoped runtime behavior
```

The UI should eventually let users choose a revision for runtime use, but the
revision itself does not imply where it is active.

## Domain Model

### CatalogDatabase

A catalog database is a logical library entry within a mission.

Examples:

- "Bus FSW 3.x Database"
- "Payload Science Catalog"
- "Demo Spacecraft MDB"
- "Camera Payload Packet Catalog"

Suggested fields:

- `catalog_database_id`
- `organization_id`
- `mission_id`
- `name`
- `slug` or `database_key`
- `description`
- `catalog_family`: `:telemetry | :command | :combined`
- `default_importer_key`
- `metadata`
- `created_by`
- `created_at`
- `updated_at`

The database is not immutable. Users may rename it, change the description, or
adjust metadata. Those edits do not change any revision.

### CatalogRevision

A catalog revision is an immutable imported version of a catalog database.

Suggested fields:

- `catalog_revision_id`
- `organization_id`
- `mission_id`
- `catalog_database_id`
- `revision_label`
- `revision_number`
- `artifact_id`
- `import_run_id`
- `telemetry_snapshot_id`
- `command_snapshot_id`
- `catalog_family`
- `content_sha256`
- `created_by`
- `created_at`
- `notes`
- `metadata`

The revision should only be created from a completed import that produced at
least one canonical snapshot. Failed import attempts remain import runs; they do
not become revisions.

Revision labels are user-facing and may come from:

- explicit user input
- source file metadata
- importer-detected database version
- fallback timestamp or monotonically increasing revision number

`revision_number` is system-assigned and monotonically increases per database.
`revision_label` is descriptive and operator-facing.

### Source Artifact

The existing artifact model remains the preserved uploaded source input.

An artifact may be associated with one catalog database during upload. The
artifact remains lower-level than the database/revision model because one
artifact is an input, not the durable library concept.

### Import Run

The existing import run model remains an execution attempt.

An import run should know which catalog database it was intended to update. This
can be done either by adding `catalog_database_id` to import runs or by linking
through the created revision once the run succeeds.

The stronger option is to add `catalog_database_id` to import runs so failed
runs still appear under the intended database.

### Canonical Snapshots

Canonical command and telemetry snapshots remain immutable imported outputs.

A catalog revision may reference:

- only a telemetry snapshot
- only a command snapshot
- both snapshots

This supports separate telemetry catalogs, separate command catalogs, and
combined command-and-telemetry databases.

### Runtime Binding

Runtime binding is deliberately not part of the catalog database or revision
model.

Runtime binding should reference catalog revisions or the compiled runtime
artifacts derived from those revisions. It should still choose a runtime scope
using the mission runtime model:

- mission default
- source endpoint
- spacecraft-derived source endpoint
- protocol/application scope
- future relay or service scope

The catalog library should be understandable without knowing those runtime
details.

## Persistence Model

### `catalog_databases`

Proposed columns:

- `catalog_database_id`, primary key string
- `organization_id`, string
- `mission_id`, string
- `name`, string
- `slug`, string
- `description`, text/string
- `catalog_family`, string
- `default_importer_key`, string nullable
- `created_by`, map/jsonb
- `metadata`, map/jsonb
- timestamps

Suggested indexes/constraints:

- unique `organization_id, mission_id, slug`
- index `organization_id, mission_id`
- index `organization_id, mission_id, catalog_family`

### `catalog_revisions`

Proposed columns:

- `catalog_revision_id`, primary key string
- `organization_id`, string
- `mission_id`, string
- `catalog_database_id`, string
- `revision_number`, integer
- `revision_label`, string
- `catalog_family`, string
- `artifact_id`, string
- `import_run_id`, string
- `telemetry_snapshot_id`, string nullable
- `command_snapshot_id`, string nullable
- `content_sha256`, string
- `created_by`, map/jsonb
- `notes`, string
- `metadata`, map/jsonb
- timestamps with `updated_at: false`

Suggested indexes/constraints:

- unique `catalog_database_id, revision_number`
- unique `catalog_database_id, revision_label` if labels are required to be
  unique per database
- index `organization_id, mission_id, catalog_database_id`
- index `artifact_id`
- index `import_run_id`
- index `telemetry_snapshot_id`
- index `command_snapshot_id`

The uniqueness rule for `revision_label` is a product choice. Unique labels are
cleaner for URLs and UI. Non-unique labels are friendlier to source metadata
that may repeat. If uncertain, prefer unique labels and auto-suffix conflicts.

### Existing Tables

Existing catalog tables should remain:

- `catalog_artifacts`
- `catalog_import_runs`
- `catalog_telemetry_snapshots`
- `catalog_command_snapshots`

Recommended additive changes:

- `catalog_artifacts.catalog_database_id`, nullable initially
- `catalog_import_runs.catalog_database_id`, nullable initially

Because Cadence has no active production missions yet, implementation can edit
the existing catalog migration instead of adding forward migrations, matching
the current development preference.

## Import Flow

### New Database Upload

1. User opens mission catalog library.
2. User chooses "Create catalog database".
3. User enters name, optional description, optional revision label.
4. User uploads a source artifact.
5. Cadence detects importer.
6. Cadence creates `CatalogDatabase`.
7. Cadence persists `CatalogArtifact` linked to the database.
8. Cadence starts `CatalogImportRun` linked to the database.
9. Importer creates canonical snapshot outputs.
10. On successful import, Cadence creates `CatalogRevision`.
11. UI navigates to the revision detail page.

If import fails, the database and failed import run remain visible. No revision
is created.

### Add Revision To Existing Database

1. User opens a catalog database.
2. User chooses "Add revision".
3. User uploads source artifact and optionally enters revision label/notes.
4. Cadence validates that the importer/catalog family is compatible with the
   database.
5. Cadence persists artifact and starts import run.
6. On success, Cadence creates the next immutable revision.

### Re-import Existing Artifact

Re-importing an artifact should usually create a new import run, not a new
revision by itself.

A revision should only be created when the user explicitly chooses to publish or
save the successful result as a revision, unless the upload flow already framed
the run as "add revision".

For the first implementation, the simpler behavior is acceptable:

- upload into a database always attempts to create a revision on success
- artifact-level "re-import" remains a diagnostic/developer action and does not
  create a new revision unless launched from the database revision flow

## UI Model

### Catalog Index

The mission catalog landing page should become a catalog database library.

Primary content:

- upload/create database call-to-action
- table or card list of catalog databases
- latest revision summary
- latest import status
- catalog family badge
- runtime usage summary placeholder

Suggested columns:

- Name
- Family
- Latest revision
- Latest import
- Runtime usage
- Updated
- Actions

The existing artifact table can move lower in the page as "Recent uploads" or
be moved into a database detail page.

### Catalog Database Detail

Shows one logical database.

Sections:

- database metadata
- latest revision summary
- add revision action
- revision history
- import attempts
- source artifacts
- runtime usage placeholder

Revision history should be the main operator surface. Import attempts are
secondary provenance.

### Catalog Revision Detail

Shows one immutable revision.

Sections:

- revision label and number
- source artifact link/download
- import run diagnostics
- command snapshot summary
- telemetry snapshot summary
- built-in telemetry compiler status
- custom application candidate packets
- runtime usage / materialization placeholder

This is the natural future place for:

- compare against previous revision
- use in runtime
- replay with this revision
- view catalog explorer

### Upload Form

The upload UI should ask:

- create a new catalog database, or add revision to existing database
- database name when creating new
- revision label
- optional notes
- source file

Importer detection can still be automatic. The user should not need to know
which importer module is used unless multiple importers match.

### Runtime Copy

Avoid wording that implies direct spacecraft ownership.

Prefer:

- "Available in mission catalog"
- "Add revision"
- "Use this revision in runtime"
- "Choose runtime scope"
- "No runtime bindings yet"

Avoid:

- "Assign catalog to spacecraft"
- "Spacecraft database"
- "APID belongs to spacecraft"

It is acceptable for the UI to include spacecraft-oriented affordances later,
but those should resolve to source endpoint/runtime scope selections under the
hood.

## Runtime Boundary

Catalog revisions should be selectable inputs to runtime materialization, but
they are not active by default.

Future runtime binding flow should make the user choose:

- catalog revision
- consumer/application family
- runtime scope
- selector policy
- activation target

For built-in telemetry, a friendly UI may present this as:

> Use revision `FSW 3.7` for telemetry from `Spacecraft Alpha`.

Internally, that should still become a source endpoint scoped binding against
the mission runtime model.

This keeps the UI approachable without making the backend assume homogeneous
APID meaning across the mission.

## Validation Rules

Suggested validation:

- database name is required
- database slug unique per mission
- catalog family is compatible with importer output
- revision label is required or generated
- revision number is monotonically assigned per database
- successful revision must reference at least one command or telemetry snapshot
- revision snapshot mission/org must match database mission/org
- revision artifact/import run mission/org must match database mission/org
- runtime materialization must not use a failed import run directly

Potential family compatibility rules:

- `:combined` database accepts combined importers and revisions with command,
  telemetry, or both outputs
- `:telemetry` database accepts telemetry-only outputs
- `:command` database accepts command-only outputs
- if a combined importer produces only one family, the result is allowed but
  surfaced in diagnostics

## API Surface

Suggested context functions:

```elixir
Catalog.list_databases(organization_id, mission_id, opts \\ [])
Catalog.fetch_database(organization_id, mission_id, catalog_database_id)
Catalog.create_database(organization_id, mission_id, attrs)
Catalog.update_database(organization_id, mission_id, catalog_database_id, attrs)

Catalog.list_revisions(organization_id, mission_id, catalog_database_id, opts \\ [])
Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id)
Catalog.latest_revision(organization_id, mission_id, catalog_database_id)

Catalog.start_revision_import(
  organization_id,
  mission_id,
  catalog_database_id,
  upload_attrs,
  opts \\ []
)
```

The existing lower-level functions should remain available for controllers,
tests, and diagnostic flows:

```elixir
Catalog.persist_artifact(...)
Catalog.start_import_run(...)
Catalog.fetch_catalog_telemetry_snapshot(...)
Catalog.fetch_catalog_command_snapshot(...)
```

The web UI should prefer the higher-level revision import function once it
exists.

## Events

Existing catalog import PubSub events can remain, but revision-level events will
make UI updates cleaner.

Suggested events:

- `{:catalog_database_created, database}`
- `{:catalog_database_updated, database}`
- `{:catalog_revision_created, revision}`
- `{:catalog_revision_import_started, database, run}`
- `{:catalog_revision_import_failed, database, run}`

The first implementation may continue to subscribe to import-run events and
refetch database/revision state after each update.

## Authorization

Use the existing mission-scoped authorization pattern for the first pass.

Catalog database creation, revision upload, and revision materialization should
eventually separate into distinct capabilities:

- catalog read
- catalog manage
- catalog import
- runtime materialize
- runtime activate

For now, match the current catalog UI approach and leave TODOs for finer-grained
authorization.

## Testing Strategy

### Backend

Add tests for:

- creating a catalog database
- enforcing database uniqueness per mission
- creating a revision from a successful combined import
- not creating a revision from a failed import
- listing revisions in descending revision number
- fetching latest revision
- ensuring revision org/mission matches artifact/import/snapshot org/mission
- preserving command and telemetry snapshot references on combined revisions

### Web

Add LiveView tests for:

- catalog index lists databases instead of only artifacts
- create database + upload form renders
- successful upload navigates to revision/import status flow
- database detail shows revision history
- revision detail links to artifact, import run, command snapshot, and telemetry
  snapshot when present
- failed import appears under database import attempts without creating a
  revision

Tests should use stable DOM IDs for the key new surfaces:

- `#catalog-database-list`
- `#catalog-database-form`
- `#catalog-revision-upload-form`
- `#catalog-revision-history`
- `#catalog-import-attempts`
- `#catalog-runtime-usage-summary`

## Rollout Plan

### Phase 1: Domain and Persistence

- Add `CatalogDatabase` domain struct.
- Add `CatalogRevision` domain struct.
- Add persistence schemas.
- Update catalog migration with new tables and optional foreign keys.
- Add context functions and tests.

### Phase 2: Import Integration

- Add `catalog_database_id` to artifact/import run creation flows.
- Add high-level `start_revision_import` function.
- Create revisions only after successful imports.
- Keep existing artifact/import/snapshot functions stable.

### Phase 3: UI Reshape

- Change catalog index from artifact-first to database-first.
- Add database detail page.
- Add revision detail page.
- Move artifact/import pages behind the database/revision experience.
- Preserve direct artifact/import pages for provenance and debugging.

### Phase 4: Runtime Binding Follow-On

- Add "Use this revision in runtime" affordance.
- Route to a separate runtime scope/materialization flow.
- Do not collapse this into catalog upload.

## Open Questions

1. Should a catalog database's `catalog_family` be fixed forever, or can it move
   from `:telemetry`/`:command` to `:combined` if later revisions include both?
2. Should revision labels be unique per database, or should only revision
   numbers be unique?
3. Should successful import automatically create a revision, or should users
   explicitly publish a successful import result as a revision?
4. Should failed import attempts be shown on the database detail page by
   default, or hidden behind "Import attempts"?
5. Should source artifact upload create the database before import starts, or
   should the database be created only after the first successful import?
6. Should runtime materialization reference catalog revisions directly, or
   continue to reference canonical snapshots while storing revision provenance?

## Recommendation

For the first implementation:

- create the database before import starts
- link artifacts and import runs to the database
- create revisions automatically after successful imports launched from the
  "add revision" flow
- require unique revision labels per database, auto-generating a label when the
  user leaves it blank
- keep failed import attempts visible on the database detail page
- leave runtime materialization as a separate flow that starts from a revision
  but still compiles into governed runtime artifacts

This gives operators the product model they expect while preserving the
architecture Cadence needs for heterogeneous missions.
