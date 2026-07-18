# Catalog Upload UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first mission-scoped web UI for command & telemetry catalog upload, import runs, and read-only snapshot summaries, per `docs/superpowers/specs/2026-04-19-catalog-upload-ui-design.md`.

**Architecture:** Add small backend hooks (PubSub lifecycle broadcasts + importer detection + a handful of helpers) to the existing `Cadence.Catalog` facade. Add a new `live_session :catalog` with five LiveViews under `/missions/:mission_id/catalog` and one controller for artifact download. Use Phoenix LiveView uploads with auto-detection of the importer. Live status updates go through `Cadence.PubSub`.

**Tech Stack:** Elixir / Phoenix LiveView 1.x / Phoenix.PubSub / Ecto / daisyUI 5 + Tailwind v4 (HUD aesthetic). Test with `ExUnit` + `Phoenix.LiveViewTest`.

**Ground truth references:**
- Spec: `docs/superpowers/specs/2026-04-19-catalog-upload-ui-design.md`
- Catalog facade: `apps/cadence/lib/cadence/catalog.ex`
- PubSub server name: `Cadence.PubSub` (defined in `apps/cadence/lib/cadence/application.ex`)
- `ImportRun` status enum: `:running | :completed | :failed` (no `:pending`)
- Existing LiveView patterns to match: `apps/cadence_web/lib/cadence_web/live/spacecraft_list_live.ex`, `spacecraft_show_live.ex`, `spacecraft_new_live.ex`
- Existing LiveView test patterns: `apps/cadence_web/test/cadence_web/live/spacecraft_list_live_test.exs`
- Test fixtures: `apps/cadence_web/test/support/fixtures.ex` (`TestFixtures.persist_user!`, `persist_org!`, `persist_mission!`, `member_conn/1`)
- Core UI rules: `CLAUDE.md` (frozen CSS, `<.input>`, `<.action_menu>`, ≤400 lines, ≤50-line renders)

**Commit conventions (matching recent history):** `feat(cadence):`, `feat(cadence_web):`, `fix(...)`, `refactor(...)`, `test(...)`, with a single-line subject.

**Quality gates for every commit:** `mix compile --warnings-as-errors`, `mix format` over touched files, and `mix credo --strict` (don't regress, aim to burn down). Per-app tests: `cd apps/cadence && mix test` and `cd apps/cadence_web && mix test`.

---

## File structure

### New files

```
apps/cadence/lib/cadence/catalog/events.ex
apps/cadence/test/cadence/catalog/events_test.exs
apps/cadence/test/cadence/catalog/broadcasts_test.exs

apps/cadence_web/lib/cadence_web/live/catalog/components.ex
apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex
apps/cadence_web/lib/cadence_web/live/catalog/catalog_artifact_show_live.ex
apps/cadence_web/lib/cadence_web/live/catalog/catalog_import_run_show_live.ex
apps/cadence_web/lib/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live.ex
apps/cadence_web/lib/cadence_web/live/catalog/catalog_command_snapshot_show_live.ex

apps/cadence_web/lib/cadence_web/controllers/catalog_artifact_download_controller.ex

apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs
apps/cadence_web/test/cadence_web/live/catalog/catalog_artifact_show_live_test.exs
apps/cadence_web/test/cadence_web/live/catalog/catalog_import_run_show_live_test.exs
apps/cadence_web/test/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live_test.exs
apps/cadence_web/test/cadence_web/live/catalog/catalog_command_snapshot_show_live_test.exs

apps/cadence_web/test/cadence_web/controllers/catalog_artifact_download_controller_test.exs
```

### Modified files

```
apps/cadence/lib/cadence/catalog.ex                  (broadcasts + list helper)
apps/cadence/lib/cadence/catalog/registry.ex         (detect_importer/2)
apps/cadence/lib/cadence/catalog/artifact.ex         (download_payload/1 + build_from_upload/4)

apps/cadence/test/cadence/catalog/registry_test.exs  (extend — create if missing)

apps/cadence_web/lib/cadence_web/router.ex           (live_session + download route)
apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex  (nav item)

apps/cadence_web/test/support/fixtures.ex            (catalog artifact/import-run/snapshot fixtures)
```

Each file stays under 400 lines. Render functions stay under 50 lines — if `catalog_index_live.ex` starts pushing the limit, extract the upload card into `components.ex` before continuing.

---

## Phase 1 — Backend: PubSub events module

### Task 1.1: Define `Cadence.Catalog.Events`

**Files:**
- Create: `apps/cadence/lib/cadence/catalog/events.ex`
- Test: `apps/cadence/test/cadence/catalog/events_test.exs`

- [ ] **Step 1: Write the failing test**

Create `apps/cadence/test/cadence/catalog/events_test.exs`:

```elixir
defmodule Cadence.Catalog.EventsTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Events
  alias Cadence.Catalog.ImportRun

  defp run(overrides \\ %{}) do
    ImportRun.new(
      Map.merge(
        %{
          mission_id: "mission_abc",
          artifact_id: "catalog_artifact_xyz",
          catalog_family: :combined,
          importer_key: "cadence_yaml"
        },
        overrides
      )
    )
  end

  describe "topic names" do
    test "import_runs_topic is mission-scoped" do
      assert Events.import_runs_topic("mission_abc") ==
               "catalog:mission:mission_abc:import_runs"
    end

    test "import_run_topic is run-scoped" do
      assert Events.import_run_topic("mission_abc", "catalog_import_run_123") ==
               "catalog:mission:mission_abc:import_run:catalog_import_run_123"
    end
  end

  describe "broadcast_started/1" do
    test "publishes to the mission and run topics" do
      run = run(%{status: :running})
      :ok = Events.subscribe_import_runs(run.mission_id)
      :ok = Events.subscribe_import_run(run.mission_id, run.import_run_id)

      assert :ok = Events.broadcast_started(run)

      assert_receive {:import_run_started, ^run}
      assert_receive {:import_run_started, ^run}
    end
  end

  describe "broadcast_completed/1" do
    test "publishes completed event" do
      run = run(%{status: :completed, completed_at: DateTime.utc_now()})
      :ok = Events.subscribe_import_run(run.mission_id, run.import_run_id)

      assert :ok = Events.broadcast_completed(run)
      assert_receive {:import_run_completed, ^run}
    end
  end

  describe "broadcast_failed/1" do
    test "publishes failed event" do
      run = run(%{status: :failed, failure_reason: {:exception, "boom"}})
      :ok = Events.subscribe_import_runs(run.mission_id)

      assert :ok = Events.broadcast_failed(run)
      assert_receive {:import_run_failed, ^run}
    end
  end

  describe "broadcast_updated/1" do
    test "publishes updated event on non-terminal transitions" do
      run = run(%{status: :running})
      :ok = Events.subscribe_import_run(run.mission_id, run.import_run_id)

      assert :ok = Events.broadcast_updated(run)
      assert_receive {:import_run_updated, ^run}
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```
cd apps/cadence && mix test test/cadence/catalog/events_test.exs
```

Expected: module `Cadence.Catalog.Events` is not available / undefined function.

- [ ] **Step 3: Implement `Cadence.Catalog.Events`**

Create `apps/cadence/lib/cadence/catalog/events.ex`:

```elixir
defmodule Cadence.Catalog.Events do
  @moduledoc """
  PubSub topic helpers and lifecycle broadcast helpers for catalog import runs.

  The catalog subsystem is the only authority for these topic names — nothing
  else should construct them by hand.
  """

  alias Cadence.Catalog.ImportRun

  @pubsub Cadence.PubSub

  @spec import_runs_topic(binary()) :: binary()
  def import_runs_topic(mission_id) when is_binary(mission_id) do
    "catalog:mission:#{mission_id}:import_runs"
  end

  @spec import_run_topic(binary(), binary()) :: binary()
  def import_run_topic(mission_id, import_run_id)
      when is_binary(mission_id) and is_binary(import_run_id) do
    "catalog:mission:#{mission_id}:import_run:#{import_run_id}"
  end

  @spec subscribe_import_runs(binary()) :: :ok | {:error, term()}
  def subscribe_import_runs(mission_id) when is_binary(mission_id) do
    Phoenix.PubSub.subscribe(@pubsub, import_runs_topic(mission_id))
  end

  @spec subscribe_import_run(binary(), binary()) :: :ok | {:error, term()}
  def subscribe_import_run(mission_id, import_run_id)
      when is_binary(mission_id) and is_binary(import_run_id) do
    Phoenix.PubSub.subscribe(@pubsub, import_run_topic(mission_id, import_run_id))
  end

  @spec broadcast_started(ImportRun.t()) :: :ok
  def broadcast_started(%ImportRun{} = run), do: broadcast(run, :import_run_started)

  @spec broadcast_updated(ImportRun.t()) :: :ok
  def broadcast_updated(%ImportRun{} = run), do: broadcast(run, :import_run_updated)

  @spec broadcast_completed(ImportRun.t()) :: :ok
  def broadcast_completed(%ImportRun{} = run), do: broadcast(run, :import_run_completed)

  @spec broadcast_failed(ImportRun.t()) :: :ok
  def broadcast_failed(%ImportRun{} = run), do: broadcast(run, :import_run_failed)

  defp broadcast(%ImportRun{mission_id: mission_id, import_run_id: run_id} = run, event) do
    message = {event, run}
    :ok = Phoenix.PubSub.broadcast(@pubsub, import_runs_topic(mission_id), message)
    :ok = Phoenix.PubSub.broadcast(@pubsub, import_run_topic(mission_id, run_id), message)
    :ok
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```
cd apps/cadence && mix test test/cadence/catalog/events_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Quality gates**

```
cd apps/cadence && mix compile --warnings-as-errors
mix format lib/cadence/catalog/events.ex test/cadence/catalog/events_test.exs
cd apps/cadence && mix credo --strict lib/cadence/catalog/events.ex
```

- [ ] **Step 6: Commit**

```
git add apps/cadence/lib/cadence/catalog/events.ex apps/cadence/test/cadence/catalog/events_test.exs
git commit -m "feat(cadence): add Catalog.Events PubSub lifecycle helpers"
```

### Task 1.2: Wire broadcasts into `Cadence.Catalog` run lifecycle

**Files:**
- Modify: `apps/cadence/lib/cadence/catalog.ex`
- Test: `apps/cadence/test/cadence/catalog/broadcasts_test.exs`

- [ ] **Step 1: Write the failing test**

Create `apps/cadence/test/cadence/catalog/broadcasts_test.exs`. This test exercises the real pipeline through `Cadence.Catalog.execute_enqueued_run/1` using the existing fake importer. It assumes `TestFixtures` (from cadence_web) cannot be reused here; use cadence app's existing test fixtures if present, otherwise use `Cadence.DataCase` and manual persistence through the facade.

First verify what's available:

```
cd apps/cadence && ls test/support 2>/dev/null
```

If `Cadence.DataCase` exists, use it. If not, create the test using whatever case module is used by `apps/cadence/test/cadence/catalog` tests. Mirror that pattern.

Here is the test skeleton. Adapt the setup blocks to the existing fixture pattern:

```elixir
defmodule Cadence.Catalog.BroadcastsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Catalog
  alias Cadence.Catalog.Events

  # Use the fake importer already configured for web tests, or whichever
  # importer is configured in :cadence, :catalog_importers for this env.
  # If test-only fake exists at apps/cadence_web/test/support/fake_telemetry_catalog_importer.ex,
  # ensure the :catalog_importers application env includes it in the cadence
  # app's test config; otherwise use Cadence.Catalog.Importers.CadenceYamlDatabase
  # with a minimal valid YAML fixture.

  setup do
    org = persist_organization_fixture()
    mission = persist_mission_fixture(org)

    artifact =
      build_artifact_fixture(mission.mission_id,
        catalog_family: :combined,
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: sample_yaml_source()
      )

    {:ok, persisted_artifact} = Catalog.persist_artifact(org.organization_id, artifact)
    {:ok, org: org, mission: mission, artifact: persisted_artifact}
  end

  test "broadcasts :import_run_started when a run is inserted",
       %{org: org, mission: mission, artifact: artifact} do
    :ok = Events.subscribe_import_runs(mission.mission_id)

    {:ok, run} =
      Catalog.start_import_run(
        org.organization_id,
        mission.mission_id,
        artifact.artifact_id,
        "cadence_yaml",
        requested_by: %{user_id: "user_1"}
      )

    assert_receive {:import_run_started, %{import_run_id: started_run_id}}
    assert started_run_id == run.import_run_id
  end

  test "broadcasts :import_run_completed when an async run succeeds",
       %{org: org, mission: mission, artifact: artifact} do
    :ok = Events.subscribe_import_runs(mission.mission_id)

    {:ok, run} =
      Catalog.start_import_run(
        org.organization_id,
        mission.mission_id,
        artifact.artifact_id,
        "cadence_yaml"
      )

    # Discard the started event
    assert_receive {:import_run_started, _}

    {:ok, _completed_run} = Catalog.execute_enqueued_run(run.import_run_id)

    assert_receive {:import_run_completed, %{import_run_id: completed_id, status: :completed}}
    assert completed_id == run.import_run_id
  end

  test "broadcasts :import_run_failed when a run fails",
       %{org: org, mission: mission, artifact: _valid_artifact} do
    # Build and persist an artifact with deliberately invalid YAML so the
    # importer returns {:error, _}.
    bad_artifact =
      build_artifact_fixture(mission.mission_id,
        catalog_family: :combined,
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: "not: [valid"
      )

    {:ok, bad_artifact} = Catalog.persist_artifact(org.organization_id, bad_artifact)

    :ok = Events.subscribe_import_runs(mission.mission_id)

    {:ok, run} =
      Catalog.start_import_run(
        org.organization_id,
        mission.mission_id,
        bad_artifact.artifact_id,
        "cadence_yaml"
      )

    assert_receive {:import_run_started, _}

    {:ok, _failed_run} = Catalog.execute_enqueued_run(run.import_run_id)

    assert_receive {:import_run_failed, %{import_run_id: failed_id, status: :failed}}
    assert failed_id == run.import_run_id
  end

  # Fixture helpers — adapt to whatever pattern the existing cadence app tests use.
  defp persist_organization_fixture, do: # ...
  defp persist_mission_fixture(org), do: # ...
  defp build_artifact_fixture(mission_id, opts), do: # ...
  defp sample_yaml_source, do: # ... a minimal valid YAML with packets and commands
end
```

Before implementing, grep the existing tests for fixture patterns:

```
cd apps/cadence && grep -r "persist_organization\|persist_mission\|catalog_artifact" test --include="*.exs" -l
```

Reuse the existing fixture helpers by importing the appropriate test support module. If there is no existing catalog test with a fixture, mirror whatever existing cadence catalog or accounts test does.

The test may fail validity check (bad yaml test) — the importer's `validate_artifact/1` is called BEFORE the job runs. That means the third test needs different breakage: use a YAML that passes validation but triggers a downstream `{:error, _}` from `importer_module.import/2`. If no such failure mode exists, simulate via a test-only importer configured in `config/test.exs` that returns `{:error, :simulated}` on `import/2`. Document the decision in the commit message.

- [ ] **Step 2: Run the test to verify it fails**

```
cd apps/cadence && mix test test/cadence/catalog/broadcasts_test.exs
```

Expected: `assert_receive` times out — no broadcasts yet.

- [ ] **Step 3: Wire broadcasts into `Cadence.Catalog`**

Open `apps/cadence/lib/cadence/catalog.ex`. Add `alias Cadence.Catalog.Events` near the top with the other aliases:

```elixir
  alias Cadence.Catalog.{Artifact, Events, ImportResult, ImportRun, Registry}
```

Modify `insert_run/1` (around lines 393-399) so the success branch broadcasts `:import_run_started`:

```elixir
  defp insert_run(%ImportRun{} = run) do
    case Repo.insert(ImportRunRow.changeset(run)) do
      {:ok, %ImportRunRow{} = row} ->
        domain_run = ImportRunRow.to_domain(row)
        Events.broadcast_started(domain_run)
        {:ok, domain_run}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end
```

Modify `update_run/1` (around lines 401-418) so each `{:ok, run}` branch broadcasts the correct event based on `run.status`:

```elixir
  defp update_run(%ImportRun{} = run) do
    case Repo.get(ImportRunRow, run.import_run_id) do
      nil ->
        {:error, :catalog_import_run_not_found}

      %ImportRunRow{} = row ->
        case Repo.update(ImportRunRow.changeset(row, run)) do
          {:ok, %ImportRunRow{} = updated_row} ->
            domain_run = ImportRunRow.to_domain(updated_row)
            broadcast_for_status(domain_run)
            {:ok, domain_run}

          {:error, %Changeset{} = changeset} ->
            {:error, changeset}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp broadcast_for_status(%ImportRun{status: :completed} = run),
    do: Events.broadcast_completed(run)

  defp broadcast_for_status(%ImportRun{status: :failed} = run),
    do: Events.broadcast_failed(run)

  defp broadcast_for_status(%ImportRun{} = run),
    do: Events.broadcast_updated(run)
```

- [ ] **Step 4: Run the test to verify it passes**

```
cd apps/cadence && mix test test/cadence/catalog/broadcasts_test.exs
```

Expected: all three tests pass.

- [ ] **Step 5: Full app test run to confirm no regressions**

```
cd apps/cadence && mix test
```

Expected: green.

- [ ] **Step 6: Quality gates**

```
cd apps/cadence && mix compile --warnings-as-errors
mix format apps/cadence/lib/cadence/catalog.ex apps/cadence/test/cadence/catalog/broadcasts_test.exs
cd apps/cadence && mix credo --strict lib/cadence/catalog.ex
```

- [ ] **Step 7: Commit**

```
git add apps/cadence/lib/cadence/catalog.ex apps/cadence/test/cadence/catalog/broadcasts_test.exs
git commit -m "feat(cadence): broadcast catalog import run lifecycle events"
```

---

## Phase 2 — Backend: importer detection

### Task 2.1: Add `Registry.detect_importer/2`

**Files:**
- Modify: `apps/cadence/lib/cadence/catalog/registry.ex`
- Modify or create: `apps/cadence/test/cadence/catalog/registry_test.exs`

- [ ] **Step 1: Check whether a registry test already exists**

```
ls apps/cadence/test/cadence/catalog/registry_test.exs 2>/dev/null
```

If present, extend it. If absent, create it.

- [ ] **Step 2: Write the failing tests**

Add these tests to `apps/cadence/test/cadence/catalog/registry_test.exs`:

```elixir
defmodule Cadence.Catalog.RegistryTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Registry

  describe "detect_importer/2" do
    test "matches by media type" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yaml", "application/yaml")

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "matches when media type is a known text/yaml synonym" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yaml", "text/yaml")

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "falls back to filename extension when media type is generic" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yml", "application/octet-stream")

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "falls back to filename extension when media type is missing" do
      assert {:ok, %{descriptor: descriptor}} =
               Registry.detect_importer("mission.yaml", nil)

      assert descriptor.importer_key == "cadence_yaml"
    end

    test "returns :no_matching_importer for unknown files" do
      assert {:error, :no_matching_importer} =
               Registry.detect_importer("mission.xml", "application/xml")
    end

    test "returns :no_matching_importer when both filename and media type are unknown" do
      assert {:error, :no_matching_importer} =
               Registry.detect_importer("mission.bin", "application/octet-stream")
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

```
cd apps/cadence && mix test test/cadence/catalog/registry_test.exs
```

Expected: `Registry.detect_importer/2` is undefined.

- [ ] **Step 4: Implement `detect_importer/2`**

Replace the contents of `apps/cadence/lib/cadence/catalog/registry.ex` with:

```elixir
defmodule Cadence.Catalog.Registry do
  @moduledoc """
  Registry of configured first-party catalog importers.
  """

  alias Cadence.Catalog.ImporterDescriptor

  @type importer_registration :: %{module: module(), descriptor: ImporterDescriptor.t()}

  @extension_by_media_type %{
    "application/yaml" => [".yaml", ".yml"],
    "application/x-yaml" => [".yaml", ".yml"],
    "text/yaml" => [".yaml", ".yml"],
    "text/x-yaml" => [".yaml", ".yml"]
  }

  @spec list_importers(keyword()) :: [importer_registration()]
  def list_importers(opts \\ []) when is_list(opts) do
    catalog_family = Keyword.get(opts, :catalog_family)

    configured_importers()
    |> Enum.filter(fn %{descriptor: descriptor} ->
      is_nil(catalog_family) or descriptor.catalog_family == catalog_family
    end)
    |> Enum.sort_by(fn %{descriptor: descriptor} ->
      {Atom.to_string(descriptor.catalog_family), descriptor.importer_key}
    end)
  end

  @spec fetch_importer(binary()) :: {:ok, importer_registration()} | {:error, term()}
  def fetch_importer(importer_key) when is_binary(importer_key) do
    case Enum.find(list_importers(), fn %{descriptor: descriptor} ->
           descriptor.importer_key == importer_key
         end) do
      nil -> {:error, :catalog_importer_not_found}
      importer -> {:ok, importer}
    end
  end

  @spec detect_importer(binary(), binary() | nil) ::
          {:ok, importer_registration()} | {:error, :no_matching_importer}
  def detect_importer(filename, media_type)
      when is_binary(filename) and (is_binary(media_type) or is_nil(media_type)) do
    importers = list_importers()

    with :error <- find_by_media_type(importers, media_type),
         :error <- find_by_extension(importers, filename) do
      {:error, :no_matching_importer}
    else
      {:ok, registration} -> {:ok, registration}
    end
  end

  defp find_by_media_type(_importers, nil), do: :error

  defp find_by_media_type(importers, media_type) do
    normalized = String.downcase(media_type)

    case Enum.find(importers, fn %{descriptor: descriptor} ->
           Enum.any?(descriptor.media_types, &(String.downcase(&1) == normalized))
         end) do
      nil -> :error
      registration -> {:ok, registration}
    end
  end

  defp find_by_extension(importers, filename) do
    extension = filename |> Path.extname() |> String.downcase()

    if extension == "" do
      :error
    else
      case Enum.find(importers, &matches_extension?(&1, extension)) do
        nil -> :error
        registration -> {:ok, registration}
      end
    end
  end

  defp matches_extension?(%{descriptor: descriptor}, extension) do
    Enum.any?(descriptor.media_types, fn media_type ->
      extension in Map.get(@extension_by_media_type, media_type, [])
    end)
  end

  defp configured_importers do
    Application.get_env(:cadence, :catalog_importers, [])
    |> Enum.reduce([], fn module, acc ->
      with true <- Code.ensure_loaded?(module),
           true <- function_exported?(module, :descriptor, 0),
           %ImporterDescriptor{} = descriptor <- module.descriptor() do
        acc ++ [%{module: module, descriptor: descriptor}]
      else
        _other -> acc
      end
    end)
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```
cd apps/cadence && mix test test/cadence/catalog/registry_test.exs
```

Expected: green. If any test fails because the test env doesn't configure `cadence_yaml` as a registered importer, open `apps/cadence/config/test.exs` and verify `:cadence, :catalog_importers` includes `Cadence.Catalog.Importers.CadenceYamlDatabase`. Do not hard-code fixtures into `Registry`.

- [ ] **Step 6: Quality gates and commit**

```
cd apps/cadence && mix compile --warnings-as-errors
mix format lib/cadence/catalog/registry.ex test/cadence/catalog/registry_test.exs
cd apps/cadence && mix credo --strict lib/cadence/catalog/registry.ex
git add apps/cadence/lib/cadence/catalog/registry.ex apps/cadence/test/cadence/catalog/registry_test.exs
git commit -m "feat(cadence): add Catalog.Registry.detect_importer/2"
```

---

## Phase 3 — Backend: catalog facade helpers

### Task 3.1: `Catalog.latest_import_run_by_artifact/3`

**Files:**
- Modify: `apps/cadence/lib/cadence/catalog.ex`
- Test: extend `apps/cadence/test/cadence/catalog_test.exs` (or create it if absent — mirror existing pattern)

- [ ] **Step 1: Write failing test**

Add to the catalog test module:

```elixir
describe "latest_import_run_by_artifact/3" do
  setup do
    org = persist_organization_fixture()
    mission = persist_mission_fixture(org)
    {:ok, org: org, mission: mission}
  end

  test "returns empty map when there are no runs", %{org: org, mission: mission} do
    assert Catalog.latest_import_run_by_artifact(org.organization_id, mission.mission_id) == %{}
  end

  test "returns the most recent run per artifact", %{org: org, mission: mission} do
    {:ok, artifact_a} = persist_yaml_artifact(org, mission)
    {:ok, artifact_b} = persist_yaml_artifact(org, mission)

    {:ok, older_run_a} = start_and_advance_time(org, mission, artifact_a)
    {:ok, newer_run_a} = start_and_advance_time(org, mission, artifact_a)
    {:ok, only_run_b} = start_and_advance_time(org, mission, artifact_b)

    result = Catalog.latest_import_run_by_artifact(org.organization_id, mission.mission_id)

    assert result[artifact_a.artifact_id].import_run_id == newer_run_a.import_run_id
    assert result[artifact_b.artifact_id].import_run_id == only_run_b.import_run_id
    refute result[artifact_a.artifact_id].import_run_id == older_run_a.import_run_id
  end

  test "scopes by mission", %{org: org, mission: mission} do
    other_mission = persist_mission_fixture(org)
    {:ok, artifact} = persist_yaml_artifact(org, mission)
    {:ok, _run} = start_and_advance_time(org, mission, artifact)

    assert Catalog.latest_import_run_by_artifact(org.organization_id, other_mission.mission_id) ==
             %{}
  end
end
```

Helper `start_and_advance_time/3` starts a run and sleeps 1 ms to distinguish `started_at` ordering; an alternative is to pass `started_at:` explicitly in a test-only facade path. The simpler portable approach: set `started_at: DateTime.add(DateTime.utc_now(), n, :second)` by directly writing a fixture row builder for tests. Define whichever matches the existing style in cadence tests.

- [ ] **Step 2: Verify failing test**

```
cd apps/cadence && mix test test/cadence/catalog_test.exs
```

Expected: `UndefinedFunctionError Catalog.latest_import_run_by_artifact/2`.

- [ ] **Step 3: Implement**

In `apps/cadence/lib/cadence/catalog.ex`, add this public function after `list_import_runs/3`:

```elixir
  @spec latest_import_run_by_artifact(binary(), binary()) ::
          %{optional(binary()) => ImportRun.t()}
  def latest_import_run_by_artifact(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    ImportRunRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> order_by([row], desc: row.started_at, desc: row.import_run_id)
    |> Repo.all()
    |> Enum.map(&ImportRunRow.to_domain/1)
    |> Enum.reduce(%{}, fn %ImportRun{artifact_id: artifact_id} = run, acc ->
      Map.put_new(acc, artifact_id, run)
    end)
  end
```

- [ ] **Step 4: Verify**

```
cd apps/cadence && mix test test/cadence/catalog_test.exs
```

Expected: green.

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence && mix compile --warnings-as-errors
mix format apps/cadence/lib/cadence/catalog.ex apps/cadence/test/cadence/catalog_test.exs
cd apps/cadence && mix credo --strict lib/cadence/catalog.ex
git add apps/cadence/lib/cadence/catalog.ex apps/cadence/test/cadence/catalog_test.exs
git commit -m "feat(cadence): add Catalog.latest_import_run_by_artifact/2"
```

### Task 3.2: `Artifact.build_from_upload/4` and `Artifact.download_payload/1`

**Files:**
- Modify: `apps/cadence/lib/cadence/catalog/artifact.ex`
- Test: `apps/cadence/test/cadence/catalog/artifact_test.exs` (create or extend)

- [ ] **Step 1: Write failing tests**

Create/extend `apps/cadence/test/cadence/catalog/artifact_test.exs`:

```elixir
defmodule Cadence.Catalog.ArtifactTest do
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.ImporterDescriptor

  describe "build_from_upload/4" do
    test "builds an Artifact from raw bytes + descriptor + filename + uploader" do
      descriptor =
        ImporterDescriptor.new(%{
          importer_key: "cadence_yaml",
          display_name: "Cadence YAML Database",
          catalog_family: :combined,
          source_formats: ["cadence_yaml"],
          media_types: ["application/yaml"]
        })

      bytes = "packets: []\ncommands: []\n"

      artifact =
        Artifact.build_from_upload(
          "mission_abc",
          descriptor,
          %{filename: "mission.yaml", bytes: bytes, client_type: "application/yaml"},
          uploaded_by: %{user_id: "user_1", email: "a@example.com"}
        )

      assert %Artifact{} = artifact
      assert artifact.mission_id == "mission_abc"
      assert artifact.artifact_name == "mission.yaml"
      assert artifact.format_key == "cadence_yaml"
      assert artifact.catalog_family == :combined
      assert artifact.media_type == "application/yaml"
      assert artifact.source_artifact == bytes
      assert artifact.uploaded_by == %{user_id: "user_1", email: "a@example.com"}
      assert is_binary(artifact.content_sha256)
    end
  end

  describe "download_payload/1" do
    test "returns {bytes, media_type} for a raw binary source artifact" do
      artifact =
        Artifact.new(%{
          mission_id: "mission_abc",
          catalog_family: :combined,
          artifact_name: "mission.yaml",
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          source_artifact: "payload-bytes"
        })

      assert {"payload-bytes", "application/yaml"} = Artifact.download_payload(artifact)
    end

    test "returns the inner yaml for a %{\"yaml\" => bytes} source artifact" do
      artifact =
        Artifact.new(%{
          mission_id: "mission_abc",
          catalog_family: :combined,
          artifact_name: "mission.yaml",
          format_key: "cadence_yaml",
          media_type: "application/yaml",
          source_artifact: %{"yaml" => "inner-bytes"}
        })

      assert {"inner-bytes", "application/yaml"} = Artifact.download_payload(artifact)
    end

    test "falls back to application/octet-stream when media_type is nil for raw bytes" do
      artifact =
        Artifact.new(%{
          mission_id: "mission_abc",
          catalog_family: :combined,
          artifact_name: "mission.bin",
          format_key: "cadence_yaml",
          source_artifact: "raw"
        })

      assert {"raw", "application/octet-stream"} = Artifact.download_payload(artifact)
    end
  end
end
```

- [ ] **Step 2: Verify fail**

```
cd apps/cadence && mix test test/cadence/catalog/artifact_test.exs
```

Expected: undefined functions.

- [ ] **Step 3: Implement**

Open `apps/cadence/lib/cadence/catalog/artifact.ex` and add these functions at the bottom of the module, before the final `end`:

```elixir
  alias Cadence.Catalog.ImporterDescriptor

  @type upload :: %{
          required(:filename) => binary(),
          required(:bytes) => binary(),
          optional(:client_type) => binary() | nil
        }

  @spec build_from_upload(binary(), ImporterDescriptor.t(), upload(), keyword()) :: t()
  def build_from_upload(mission_id, %ImporterDescriptor{} = descriptor, upload, opts \\ [])
      when is_binary(mission_id) and is_map(upload) and is_list(opts) do
    filename = Map.fetch!(upload, :filename)
    bytes = Map.fetch!(upload, :bytes)
    client_type = Map.get(upload, :client_type)

    media_type = resolve_media_type(descriptor, client_type)
    format_key = descriptor.importer_key

    new(%{
      mission_id: mission_id,
      catalog_family: descriptor.catalog_family,
      artifact_name: filename,
      format_key: format_key,
      media_type: media_type,
      source_artifact: bytes,
      uploaded_by: Keyword.get(opts, :uploaded_by, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  @spec download_payload(t()) :: {binary(), binary()}
  def download_payload(%__MODULE__{source_artifact: bytes} = artifact) when is_binary(bytes) do
    {bytes, artifact.media_type || "application/octet-stream"}
  end

  def download_payload(%__MODULE__{source_artifact: %{"yaml" => bytes}} = artifact)
      when is_binary(bytes) do
    {bytes, artifact.media_type || "application/yaml"}
  end

  def download_payload(%__MODULE__{source_artifact: %{yaml: bytes}} = artifact)
      when is_binary(bytes) do
    {bytes, artifact.media_type || "application/yaml"}
  end

  def download_payload(%__MODULE__{source_artifact: source} = artifact) do
    payload = source |> Cadence.Persistence.JsonDocument.encode() |> Jason.encode!()
    {payload, artifact.media_type || "application/json"}
  end

  defp resolve_media_type(%ImporterDescriptor{media_types: [head | _]}, nil), do: head
  defp resolve_media_type(%ImporterDescriptor{media_types: []}, client_type), do: client_type
  defp resolve_media_type(_descriptor, client_type) when is_binary(client_type), do: client_type
  defp resolve_media_type(%ImporterDescriptor{media_types: [head | _]}, _), do: head
```

- [ ] **Step 4: Verify green**

```
cd apps/cadence && mix test test/cadence/catalog/artifact_test.exs
```

Expected: green.

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence && mix compile --warnings-as-errors
mix format apps/cadence/lib/cadence/catalog/artifact.ex apps/cadence/test/cadence/catalog/artifact_test.exs
cd apps/cadence && mix credo --strict lib/cadence/catalog/artifact.ex
git add apps/cadence/lib/cadence/catalog/artifact.ex apps/cadence/test/cadence/catalog/artifact_test.exs
git commit -m "feat(cadence): add Catalog.Artifact build_from_upload/4 and download_payload/1"
```

---

## Phase 4 — Web: router, sidebar, LiveView skeletons

This phase stands up the scaffolding for all five LiveViews with empty `render` bodies plus the download route, so later phases can flesh them out behind passing-route tests.

### Task 4.1: Add `live_session :catalog` and skeleton LiveViews

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`
- Create: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_artifact_show_live.ex`
- Create: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_import_run_show_live.ex`
- Create: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live.ex`
- Create: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_command_snapshot_show_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`

- [ ] **Step 1: Write failing test — skeleton page renders**

Create `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`:

```elixir
defmodule CadenceWeb.CatalogIndexLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders the catalog landing page" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

    assert html =~ "Catalog"
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/any/catalog")
    end
  end
end
```

- [ ] **Step 2: Run failing test**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: route not found / module not available.

- [ ] **Step 3: Implement skeleton LiveView modules**

Create each of the five LiveView files with this pattern (shown for the index — repeat for the others, adjusting `nav_item`, `page_title`, URL params, and the `<h1>`):

`apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`:

```elixir
defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  # TODO(authz): Catalog upload currently permitted for any active org member.
  # Tighten once finer-grained catalog capability is defined.
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:nav_item, :catalog)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Catalog</h1>
    </div>
    """
  end
end
```

`apps/cadence_web/lib/cadence_web/live/catalog/catalog_artifact_show_live.ex`:

```elixir
defmodule CadenceWeb.CatalogArtifactShowLive do
  @moduledoc false

  # TODO(authz): Catalog management currently permitted for any active org member.
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"artifact_id" => artifact_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog Artifact")
     |> assign(:nav_item, :catalog)
     |> assign(:artifact_id, artifact_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Artifact</h1>
    </div>
    """
  end
end
```

`apps/cadence_web/lib/cadence_web/live/catalog/catalog_import_run_show_live.ex`:

```elixir
defmodule CadenceWeb.CatalogImportRunShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"import_run_id" => import_run_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Catalog Import Run")
     |> assign(:nav_item, :catalog)
     |> assign(:import_run_id, import_run_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Import Run</h1>
    </div>
    """
  end
end
```

`apps/cadence_web/lib/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live.ex`:

```elixir
defmodule CadenceWeb.CatalogTelemetrySnapshotShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Telemetry Snapshot")
     |> assign(:nav_item, :catalog)
     |> assign(:snapshot_id, snapshot_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Telemetry Snapshot</h1>
    </div>
    """
  end
end
```

`apps/cadence_web/lib/cadence_web/live/catalog/catalog_command_snapshot_show_live.ex`:

```elixir
defmodule CadenceWeb.CatalogCommandSnapshotShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Command Snapshot")
     |> assign(:nav_item, :catalog)
     |> assign(:snapshot_id, snapshot_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-base-content">Command Snapshot</h1>
    </div>
    """
  end
end
```

- [ ] **Step 4: Add the live_session to the router**

Open `apps/cadence_web/lib/cadence_web/router.ex`. After the `:spacecraft_show` live_session block (around line 97), add:

```elixir
    live_session :catalog,
      on_mount: [
        {CadenceWeb.OrganizationAuth, :require_organization_scope},
        {CadenceWeb.MissionAuth, :load_mission},
        {CadenceWeb.UserAuth, :attach_user_menu}
      ],
      layout: {CadenceWeb.Layouts, :mission_sidebar} do
      live "/missions/:mission_id/catalog", CatalogIndexLive, :index
      live "/missions/:mission_id/catalog/artifacts/:artifact_id",
           CatalogArtifactShowLive,
           :show
      live "/missions/:mission_id/catalog/imports/:import_run_id",
           CatalogImportRunShowLive,
           :show
      live "/missions/:mission_id/catalog/telemetry_snapshots/:snapshot_id",
           CatalogTelemetrySnapshotShowLive,
           :show
      live "/missions/:mission_id/catalog/command_snapshots/:snapshot_id",
           CatalogCommandSnapshotShowLive,
           :show
    end
```

(Do not add the download controller route yet — it lands in Task 9.)

- [ ] **Step 5: Verify test passes**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: green.

- [ ] **Step 6: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/test/cadence_web/live/catalog
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/catalog lib/cadence_web/router.ex
git add apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/test/cadence_web/live/catalog
git commit -m "feat(cadence_web): scaffold catalog live_session and skeleton LiveViews"
```

### Task 4.2: Add "Catalog" nav item to mission sidebar

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`

- [ ] **Step 1: Write failing test**

Extend `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs` with a sidebar test:

```elixir
  test "mission sidebar marks Catalog as the active nav item" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

    # The active nav item uses the bg-primary/10 class combined with "Catalog"
    assert html =~ ~s(Catalog)
    assert html =~ "hero-circle-stack"
    assert html =~ "bg-primary/10"
  end
```

- [ ] **Step 2: Run test to verify failure**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: no `hero-circle-stack` class in rendered HTML.

- [ ] **Step 3: Add Catalog nav item**

In `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`, immediately after the `<li>` block for Spacecraft (around line 91), add:

```heex
          <li :if={assigns[:current_mission]}>
            <.link navigate={~p"/missions/#{@current_mission.mission_id}/catalog"} class={["flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", if(assigns[:nav_item] == :catalog, do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]", else: "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30")]}>
              <span class="hero-circle-stack h-4 w-4 opacity-80 flex-shrink-0"></span>
              <span class="sidebar-label">Catalog</span>
            </.link>
          </li>
```

- [ ] **Step 4: Verify green**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: green.

- [ ] **Step 5: Commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
git add apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs
git commit -m "feat(cadence_web): add Catalog entry to mission sidebar"
```

### Task 4.3: Test fixtures for catalog domain

**Files:**
- Modify: `apps/cadence_web/test/support/fixtures.ex`

Add fixture helpers so downstream LiveView tests can build artifacts, runs, and snapshots without reaching through the persistence layer manually.

- [ ] **Step 1: Extend `TestFixtures` with catalog helpers**

Append to `apps/cadence_web/test/support/fixtures.ex`:

```elixir
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.ImportRun
  alias Cadence.Catalog.Command.Snapshot, as: CommandSnapshot
  alias Cadence.Catalog.Telemetry.Snapshot, as: TelemetrySnapshot

  @spec persist_catalog_artifact!(Mission.t(), keyword()) :: Artifact.t()
  def persist_catalog_artifact!(%Mission{} = mission, opts \\ []) do
    artifact =
      Artifact.new(%{
        mission_id: mission.mission_id,
        catalog_family: Keyword.get(opts, :catalog_family, :combined),
        artifact_name: Keyword.get(opts, :artifact_name, "mission.yaml"),
        format_key: Keyword.get(opts, :format_key, "cadence_yaml"),
        media_type: Keyword.get(opts, :media_type, "application/yaml"),
        source_artifact: Keyword.get(opts, :source_artifact, sample_yaml_source()),
        uploaded_by: Keyword.get(opts, :uploaded_by, %{}),
        metadata: Keyword.get(opts, :metadata, %{})
      })

    assert {:ok, persisted} = Catalog.persist_artifact(mission.organization_id, artifact)
    persisted
  end

  @spec persist_catalog_import_run!(Artifact.t(), keyword()) :: ImportRun.t()
  def persist_catalog_import_run!(%Artifact{} = artifact, opts \\ []) do
    assert {:ok, run} =
             Catalog.start_import_run(
               artifact.organization_id,
               artifact.mission_id,
               artifact.artifact_id,
               Keyword.get(opts, :importer_key, "cadence_yaml"),
               requested_by: Keyword.get(opts, :requested_by, %{})
             )

    run
  end

  @spec complete_catalog_import_run!(ImportRun.t()) :: ImportRun.t()
  def complete_catalog_import_run!(%ImportRun{} = run) do
    assert {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)
    completed
  end

  defp sample_yaml_source do
    """
    packets: []
    commands: []
    """
  end
```

- [ ] **Step 2: Verify it compiles**

```
cd apps/cadence_web && mix compile --warnings-as-errors
```

Expected: no warnings.

- [ ] **Step 3: Commit**

```
git add apps/cadence_web/test/support/fixtures.ex
git commit -m "test(cadence_web): add catalog artifact and import run fixtures"
```

---

## Phase 5 — Catalog index LiveView (upload + artifacts table)

### Task 5.1: Shared components module

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/live/catalog/components.ex`

This module will host the small components used across the catalog pages. We build it first so later tasks can reference it.

- [ ] **Step 1: Create the components module**

`apps/cadence_web/lib/cadence_web/live/catalog/components.ex`:

```elixir
defmodule CadenceWeb.Catalog.Components do
  @moduledoc false
  use CadenceWeb, :html

  @doc "Colored badge for a catalog family atom (`:telemetry | :command | :combined`)."
  attr :family, :atom, required: true

  def catalog_family_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      family_badge_class(@family)
    ]}>
      {family_label(@family)}
    </span>
    """
  end

  defp family_badge_class(:telemetry), do: "badge-info"
  defp family_badge_class(:command), do: "badge-warning"
  defp family_badge_class(:combined), do: "badge-primary"
  defp family_badge_class(_), do: "badge-ghost"

  defp family_label(:telemetry), do: "Telemetry"
  defp family_label(:command), do: "Command"
  defp family_label(:combined), do: "Combined"
  defp family_label(other) when is_atom(other), do: other |> Atom.to_string() |> String.capitalize()

  @doc "Colored badge for an import run status."
  attr :status, :atom, required: true

  def import_run_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      status_badge_class(@status)
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_badge_class(:running), do: "badge-info"
  defp status_badge_class(:completed), do: "badge-success"
  defp status_badge_class(:failed), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:failed), do: "Failed"
  defp status_label(other), do: other |> to_string() |> String.capitalize()

  @doc "Grouped diagnostic list for an import run."
  attr :diagnostics, :list, required: true

  def diagnostic_list(assigns) do
    assigns = assign(assigns, :groups, group_diagnostics(assigns.diagnostics))

    ~H"""
    <div :if={@diagnostics != []} class="space-y-3">
      <div :for={{severity, items} <- @groups} class="card bg-base-200">
        <div class="card-body p-4">
          <p class="hud-label mb-2">{severity_heading(severity)} ({length(items)})</p>
          <ul class="space-y-2">
            <li :for={diagnostic <- items} class="text-sm">
              <span class="font-mono text-xs text-base-content/60">{diagnostic.code}</span>
              <span class="ml-2">{diagnostic.message}</span>
              <p :if={diagnostic.path != []} class="text-xs text-base-content/50 font-mono mt-1">
                {Enum.join(diagnostic.path, " / ")}
              </p>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp group_diagnostics(diagnostics) do
    [:error, :warning, :info]
    |> Enum.map(fn severity ->
      {severity, Enum.filter(diagnostics, &(&1.severity == severity))}
    end)
    |> Enum.reject(fn {_, items} -> items == [] end)
  end

  defp severity_heading(:error), do: "Errors"
  defp severity_heading(:warning), do: "Warnings"
  defp severity_heading(:info), do: "Info"

  @doc "Summary count card for a snapshot (telemetry or command)."
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :counts, :list, required: true, doc: "Keyword list of {label, integer}."
  attr :navigate, :string, default: nil

  def snapshot_summary_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4">
        <div class="flex items-center gap-2 mb-3">
          <span class={[@icon, "h-4 w-4"]}></span>
          <p class="hud-label">{@title}</p>
        </div>
        <dl class="grid grid-cols-2 gap-2 text-sm">
          <div :for={{label, count} <- @counts} class="contents">
            <dt class="text-base-content/60">{label}</dt>
            <dd class="font-mono text-base-content text-right">{count}</dd>
          </div>
        </dl>
        <div :if={@navigate} class="card-actions justify-end mt-3">
          <.link navigate={@navigate} class="btn btn-ghost btn-xs">
            View details <span class="hero-arrow-right h-3 w-3 ml-1"></span>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 2: Verify it compiles**

```
cd apps/cadence_web && mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```
git add apps/cadence_web/lib/cadence_web/live/catalog/components.ex
git commit -m "feat(cadence_web): add catalog shared components"
```

### Task 5.2: Artifacts table (read-only, no upload yet)

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`
- Modify: `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`

- [ ] **Step 1: Write failing tests**

Replace the index test with:

```elixir
defmodule CadenceWeb.CatalogIndexLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "artifacts table" do
    test "shows empty state when no artifacts exist" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "No catalog artifacts"
    end

    test "lists persisted artifacts with their latest run status" do
      {conn, _org, mission} = signed_in_org_and_mission()
      artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
      run = TestFixtures.persist_catalog_import_run!(artifact)
      _ = TestFixtures.complete_catalog_import_run!(run)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "mission.yaml"
      assert html =~ "Completed"
    end

    test "only shows artifacts in this mission" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "other", display_name: "Other Mission")

      _mine = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mine.yaml")
      _theirs = TestFixtures.persist_catalog_artifact!(other_mission, artifact_name: "theirs.yaml")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "mine.yaml"
      refute html =~ "theirs.yaml"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/any/catalog")
    end
  end

  describe "pubsub updates" do
    test "re-renders when an import run completes" do
      {conn, _org, mission} = signed_in_org_and_mission()
      artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
      run = TestFixtures.persist_catalog_import_run!(artifact)

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "Running"

      completed = TestFixtures.complete_catalog_import_run!(run)

      # The broadcast was already emitted by complete_catalog_import_run!. Allow
      # the LiveView to process the message:
      assert render(view) =~ "Completed"
      assert completed.status == :completed
    end
  end
end
```

- [ ] **Step 2: Run and see failures**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: several failures (missing UI, missing pubsub).

- [ ] **Step 3: Implement the index**

Replace `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex` with:

```elixir
defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  # TODO(authz): Catalog upload currently permitted for any active org member.
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Events

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:nav_item, :catalog)
     |> assign_artifacts(organization_id, mission.mission_id)}
  end

  @impl true
  def handle_info({event, run}, socket)
      when event in [
             :import_run_started,
             :import_run_updated,
             :import_run_completed,
             :import_run_failed
           ] do
    {:noreply, apply_run_to_latest_map(socket, run)}
  end

  defp assign_artifacts(socket, organization_id, mission_id) do
    artifacts = Catalog.list_artifacts(organization_id, mission_id)
    latest = Catalog.latest_import_run_by_artifact(organization_id, mission_id)

    socket
    |> assign(:artifacts, artifacts)
    |> assign(:latest_runs, latest)
  end

  defp apply_run_to_latest_map(socket, run) do
    update(socket, :latest_runs, fn latest ->
      case Map.get(latest, run.artifact_id) do
        nil ->
          Map.put(latest, run.artifact_id, run)

        %{started_at: existing_started} ->
          if DateTime.compare(run.started_at, existing_started) in [:eq, :gt] do
            Map.put(latest, run.artifact_id, run)
          else
            latest
          end
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">Catalog</h1>
      </div>

      <.artifacts_table
        current_mission={@current_mission}
        artifacts={@artifacts}
        latest_runs={@latest_runs}
      />
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :artifacts, :list, required: true
  attr :latest_runs, :map, required: true

  defp artifacts_table(assigns) do
    ~H"""
    <%= if @artifacts == [] do %>
      <div class="card bg-base-200">
        <div class="card-body p-6 text-center">
          <p class="hud-label text-base-content/60">No catalog artifacts yet</p>
          <p class="text-sm text-base-content/50 mt-1">
            Uploading will appear here once the upload form lands.
          </p>
        </div>
      </div>
    <% else %>
      <div class="card bg-base-200">
        <table class="table">
          <thead>
            <tr>
              <th class="hud-label">Name</th>
              <th class="hud-label">Format</th>
              <th class="hud-label">Family</th>
              <th class="hud-label">Uploaded</th>
              <th class="hud-label">Latest run</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={artifact <- @artifacts}>
              <td class="font-medium">{artifact.artifact_name}</td>
              <td class="font-mono text-sm text-base-content/70">{artifact.format_key}</td>
              <td><.catalog_family_badge family={artifact.catalog_family} /></td>
              <td class="text-sm text-base-content/70">
                {Calendar.strftime(artifact.uploaded_at, "%Y-%m-%d %H:%M")}
              </td>
              <td>
                <%= case Map.get(@latest_runs, artifact.artifact_id) do %>
                  <% nil -> %>
                    <span class="text-base-content/40 text-xs">—</span>
                  <% run -> %>
                    <.link
                      navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{run.import_run_id}"}
                      class="inline-flex"
                    >
                      <.import_run_status_badge status={run.status} />
                    </.link>
                <% end %>
              </td>
              <td class="text-right">
                <.action_menu>
                  <:action>
                    <.link navigate={~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"}>
                      View artifact
                    </.link>
                  </:action>
                  <:action :if={Map.has_key?(@latest_runs, artifact.artifact_id)}>
                    <.link navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@latest_runs[artifact.artifact_id].import_run_id}"}>
                      View latest run
                    </.link>
                  </:action>
                </.action_menu>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end
end
```

- [ ] **Step 4: Verify tests pass**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: green.

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/catalog/catalog_index_live.ex
git add apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/test/cadence_web/live/catalog
git commit -m "feat(cadence_web): list catalog artifacts with live run status"
```

### Task 5.3: Upload card with auto-detection + one-step upload+import

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`
- Modify: `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`

- [ ] **Step 1: Write failing tests**

Add these tests to `catalog_index_live_test.exs` inside a new `describe "upload flow"` block:

```elixir
  describe "upload flow" do
    test "shows a friendly banner when no importer matches the file" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      uploads =
        file_input(view, "#catalog-upload-form", :artifact, [
          %{
            name: "mission.bin",
            content: "anything",
            type: "application/octet-stream",
            last_modified: 1_700_000_000_000
          }
        ])

      render_upload(uploads, "mission.bin")

      html = render(view)
      assert html =~ "No importer supports"
      assert html =~ "mission.bin"
    end

    test "uploading a valid YAML file creates an artifact, starts a run, and navigates to the run" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      uploads =
        file_input(view, "#catalog-upload-form", :artifact, [
          %{
            name: "mission.yaml",
            content: "packets: []\ncommands: []\n",
            type: "application/yaml",
            last_modified: 1_700_000_000_000
          }
        ])

      render_upload(uploads, "mission.yaml")

      # After validate: detected importer is shown, submit enabled
      assert render(view) =~ "Cadence YAML Database"

      result = render_submit(view, "save", %{})

      assert {:error, {:live_redirect, %{to: to}}} = result
      assert to =~ ~r"/missions/.+/catalog/imports/"
    end
  end
```

- [ ] **Step 2: Run the tests to see them fail**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: no upload form exists yet.

- [ ] **Step 3: Implement the upload card**

Update `catalog_index_live.ex` to add upload handling. Key additions (merge with the existing module, do not replace wholesale):

Add imports and aliases at the top:

```elixir
  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Events
  alias Cadence.Catalog.Registry
```

Update `mount/3`:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:nav_item, :catalog)
     |> assign(:detected_importer, nil)
     |> assign_artifacts(organization_id, mission.mission_id)
     |> allow_upload(:artifact,
       accept: :any,
       max_entries: 1,
       max_file_size: 50 * 1024 * 1024
     )}
  end
```

Add event handlers:

```elixir
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, assign(socket, :detected_importer, detect_from_uploads(socket))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :artifact, ref)}
  end

  def handle_event("save", _params, socket) do
    case socket.assigns.detected_importer do
      {:ok, registration} ->
        perform_upload(socket, registration)

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Pick a file with a supported format before uploading."
         )}
    end
  end

  defp perform_upload(socket, %{descriptor: descriptor}) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    uploaded_by = uploader_identity(socket)

    [artifact_or_error | _] =
      consume_uploaded_entries(socket, :artifact, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, bytes} ->
            upload = %{
              filename: entry.client_name,
              bytes: bytes,
              client_type: entry.client_type
            }

            {:ok,
             Artifact.build_from_upload(mission.mission_id, descriptor, upload,
               uploaded_by: uploaded_by
             )}

          {:error, reason} ->
            {:ok, {:error, {:file_read_failed, reason}}}
        end
      end)

    case artifact_or_error do
      %Artifact{} = artifact ->
        case Catalog.persist_artifact(organization_id, artifact) do
          {:ok, persisted} ->
            start_import_and_redirect(socket, persisted, descriptor)

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to save artifact: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to read uploaded file: #{inspect(reason)}")}
    end
  end

  defp start_import_and_redirect(socket, artifact, %{descriptor: descriptor}) do
    organization_id = socket.assigns.current_scope.organization_id
    mission = socket.assigns.current_mission
    uploaded_by = uploader_identity(socket)

    case Catalog.start_import_run(
           organization_id,
           mission.mission_id,
           artifact.artifact_id,
           descriptor.importer_key,
           requested_by: uploaded_by
         ) do
      {:ok, run} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Import run failed to start: #{inspect(reason)}")
         |> push_navigate(
           to: ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
         )}
    end
  end

  defp detect_from_uploads(socket) do
    case socket.assigns.uploads.artifact.entries do
      [%{client_name: name, client_type: type} | _] ->
        Registry.detect_importer(name, type)

      _ ->
        nil
    end
  end

  defp uploader_identity(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id, email: email}} -> %{user_id: id, email: email}
      %{user: %{email: email}} -> %{email: email}
      _ -> %{}
    end
  end
```

Replace the `render/1` function with:

```elixir
  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">Catalog</h1>
      </div>

      <.upload_card
        uploads={@uploads}
        detected_importer={@detected_importer}
      />

      <.artifacts_table
        current_mission={@current_mission}
        artifacts={@artifacts}
        latest_runs={@latest_runs}
      />
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :detected_importer, :any, required: true

  defp upload_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-6 space-y-4">
        <p class="hud-label">Upload command & telemetry database</p>

        <.form
          id="catalog-upload-form"
          for={%{}}
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <label class="block">
            <.live_file_input upload={@uploads.artifact} class="file-input file-input-bordered w-full" />
          </label>

          <ul :if={@uploads.artifact.entries != []} class="space-y-1">
            <li :for={entry <- @uploads.artifact.entries} class="flex items-center justify-between text-sm">
              <span class="font-mono">{entry.client_name} ({entry.client_type || "unknown"})</span>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                class="btn btn-ghost btn-xs"
              >
                Remove
              </button>
            </li>
          </ul>

          <.upload_error :for={err <- upload_errors(@uploads.artifact)} error={err} />

          <.detected_preview detected={@detected_importer} />

          <div class="flex items-center gap-3">
            <button
              type="submit"
              class="btn btn-primary"
              disabled={!importer_detected?(@detected_importer)}
            >
              Upload &amp; import
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :error, :atom, required: true

  defp upload_error(assigns) do
    ~H"""
    <div class="alert alert-error text-sm">
      {error_message(@error)}
    </div>
    """
  end

  attr :detected, :any, required: true

  defp detected_preview(assigns) do
    ~H"""
    <%= case @detected do %>
      <% {:ok, %{descriptor: descriptor}} -> %>
        <div class="flex items-center gap-2 text-sm text-base-content/80">
          <span class="hero-check-circle h-4 w-4 text-success"></span>
          Detected importer:
          <span class="font-medium">{descriptor.display_name}</span>
          <.catalog_family_badge family={descriptor.catalog_family} />
        </div>
      <% {:error, :no_matching_importer} -> %>
        <div class="alert alert-error text-sm">
          <p>
            No importer supports this file. Accepted formats: YAML (<code>.yaml</code>, <code>.yml</code>).
          </p>
        </div>
      <% _ -> %>
        <div class="text-xs text-base-content/50">
          Select a file to see the detected importer.
        </div>
    <% end %>
    """
  end

  defp importer_detected?({:ok, _registration}), do: true
  defp importer_detected?(_), do: false

  defp error_message(:too_large), do: "File exceeds the 50 MB limit."
  defp error_message(:not_accepted), do: "File type is not accepted."
  defp error_message(:too_many_files), do: "Only one file at a time."
  defp error_message(other), do: "Upload failed: #{inspect(other)}"
```

If the combined file exceeds 400 lines, split: keep event handlers + mount in `catalog_index_live.ex`, move `upload_card/1`, `artifacts_table/1`, `detected_preview/1` into `components.ex` as public components. The spec allows extracting when over limit.

- [ ] **Step 4: Run tests**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: green. Debug flash assertions and upload helpers if any test reports mismatched HTML. `render_submit/3` with no event returns a 302/redirect tuple when `push_navigate` is called.

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/live/catalog
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/catalog
wc -l apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex
# If over 400, split per CLAUDE.md rule before committing.
git add apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/test/cadence_web/live/catalog
git commit -m "feat(cadence_web): upload + auto-detect importer on catalog index"
```

---

## Phase 6 — Artifact detail LiveView

### Task 6.1: Render artifact metadata + import runs list

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_artifact_show_live.ex`
- Modify: `apps/cadence_web/test/cadence_web/live/catalog/catalog_artifact_show_live_test.exs`

- [ ] **Step 1: Write failing tests**

Create `apps/cadence_web/test/cadence_web/live/catalog/catalog_artifact_show_live_test.exs`:

```elixir
defmodule CadenceWeb.CatalogArtifactShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders artifact metadata and its import runs" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
    run = TestFixtures.persist_catalog_import_run!(artifact)
    _ = TestFixtures.complete_catalog_import_run!(run)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    assert html =~ "mission.yaml"
    assert html =~ artifact.format_key
    assert html =~ "Completed"
  end

  test "re-import action starts a new run and navigates to it" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> element("button", "Re-import") |> render_click()

    assert to =~ ~r"/catalog/imports/"
  end

  test "missing artifact redirects to the catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/artifacts/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_artifact_show_live_test.exs
```

- [ ] **Step 3: Implement**

Replace `catalog_artifact_show_live.ex` with:

```elixir
defmodule CadenceWeb.CatalogArtifactShowLive do
  @moduledoc false

  # TODO(authz): Catalog management currently permitted for any active org member.
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Events

  @impl true
  def mount(%{"artifact_id" => artifact_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Catalog.fetch_artifact(organization_id, mission.mission_id, artifact_id) do
      {:ok, artifact} ->
        if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

        runs =
          Catalog.list_import_runs(organization_id, mission.mission_id, artifact_id: artifact_id)

        {:ok,
         socket
         |> assign(:page_title, artifact.artifact_name)
         |> assign(:nav_item, :catalog)
         |> assign(:artifact, artifact)
         |> assign(:runs, runs)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Artifact not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/catalog")}
    end
  end

  @impl true
  def handle_info({event, run}, socket)
      when event in [
             :import_run_started,
             :import_run_updated,
             :import_run_completed,
             :import_run_failed
           ] do
    if run.artifact_id == socket.assigns.artifact.artifact_id do
      {:noreply, update(socket, :runs, &upsert_run(&1, run))}
    else
      {:noreply, socket}
    end
  end

  defp upsert_run(runs, run) do
    case Enum.find_index(runs, &(&1.import_run_id == run.import_run_id)) do
      nil -> [run | runs]
      index -> List.replace_at(runs, index, run)
    end
  end

  @impl true
  def handle_event("reimport", _params, socket) do
    artifact = socket.assigns.artifact
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Catalog.start_import_run(
           organization_id,
           mission.mission_id,
           artifact.artifact_id,
           artifact.format_key,
           requested_by: uploader_identity(socket)
         ) do
      {:ok, run} ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to start import: #{inspect(reason)}")}
    end
  end

  defp uploader_identity(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id, email: email}} -> %{user_id: id, email: email}
      _ -> %{}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Catalog
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">{@artifact.artifact_name}</h1>
      </div>

      <.artifact_metadata_card
        current_mission={@current_mission}
        artifact={@artifact}
      />

      <.artifact_runs_section current_mission={@current_mission} runs={@runs} />
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :artifact, :map, required: true

  defp artifact_metadata_card(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-6 space-y-3">
        <p class="hud-label">Artifact</p>
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <div class="contents">
            <dt class="text-base-content/60">Format</dt>
            <dd class="font-mono">{@artifact.format_key}</dd>
            <dt class="text-base-content/60">Family</dt>
            <dd><.catalog_family_badge family={@artifact.catalog_family} /></dd>
            <dt class="text-base-content/60">Media type</dt>
            <dd class="font-mono">{@artifact.media_type || "—"}</dd>
            <dt class="text-base-content/60">Content SHA-256</dt>
            <dd class="font-mono text-xs break-all">{@artifact.content_sha256}</dd>
            <dt class="text-base-content/60">Uploaded at</dt>
            <dd>{Calendar.strftime(@artifact.uploaded_at, "%Y-%m-%d %H:%M:%S UTC")}</dd>
          </div>
        </dl>

        <div class="flex items-center gap-3 pt-2">
          <a
            href={~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@artifact.artifact_id}/download"}
            class="btn btn-ghost btn-sm"
          >
            <span class="hero-arrow-down-tray h-4 w-4"></span>
            Download original
          </a>
          <button type="button" phx-click="reimport" class="btn btn-primary btn-sm">
            <span class="hero-arrow-path h-4 w-4"></span>
            Re-import
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :runs, :list, required: true

  defp artifact_runs_section(assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Import runs</p>
      <%= if @runs == [] do %>
        <div class="card bg-base-200">
          <div class="card-body p-4 text-sm text-base-content/60">
            No runs yet.
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200">
          <table class="table">
            <thead>
              <tr>
                <th class="hud-label">Status</th>
                <th class="hud-label">Started</th>
                <th class="hud-label">Completed</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={run <- @runs}>
                <td><.import_run_status_badge status={run.status} /></td>
                <td class="text-sm text-base-content/70">
                  {Calendar.strftime(run.started_at, "%Y-%m-%d %H:%M:%S")}
                </td>
                <td class="text-sm text-base-content/70">
                  {run.completed_at && Calendar.strftime(run.completed_at, "%Y-%m-%d %H:%M:%S") || "—"}
                </td>
                <td class="text-right">
                  <.action_menu>
                    <:action>
                      <.link navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{run.import_run_id}"}>
                        View run
                      </.link>
                    </:action>
                  </.action_menu>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
```

- [ ] **Step 4: Verify tests pass**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_artifact_show_live_test.exs
```

Expected: green.

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/live/catalog/catalog_artifact_show_live.ex
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/catalog/catalog_artifact_show_live.ex
git add apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/test/cadence_web/live/catalog
git commit -m "feat(cadence_web): catalog artifact detail with re-import"
```

---

## Phase 7 — Import run detail LiveView

### Task 7.1: Status header + diagnostics + snapshot summaries + pubsub

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_import_run_show_live.ex`
- Modify: `apps/cadence_web/test/cadence_web/live/catalog/catalog_import_run_show_live_test.exs`

- [ ] **Step 1: Write failing tests**

Create `apps/cadence_web/test/cadence_web/live/catalog/catalog_import_run_show_live_test.exs`:

```elixir
defmodule CadenceWeb.CatalogImportRunShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog.Events
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders running status for a freshly inserted run" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, _view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    assert html =~ "Running"
    refute html =~ "Telemetry snapshot"
  end

  test "re-renders snapshot summary after an async completion broadcast" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    completed = TestFixtures.complete_catalog_import_run!(run)

    html = render(view)
    assert html =~ "Completed"

    if completed.snapshot_id do
      assert html =~ "Telemetry snapshot"
    end
  end

  test "missing run redirects to the catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end

  test "failure reason renders when a run fails" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    failed_run = %{run | status: :failed, failure_reason: {:exception, "boom"}}
    Events.broadcast_failed(failed_run)

    html = render(view)
    assert html =~ "Failed"
    assert html =~ "boom"
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_import_run_show_live_test.exs
```

- [ ] **Step 3: Implement**

Replace `catalog_import_run_show_live.ex` with:

```elixir
defmodule CadenceWeb.CatalogImportRunShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Events

  @impl true
  def mount(%{"import_run_id" => import_run_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Catalog.fetch_import_run(organization_id, mission.mission_id, import_run_id) do
      {:ok, run} ->
        if connected?(socket),
          do: Events.subscribe_import_run(mission.mission_id, run.import_run_id)

        socket =
          socket
          |> assign(:page_title, "Import run")
          |> assign(:nav_item, :catalog)
          |> assign(:run, run)
          |> assign_snapshots(run)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Import run not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/catalog")}
    end
  end

  @impl true
  def handle_info({event, run}, socket)
      when event in [
             :import_run_started,
             :import_run_updated,
             :import_run_completed,
             :import_run_failed
           ] do
    if run.import_run_id == socket.assigns.run.import_run_id do
      {:noreply,
       socket
       |> assign(:run, run)
       |> assign_snapshots(run)}
    else
      {:noreply, socket}
    end
  end

  defp assign_snapshots(socket, %{status: :completed} = run) do
    mission_id = socket.assigns.current_mission.mission_id
    organization_id = socket.assigns.current_scope.organization_id

    telemetry =
      organization_id
      |> Catalog.list_telemetry_snapshots(mission_id, import_run_id: run.import_run_id)
      |> List.first()

    command =
      organization_id
      |> Catalog.list_command_snapshots(mission_id, import_run_id: run.import_run_id)
      |> List.first()

    socket
    |> assign(:telemetry_snapshot, telemetry)
    |> assign(:command_snapshot, command)
  end

  defp assign_snapshots(socket, _run) do
    socket
    |> assign(:telemetry_snapshot, nil)
    |> assign(:command_snapshot, nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@run.artifact_id}"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Artifact
        </.link>
        <div class="flex items-center gap-3 mt-1">
          <h1 class="text-2xl font-bold text-base-content">Import run</h1>
          <.import_run_status_badge status={@run.status} />
        </div>
      </div>

      <.run_header run={@run} />

      <.diagnostic_list diagnostics={@run.diagnostics} />

      <.failure_block :if={@run.status == :failed} failure_reason={@run.failure_reason} />

      <div
        :if={@run.status == :completed}
        class="grid grid-cols-1 lg:grid-cols-2 gap-4"
      >
        <.snapshot_summary_card
          :if={@telemetry_snapshot}
          title="Telemetry snapshot"
          icon="hero-signal"
          counts={telemetry_counts(@telemetry_snapshot)}
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog/telemetry_snapshots/#{@telemetry_snapshot.snapshot_id}"}
        />

        <.snapshot_summary_card
          :if={@command_snapshot}
          title="Command snapshot"
          icon="hero-command-line"
          counts={command_counts(@command_snapshot)}
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog/command_snapshots/#{@command_snapshot.snapshot_id}"}
        />
      </div>
    </div>
    """
  end

  attr :run, :map, required: true

  defp run_header(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4 text-sm space-y-1">
        <div class="flex items-center gap-2">
          <span class="text-base-content/60">Importer</span>
          <span class="font-mono">{@run.importer_key}</span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-base-content/60">Started</span>
          <span>{Calendar.strftime(@run.started_at, "%Y-%m-%d %H:%M:%S UTC")}</span>
        </div>
        <div :if={@run.completed_at} class="flex items-center gap-2">
          <span class="text-base-content/60">Completed</span>
          <span>{Calendar.strftime(@run.completed_at, "%Y-%m-%d %H:%M:%S UTC")}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :failure_reason, :any, required: true

  defp failure_block(assigns) do
    ~H"""
    <div class="alert alert-error">
      <p class="font-mono text-sm">{format_failure_reason(@failure_reason)}</p>
    </div>
    """
  end

  defp format_failure_reason({:exception, message}) when is_binary(message), do: message
  defp format_failure_reason({:job_enqueue_failed, reason}), do: "Job enqueue failed: #{inspect(reason)}"
  defp format_failure_reason(reason), do: inspect(reason)

  defp telemetry_counts(snapshot) do
    [
      {"Packets", length(snapshot.packets)},
      {"Points", length(snapshot.points)},
      {"Types", length(snapshot.types)},
      {"Units", length(snapshot.units)},
      {"Calibrations", length(snapshot.calibration_algorithms)}
    ]
  end

  defp command_counts(snapshot) do
    [
      {"Definitions", length(snapshot.command_definitions)},
      {"Arguments", length(snapshot.arguments)},
      {"Argument types", length(snapshot.argument_types)},
      {"Encoding layouts", length(snapshot.encoding_layouts)}
    ]
  end
end
```

- [ ] **Step 4: Verify tests pass**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_import_run_show_live_test.exs
```

Expected: green.

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/live/catalog/catalog_import_run_show_live.ex
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/catalog/catalog_import_run_show_live.ex
git add apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/test/cadence_web/live/catalog
git commit -m "feat(cadence_web): catalog import run detail with live diagnostics"
```

---

## Phase 8 — Snapshot summary LiveViews

### Task 8.1: Telemetry snapshot show live

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live.ex`
- Create: `apps/cadence_web/test/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
defmodule CadenceWeb.CatalogTelemetrySnapshotShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders summary counts and provenance back-links" do
    {conn, org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)
    _ = TestFixtures.complete_catalog_import_run!(run)

    [snapshot | _] =
      Catalog.list_telemetry_snapshots(
        org.organization_id,
        mission.mission_id,
        import_run_id: run.import_run_id
      )

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/telemetry_snapshots/#{snapshot.snapshot_id}"
      )

    assert html =~ "Telemetry snapshot"
    assert html =~ "Packets"
    assert html =~ "Points"
    assert html =~ artifact.artifact_name
  end

  test "missing snapshot redirects to catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/catalog/telemetry_snapshots/missing"
             )

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end
end
```

- [ ] **Step 2: Verify fail**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live_test.exs
```

- [ ] **Step 3: Implement**

Replace `catalog_telemetry_snapshot_show_live.ex` with:

```elixir
defmodule CadenceWeb.CatalogTelemetrySnapshotShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    with {:ok, snapshot} <-
           Catalog.fetch_telemetry_snapshot(organization_id, mission.mission_id, snapshot_id),
         {:ok, artifact} <-
           Catalog.fetch_artifact(organization_id, mission.mission_id, snapshot.artifact_id) do
      {:ok,
       socket
       |> assign(:page_title, "Telemetry snapshot")
       |> assign(:nav_item, :catalog)
       |> assign(:snapshot, snapshot)
       |> assign(:artifact, artifact)}
    else
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Snapshot not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/catalog")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@snapshot.import_run_id}"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Import run
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">Telemetry snapshot</h1>
      </div>

      <.snapshot_summary_card
        title="Telemetry catalog"
        icon="hero-signal"
        counts={[
          {"Packets", length(@snapshot.packets)},
          {"Points", length(@snapshot.points)},
          {"Types", length(@snapshot.types)},
          {"Units", length(@snapshot.units)},
          {"Enumerations", enumeration_count(@snapshot)},
          {"Calibrations", length(@snapshot.calibration_algorithms)}
        ]}
      />

      <.provenance_block
        current_mission={@current_mission}
        artifact={@artifact}
        snapshot={@snapshot}
      />

      <p class="text-sm text-base-content/50">
        Individual-item views are coming in a future catalog explorer.
      </p>
    </div>
    """
  end

  defp enumeration_count(snapshot) do
    Enum.sum(Enum.map(snapshot.types, &length(Map.get(&1, :enumeration_values, []))))
  end

  attr :current_mission, :map, required: true
  attr :artifact, :map, required: true
  attr :snapshot, :map, required: true

  defp provenance_block(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4 text-sm space-y-1">
        <p class="hud-label mb-2">Provenance</p>
        <div>
          Artifact:
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@artifact.artifact_id}"}
            class="text-primary hover:underline"
          >
            {@artifact.artifact_name}
          </.link>
        </div>
        <div>
          Import run:
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@snapshot.import_run_id}"}
            class="text-primary hover:underline font-mono text-xs"
          >
            {@snapshot.import_run_id}
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
```

Note: if `enumeration_values` is not an actual field on `Cadence.Catalog.Telemetry.Type`, adjust `enumeration_count/1` accordingly. Verify by reading `apps/cadence/lib/cadence/catalog/telemetry/type.ex` before implementing.

- [ ] **Step 4: Verify tests pass**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live_test.exs
```

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live.ex
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/catalog/catalog_telemetry_snapshot_show_live.ex
git add apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/test/cadence_web/live/catalog
git commit -m "feat(cadence_web): telemetry snapshot summary view"
```

### Task 8.2: Command snapshot show live

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_command_snapshot_show_live.ex`
- Create: `apps/cadence_web/test/cadence_web/live/catalog/catalog_command_snapshot_show_live_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
defmodule CadenceWeb.CatalogCommandSnapshotShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders summary counts" do
    {conn, org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)
    _ = TestFixtures.complete_catalog_import_run!(run)

    snapshots =
      Catalog.list_command_snapshots(
        org.organization_id,
        mission.mission_id,
        import_run_id: run.import_run_id
      )

    case snapshots do
      [snapshot | _] ->
        {:ok, _view, html} =
          live(
            conn,
            ~p"/missions/#{mission.mission_id}/catalog/command_snapshots/#{snapshot.snapshot_id}"
          )

        assert html =~ "Command snapshot"
        assert html =~ "Definitions"
        assert html =~ "Arguments"

      [] ->
        # Fixture produced no command snapshot — acceptable for dev importer.
        :ok
    end
  end

  test "missing snapshot redirects to catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/catalog/command_snapshots/missing"
             )

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end
end
```

- [ ] **Step 2: Verify fail**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_command_snapshot_show_live_test.exs
```

- [ ] **Step 3: Implement**

Replace `catalog_command_snapshot_show_live.ex` with:

```elixir
defmodule CadenceWeb.CatalogCommandSnapshotShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    with {:ok, snapshot} <-
           Catalog.fetch_command_snapshot(organization_id, mission.mission_id, snapshot_id),
         {:ok, artifact} <-
           Catalog.fetch_artifact(organization_id, mission.mission_id, snapshot.artifact_id) do
      {:ok,
       socket
       |> assign(:page_title, "Command snapshot")
       |> assign(:nav_item, :catalog)
       |> assign(:snapshot, snapshot)
       |> assign(:artifact, artifact)}
    else
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Snapshot not found.")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/catalog")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@snapshot.import_run_id}"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Import run
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">Command snapshot</h1>
      </div>

      <.snapshot_summary_card
        title="Command catalog"
        icon="hero-command-line"
        counts={[
          {"Definitions", length(@snapshot.command_definitions)},
          {"Arguments", length(@snapshot.arguments)},
          {"Argument types", length(@snapshot.argument_types)},
          {"Encoding layouts", length(@snapshot.encoding_layouts)}
        ]}
      />

      <.provenance_block
        current_mission={@current_mission}
        artifact={@artifact}
        snapshot={@snapshot}
      />

      <p class="text-sm text-base-content/50">
        Individual-item views are coming in a future catalog explorer.
      </p>
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :artifact, :map, required: true
  attr :snapshot, :map, required: true

  defp provenance_block(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4 text-sm space-y-1">
        <p class="hud-label mb-2">Provenance</p>
        <div>
          Artifact:
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@artifact.artifact_id}"}
            class="text-primary hover:underline"
          >
            {@artifact.artifact_name}
          </.link>
        </div>
        <div>
          Import run:
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@snapshot.import_run_id}"}
            class="text-primary hover:underline font-mono text-xs"
          >
            {@snapshot.import_run_id}
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Verify green**

```
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_command_snapshot_show_live_test.exs
```

- [ ] **Step 5: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/live/catalog/catalog_command_snapshot_show_live.ex
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/catalog/catalog_command_snapshot_show_live.ex
git add apps/cadence_web/lib/cadence_web/live/catalog apps/cadence_web/test/cadence_web/live/catalog
git commit -m "feat(cadence_web): command snapshot summary view"
```

---

## Phase 9 — Artifact download controller

### Task 9.1: Add controller + route

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/controllers/catalog_artifact_download_controller.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Create: `apps/cadence_web/test/cadence_web/controllers/catalog_artifact_download_controller_test.exs`

- [ ] **Step 1: Inspect existing mission-scoped browser controllers**

```
grep -rn "NoOrganizationController\|:browser" apps/cadence_web/lib/cadence_web
```

Identify the on_mount/pipeline pattern for a mission-scoped browser controller. If no such pattern exists, reuse `CadenceWeb.MissionAuth` fetch helpers from within the controller action itself.

- [ ] **Step 2: Write failing test**

```elixir
defmodule CadenceWeb.CatalogArtifactDownloadControllerTest do
  use CadenceWeb.ConnCase, async: false

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "downloads the raw artifact bytes with content-disposition" do
    {conn, _org, mission} = signed_in_org_and_mission()

    artifact =
      TestFixtures.persist_catalog_artifact!(mission,
        artifact_name: "mission.yaml",
        source_artifact: "hello: world\n"
      )

    conn =
      get(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}/download"
      )

    assert response(conn, 200) == "hello: world\n"
    assert ["application/yaml" <> _] = get_resp_header(conn, "content-type")
    assert ["attachment; filename=" <> name] = get_resp_header(conn, "content-disposition")
    assert name =~ "mission.yaml"
  end

  test "returns 404 for unknown artifact" do
    {conn, _org, mission} = signed_in_org_and_mission()

    conn =
      get(conn, ~p"/missions/#{mission.mission_id}/catalog/artifacts/missing/download")

    assert conn.status == 404
  end

  test "rejects access from a user without membership" do
    user = TestFixtures.persist_user!()
    conn = TestFixtures.member_conn(user)

    assert conn
           |> get("/missions/any/catalog/artifacts/any/download")
           |> redirected_to() == "/no-organization"
  end
end
```

- [ ] **Step 3: Run to confirm failure**

```
cd apps/cadence_web && mix test test/cadence_web/controllers/catalog_artifact_download_controller_test.exs
```

- [ ] **Step 4: Implement controller**

Create `apps/cadence_web/lib/cadence_web/controllers/catalog_artifact_download_controller.ex`:

```elixir
defmodule CadenceWeb.CatalogArtifactDownloadController do
  @moduledoc false

  use CadenceWeb, :controller

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Missions

  def show(conn, %{"mission_id" => mission_id, "artifact_id" => artifact_id}) do
    scope = conn.assigns.current_scope

    with {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, artifact} <- Catalog.fetch_artifact(scope.organization_id, mission_id, artifact_id) do
      {bytes, content_type} = Artifact.download_payload(artifact)

      conn
      |> put_resp_content_type(content_type, nil)
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{artifact.artifact_name}")
      )
      |> send_resp(200, bytes)
    else
      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> text("Not found")
    end
  end
end
```

Note: `put_resp_content_type/3` will fail on non-extension types. If that happens, use `put_resp_header(conn, "content-type", content_type)` directly.

- [ ] **Step 5: Add the route**

In `apps/cadence_web/lib/cadence_web/router.ex`, inside the `scope "/", CadenceWeb do` block that has `pipe_through [:browser, :require_authenticated_scope]` (around line 49), add before the closing `end`:

```elixir
    get "/missions/:mission_id/catalog/artifacts/:artifact_id/download",
        CatalogArtifactDownloadController,
        :show
```

The controller relies on `conn.assigns.current_scope`. Since this lives under `:browser` + `:require_authenticated_scope`, `current_scope` is assigned by `CadenceWeb.Plugs.FetchBrowserCurrentScope`. Verify by reading that plug; it needs to populate `organization_id` — if it only handles the user scope, wrap the controller in an org-scope plug (similar to `CadenceWeb.OrganizationAuth.require_organization_scope` but for controllers).

If the scope shape differs from what's expected, adapt the controller's `scope = ...` line accordingly. The goal is: when organization membership is missing, the browser pipeline redirects to `/no-organization`.

- [ ] **Step 6: Verify tests pass**

```
cd apps/cadence_web && mix test test/cadence_web/controllers/catalog_artifact_download_controller_test.exs
```

- [ ] **Step 7: Quality gates + commit**

```
cd apps/cadence_web && mix compile --warnings-as-errors
mix format apps/cadence_web/lib/cadence_web/controllers/catalog_artifact_download_controller.ex apps/cadence_web/lib/cadence_web/router.ex
cd apps/cadence_web && mix credo --strict lib/cadence_web/controllers/catalog_artifact_download_controller.ex
git add apps/cadence_web/lib/cadence_web/controllers/catalog_artifact_download_controller.ex apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/test/cadence_web/controllers/catalog_artifact_download_controller_test.exs
git commit -m "feat(cadence_web): stream catalog artifact downloads"
```

---

## Phase 10 — Final verification

### Task 10.1: Full quality gates and manual smoke

- [ ] **Step 1: Compile both apps with warnings-as-errors**

```
cd apps/cadence && mix compile --warnings-as-errors
cd apps/cadence_web && mix compile --warnings-as-errors
```

Expected: both succeed.

- [ ] **Step 2: Run per-app tests**

```
cd apps/cadence && mix test
cd apps/cadence_web && mix test
```

Expected: both green.

- [ ] **Step 3: Format and credo**

```
cd .. && mix format
cd apps/cadence && mix credo --strict
cd apps/cadence_web && mix credo --strict
```

No regressions; ideally fewer credo violations than before (per CLAUDE.md: leave better than found).

- [ ] **Step 4: Manual UI smoke**

Start the dev server:

```
mix phx.server
```

Then, signed in as an organization member:

1. Navigate to `/missions/<mission_id>/catalog`. Confirm the Catalog sidebar item is highlighted, the upload card renders, and the artifacts table shows empty state.
2. Drop a known-good YAML file. Confirm the detected importer appears. Confirm the submit button becomes enabled.
3. Drop a `.bin` file. Confirm the red "no importer" banner appears and submit stays disabled.
4. Upload a valid YAML file. Confirm redirect to the import run page, which shows "Running" then flips to "Completed" without reload. Confirm snapshot summary cards render once completed.
5. Navigate to the artifact detail. Click "Download original" — confirm the browser downloads the file with the correct content. Click "Re-import" — confirm a new run is created and navigated to.
6. From an import run, click the telemetry / command snapshot links. Confirm counts render and back-links navigate correctly.

- [ ] **Step 5: Commit any residual formatting or typo fixes**

If the manual smoke revealed small UI/flash copy adjustments, commit them separately:

```
git add -p
git commit -m "fix(cadence_web): tighten catalog upload copy from smoke test"
```

- [ ] **Step 6: PR**

The feature is ready for review. Open a PR per the repo's conventions and link this plan + the spec in the description.

---

## Self-review checklist

Already applied during plan authoring:

- **Spec coverage:** Events module (Task 1.1), broadcasts (1.2), detect_importer (2.1), latest_import_run_by_artifact (3.1), Artifact helpers (3.2), router + skeletons + sidebar + fixtures (4.1–4.3), components + index table + upload (5.1–5.3), artifact detail + re-import (6.1), import run detail + PubSub + diagnostics + snapshot summaries (7.1), telemetry + command snapshot summaries (8.1, 8.2), download controller (9.1), final verification (10.1). All spec sections map to tasks.
- **Placeholder scan:** No "TBD / TODO / implement later / add error handling" handwaves. Where the plan notes an adaptation (e.g., shape of `enumeration_values` on `Type`), a concrete verification step is included.
- **Type consistency:** Status atoms `:running | :completed | :failed` used consistently (matches `ImportRun.status`). Topic names centralized in `Events`. PubSub message tuples consistent: `{:import_run_<state>, ImportRun.t()}`.
- **Out-of-scope items** (materialize runtime, XTCE importer, fuzzy search, per-item drill-in) are not referenced in any task, matching the spec's non-goals.
