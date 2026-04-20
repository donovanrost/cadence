# Design: Command & Telemetry Catalog Upload UI

- Status: draft
- Created: 2026-04-19
- Scope: first mission-scoped web UI for catalog artifact upload, import runs, and read-only snapshot summaries
- Related ADRs: [008](../../decisions/008-multi-format-catalog-import-architecture.md), [009](../../decisions/009-canonical-telemetry-catalog-model.md), [010](../../decisions/010-canonical-command-catalog-model.md)

## Summary

Cadence already has the backend substrate for multi-format catalog import: `Cadence.Catalog` persists artifacts, runs importers asynchronously via `Cadence.Jobs`, and produces canonical telemetry and command snapshots. The only importer today is `Cadence.Catalog.Importers.CadenceYamlDatabase` (catalog family `:combined`, YAML media types).

What does not exist yet is any web UI for this subsystem. Operators cannot upload a C&T database from the browser, cannot see import diagnostics, and cannot confirm what parsed. This design adds the first mission-scoped catalog web surface: upload → import run → snapshot summary.

The design deliberately keeps snapshot detail to summary counts only. A richer catalog explorer with fuzzy search over individual parameters and commands is planned as a follow-on surface.

## Goals

- Upload a command-and-telemetry database artifact through the browser.
- Automatically detect which registered importer should handle the uploaded file.
- Kick off an import run as part of the upload action (one click, not two).
- Show import-run status live as the async job progresses.
- Surface importer diagnostics clearly enough to decide whether the snapshot is usable.
- Show read-only summary counts for the telemetry and command snapshots produced by each run.
- Preserve provenance links so an operator can navigate snapshot → import run → artifact.

## Non-goals

- Full catalog explorer (per-parameter, per-command drill-in, fuzzy search). Planned separately.
- The "materialize runtime" / governance activation action. Lives with ADR-011 follow-on.
- Additional importer families (XTCE, EDS, CSV). The registry and detection hooks accommodate them; implementation is out of scope.
- Fine-grained catalog authorization (`:catalog_admin` capability, etc.). Follows the established `# TODO: finer capability` pattern from `mission_new_live` and `spacecraft_new_live` until the web-side capability framework matures.
- Editing snapshots. Snapshots are derived artifacts; they are re-produced by re-running an importer.

## Architecture

### Backend changes

All additions are small and targeted; the catalog import pipeline itself is unchanged.

#### 1. `Cadence.Catalog.Registry.detect_importer/2`

```elixir
@spec detect_importer(filename :: binary(), media_type :: binary() | nil) ::
        {:ok, importer_registration()} | {:error, :no_matching_importer}
```

- Matches first by `media_type` against `descriptor.media_types`.
- Falls back to filename extension, derived from media types at registration time (e.g. `application/yaml` → `.yaml`, `.yml`). The mapping lives in a private `extensions_for_media_types/1` helper in `Registry`.
- Returns `{:error, :no_matching_importer}` when nothing matches.
- When multiple importers match, the first in registry order wins; the registry is already sorted deterministically by catalog family + importer key.

#### 2. `Cadence.Catalog.Events` (new module)

Central authority for PubSub topic names and event shapes. Nothing else constructs catalog topic strings.

```elixir
defmodule Cadence.Catalog.Events do
  @moduledoc "PubSub topics and broadcast helpers for catalog import lifecycle."

  alias Cadence.Catalog.ImportRun

  @pubsub Cadence.PubSub  # whatever the existing pubsub server is

  @spec import_runs_topic(mission_id :: binary()) :: binary()
  @spec import_run_topic(mission_id :: binary(), import_run_id :: binary()) :: binary()

  @spec broadcast_started(ImportRun.t()) :: :ok
  @spec broadcast_updated(ImportRun.t()) :: :ok
  @spec broadcast_completed(ImportRun.t()) :: :ok
  @spec broadcast_failed(ImportRun.t()) :: :ok

  @spec subscribe_import_runs(mission_id :: binary()) :: :ok
  @spec subscribe_import_run(mission_id :: binary(), import_run_id :: binary()) :: :ok
end
```

Topic format:

- `"catalog:mission:#{mission_id}:import_runs"` — mission-wide index stream.
- `"catalog:mission:#{mission_id}:import_run:#{import_run_id}"` — per-run detail stream.

Message shapes:

- `{:import_run_started, %ImportRun{}}`
- `{:import_run_updated, %ImportRun{}}` (non-terminal transitions; reserved for future use such as progress counters)
- `{:import_run_completed, %ImportRun{}}`
- `{:import_run_failed, %ImportRun{}}`

Both topics receive the same events (index-level subscribers get the broadcast to the `import_runs` topic, detail-level subscribers get the broadcast to the `import_run:id` topic; the broadcast helpers publish to both).

#### 3. `Cadence.Catalog` broadcast sites

Only two call sites need to change:

- `insert_run/1` — on `{:ok, run}`, call `Events.broadcast_started(run)`.
- `update_run/1` — on `{:ok, run}`, call `Events.broadcast_completed/1` or `Events.broadcast_failed/1` when the run is in a terminal state (`:completed` / `:failed`). For non-terminal updates, call `Events.broadcast_updated/1`.

No changes to `Cadence.Jobs` wiring or to individual importer modules.

### Web layer

#### New `live_session :catalog`

```elixir
live_session :catalog,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission},
    {CadenceWeb.UserAuth, :attach_user_menu}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id/catalog", CatalogIndexLive, :index
  live "/missions/:mission_id/catalog/artifacts/:artifact_id", CatalogArtifactShowLive, :show
  live "/missions/:mission_id/catalog/imports/:import_run_id", CatalogImportRunShowLive, :show
  live "/missions/:mission_id/catalog/telemetry_snapshots/:snapshot_id", CatalogTelemetrySnapshotShowLive, :show
  live "/missions/:mission_id/catalog/command_snapshots/:snapshot_id", CatalogCommandSnapshotShowLive, :show
end
```

Plus one controller route (outside the live_session, still mission-scoped) for artifact download:

```elixir
get "/missions/:mission_id/catalog/artifacts/:artifact_id/download",
    CatalogArtifactDownloadController, :show
```

The download route goes through the same `:require_authenticated_scope` browser pipeline and a `MissionAuth` plug-equivalent check (or equivalent helper used by other mission-scoped controllers in the app — to be confirmed during implementation by reading the existing mission-scoped controller pattern).

#### Sidebar

Add one nav item to `mission_sidebar.html.heex`, directly below Spacecraft:

```heex
<li :if={assigns[:current_mission]}>
  <.link navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
         class={[... standard nav item classes keyed on assigns[:nav_item] == :catalog ...]}>
    <span class="hero-circle-stack h-4 w-4 opacity-80 flex-shrink-0"></span>
    <span class="sidebar-label">Catalog</span>
  </.link>
</li>
```

All catalog LiveViews set `nav_item: :catalog` on mount.

### LiveView pages

All paths relative to `apps/cadence_web/lib/cadence_web/live/catalog/`.

#### `CatalogIndexLive` — `/missions/:mission_id/catalog`

Page layout:

1. **Upload card**
   - `allow_upload :artifact, accept: :any, max_entries: 1, max_file_size: 50 * 1024 * 1024`
   - In the `"validate"` event, when an entry is present, call `Registry.detect_importer(entry.client_name, entry.client_type)` and store the result in `:detected_importer` (either the descriptor or an error reason).
   - Render: file drop zone, preview block showing the detected importer display name + catalog family badge (or a red error banner with the filename, its type, and the list of accepted media types), and a "Upload & import" submit button disabled unless detection succeeded.
   - In `"save"`: `consume_uploaded_entries/3` to read bytes, build `%Artifact{}` with `source_artifact: bytes` (or `%{"yaml" => bytes}` depending on the importer convention — see open question below), call `Catalog.persist_artifact/2`, then `Catalog.start_import_run/5` with `requested_by: %{user_id: scope.user.id, email: scope.user.email}`, then `push_navigate` to the import run show page.
   - Errors at `persist_artifact` or `start_import_run` step: put flash, stay on page. `detect_importer` returning `:no_matching_importer` prevents submit and renders the inline banner.

2. **Artifacts table**
   - Columns: Name, Format, Family, Uploaded, Uploaded by, Latest run
   - Loaded via `Catalog.list_artifacts(org, mission)`.
   - Latest-run column pulls the most recent `ImportRun` for each artifact via a batched query (to be added as a helper on `Cadence.Catalog` — `latest_import_run_by_artifact/3` returning a map `artifact_id => ImportRun`).
   - Row actions via `<.action_menu>`: "View artifact", "View latest import run", "Re-run importer".
   - Subscribes to `Events.subscribe_import_runs(mission_id)` on mount (when connected); updates the latest-run cell on any received event.

Empty state: card with "No artifacts yet" + a hint arrow toward the upload card.

#### `CatalogArtifactShowLive` — `/catalog/artifacts/:artifact_id`

- Fetch artifact via `Catalog.fetch_artifact/3`; 404 on not found.
- Metadata card: name, format_key, media_type, catalog_family, content_sha256 (truncated + copy button), size, uploaded_by, uploaded_at.
- Actions: "Download original" (links to the controller route), "Re-import" (calls `Catalog.start_import_run/5` with the same `importer_key`, then `push_navigate` to the new run).
- Import runs table for this artifact, loaded via `Catalog.list_import_runs(org, mission, artifact_id: id)`. Columns: status, started_at, duration, diagnostic counts, snapshot links, row action menu with "View run".
- Subscribes to the index topic; updates row status live.

#### `CatalogImportRunShowLive` — `/catalog/imports/:import_run_id`

- Fetch run via `Catalog.fetch_import_run/3`; 404 on not found.
- Status header: importer display name, status badge, timeline (started_at → completed_at/failed_at or live "running…"), requested_by.
- Diagnostics section: grouped by severity. Each diagnostic shows severity tag, code (if any), message, and structured context (rendered as key/value chips).
- When `status == :completed`: two snapshot summary cards side-by-side.
  - Telemetry snapshot card — counts for packets, points, types, units, enumerations, calibrations. Links to telemetry snapshot page.
  - Command snapshot card — counts for definitions, arguments, argument types, verifiers, enumerations. Links to command snapshot page.
  - Counts come from `Catalog.list_telemetry_snapshots(..., import_run_id: id)` and the corresponding command call, then reading simple `length/1` on the snapshot collection fields.
- When `status == :failed`: failure reason block rendering `run.failure_reason` — a prefix for known atom tuples (e.g. `{:job_enqueue_failed, _}`, `{:exception, msg}`) and a fallback `inspect/1` for anything else.
- Back-links to artifact.
- Subscribes to `Events.subscribe_import_run(mission_id, run_id)` on mount; re-fetches on any event.

#### `CatalogTelemetrySnapshotShowLive` — `/catalog/telemetry_snapshots/:snapshot_id`

- Fetch via `Catalog.fetch_telemetry_snapshot/3`; 404 on not found.
- Header: snapshot_id, import run link, artifact link, generated_at.
- Summary count cards (grid): packets, points, types, units, enumerations, calibrations.
- Placeholder footer: "Individual-item views are coming in a future catalog explorer."

#### `CatalogCommandSnapshotShowLive` — `/catalog/command_snapshots/:snapshot_id`

Same shape as the telemetry version, with command-family counts (definitions, arguments, argument types, verifiers, enumerations).

#### `CatalogArtifactDownloadController`

Single `show/2` action. Authorizes mission scope, calls `Catalog.fetch_artifact/3`, serves the raw bytes with:

- `Content-Type: artifact.media_type || "application/octet-stream"`
- `Content-Disposition: attachment; filename="artifact.artifact_name"`

For importers whose `source_artifact` is a structured map (like `%{"yaml" => bytes}`), the controller extracts the primary payload. A small helper in `Cadence.Catalog.Artifact` (e.g. `download_payload/1`) centralizes this so importer-specific knowledge stays out of the web layer.

### Shared components

`apps/cadence_web/lib/cadence_web/live/catalog/components.ex`:

- `catalog_family_badge/1` — colored badge for `:telemetry | :command | :combined`.
- `import_run_status_badge/1` — colored badge for `:pending | :running | :completed | :failed`.
- `diagnostic_list/1` — renders grouped diagnostics with severity tags.
- `snapshot_summary_card/1` — reusable count card; takes `title`, `icon`, `counts` (keyword list of label → integer), and optional `navigate` target.
- `upload_card/1` — the upload zone, extracted from `CatalogIndexLive` if the index render crosses 50 lines.

## Data flow

### Upload (happy path)

1. User selects file in the upload card.
2. `phx-change="validate"` fires; LiveView reads `entry.client_name` and `entry.client_type`, calls `Registry.detect_importer/2`, stores result in assigns.
3. Submit button becomes enabled when detection succeeds.
4. User clicks "Upload & import"; `phx-submit="save"`.
5. `consume_uploaded_entries/3` reads the binary.
6. LiveView builds an `%Artifact{}` (with detected importer's `format_key`, `catalog_family`, `media_type`; `source_artifact` shaped per importer convention).
7. `Catalog.persist_artifact/2` → `{:ok, artifact}`.
8. `Catalog.start_import_run/5` → `{:ok, run}` (job enqueued).
9. `push_navigate` to `/missions/:mission_id/catalog/imports/:import_run_id`.
10. Async: the job runs, `Catalog.update_run/1` broadcasts `:import_run_completed` (or `:import_run_failed`). The run show page re-fetches and re-renders.

### Failure modes and user-facing responses

| Failure | Handling |
|---|---|
| `Registry.detect_importer/2` returns `:no_matching_importer` | Inline red banner in upload card listing accepted formats; submit disabled. |
| Upload exceeds `max_file_size` | LiveView upload validation error rendered via `upload_errors/2` helper. |
| `Catalog.persist_artifact/2` → `{:error, changeset}` | Flash error with changeset message; stay on page. |
| `Catalog.persist_artifact/2` → `{:error, :catalog_artifact_not_found}` or similar | Flash a generic "Failed to save artifact" message with the reason inspected; stay on page. |
| `Catalog.start_import_run/5` → `{:error, reason}` (artifact already persisted) | Flash the reason; redirect to artifact detail so user can retry from there. |
| Async import run fails | Run status is `:failed`, PubSub broadcast fires, run detail page renders `failure_reason` + diagnostics. No flash (user is already on the run page or will navigate to it). |
| Snapshot fetch 404 | Standard not-found redirect back to catalog index with flash. |

### Authorization model

- All catalog routes sit inside `live_session :catalog`, which uses the same on_mount chain as `:mission`: organization scope + mission load + user menu.
- No capability check beyond mission load for this pass; add `# TODO: finer capability (:catalog_admin?)` comment at mount of each LiveView, matching established pattern.
- Download controller reuses the established mission-scoped browser controller pattern (details confirmed during implementation).

## Testing strategy

### Backend

- `Cadence.Catalog.RegistryTest` — add cases for `detect_importer/2`:
  - matches by media type
  - matches by filename extension when media type is absent/generic (`application/octet-stream`)
  - returns `:no_matching_importer` otherwise
  - when multiple importers could match, first in registry order wins
- `Cadence.Catalog.EventsTest` — topic names, broadcast helpers publish the correct shapes to both topics
- Extend the existing catalog tests (or add `Cadence.CatalogBroadcastsTest`) to assert PubSub messages fire on insert_run, completion, failure. Use `Phoenix.PubSub.subscribe/2` in test setup.
- `Cadence.Catalog.latest_import_run_by_artifact/3` — returns the most recent run per artifact, scoped to mission.

### Web

- `CadenceWeb.CatalogIndexLiveTest`
  - Renders upload card + empty state when no artifacts
  - Validate event with recognized file type: preview shows importer name, submit enabled
  - Validate event with unrecognized type: banner rendered, submit disabled
  - Upload & import happy path using a small in-memory YAML fixture: artifact persisted, run inserted, redirect to run detail
  - Artifact table updates live when a simulated `{:import_run_completed, run}` message is delivered
  - Scope enforcement: unauth redirect; other-organization mission denied
- `CadenceWeb.CatalogArtifactShowLiveTest`
  - Renders metadata correctly
  - "Re-import" action creates a new run and navigates to it
  - Import runs table updates on PubSub event
- `CadenceWeb.CatalogImportRunShowLiveTest`
  - Running state renders status, no snapshot cards
  - Simulated `{:import_run_completed, run}` flips UI: status badge + snapshot cards + summary counts
  - Simulated `{:import_run_failed, run}` flips UI: failure reason block, no snapshot cards
  - Diagnostics render grouped by severity
- `CadenceWeb.CatalogTelemetrySnapshotShowLiveTest` / `CadenceWeb.CatalogCommandSnapshotShowLiveTest`
  - Summary counts match fixture
  - Provenance back-links navigate correctly
- `CadenceWeb.CatalogArtifactDownloadControllerTest`
  - Authorized: 200, correct `Content-Type` and `Content-Disposition`, body matches `source_artifact`
  - Unauthorized / wrong mission: 404 or redirect

### Quality gates (per CLAUDE.md)

- `mix compile --warnings-as-errors`
- `mix credo --strict` — no new violations; leave it better than found
- `mix format` across touched files
- `cd apps/cadence && mix test` and `cd apps/cadence_web && mix test`

## File layout

```
apps/cadence/lib/cadence/catalog/
  events.ex                                  NEW
  registry.ex                                EDIT (add detect_importer/2)
  artifact.ex                                EDIT (add download_payload/1 helper)

apps/cadence/lib/cadence/catalog.ex          EDIT (broadcast on run transitions;
                                                   add latest_import_run_by_artifact/3)

apps/cadence/test/cadence/catalog/
  registry_test.exs                          EDIT
  events_test.exs                            NEW
  broadcasts_test.exs                        NEW (or extend existing catalog_test)

apps/cadence_web/lib/cadence_web/live/catalog/
  catalog_index_live.ex                      NEW
  catalog_artifact_show_live.ex              NEW
  catalog_import_run_show_live.ex            NEW
  catalog_telemetry_snapshot_show_live.ex    NEW
  catalog_command_snapshot_show_live.ex      NEW
  components.ex                              NEW

apps/cadence_web/lib/cadence_web/controllers/
  catalog_artifact_download_controller.ex    NEW

apps/cadence_web/lib/cadence_web/router.ex   EDIT (live_session + download route)
apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex   EDIT (nav item)

apps/cadence_web/test/cadence_web/live/catalog/
  catalog_index_live_test.exs                NEW
  catalog_artifact_show_live_test.exs        NEW
  catalog_import_run_show_live_test.exs      NEW
  catalog_telemetry_snapshot_show_live_test.exs  NEW
  catalog_command_snapshot_show_live_test.exs    NEW

apps/cadence_web/test/cadence_web/controllers/
  catalog_artifact_download_controller_test.exs  NEW
```

All LiveView files stay under 400 lines. Any render function over 50 lines gets extracted to a function component in `components.ex` before it crosses the line.

## Open questions / resolved during implementation

- **`source_artifact` shape on upload.** `CadenceYamlDatabase.extract_yaml_source/1` accepts raw binary, `%{"yaml" => bytes}`, or `%{yaml: bytes}`. The upload path will use raw binary (`source_artifact: bytes`) for the YAML importer. Future importers may need different shapes; the LiveView will build the artifact struct using a small per-importer shaping helper in `Cadence.Catalog.Artifact` (e.g. `build_from_upload/4`) to avoid the web layer encoding importer assumptions.
- **Download controller mission-scope helper.** The existing pattern for mission-scoped browser controllers will be confirmed at implementation time; if one does not exist, we reuse the LiveView `MissionAuth.load_mission` logic via a plug wrapper rather than duplicating it.
- **`Cadence.PubSub` server name.** The exact PubSub process name is confirmed by reading the application supervision tree during implementation; `Events` uses whatever is already configured.

## Follow-on work (not in this design)

- Catalog explorer: per-parameter and per-command detail pages with fuzzy search.
- Materialize runtime / activation action tied into ADR-011 governance.
- XTCE, EDS, and other importer families.
- Fine-grained catalog capabilities (`:catalog_admin` or equivalent) once the web-side capability framework lands.
- Artifact deletion / archival.
- Upload progress indicator for large files.
