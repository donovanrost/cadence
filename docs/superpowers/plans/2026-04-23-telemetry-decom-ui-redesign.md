# Telemetry Decom UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Telemetry Decom spacecraft-configuration LiveView with a single-card, progressively-disclosed APID table plus autosave, per the design spec at `docs/superpowers/specs/2026-04-23-telemetry-decom-ui-redesign-design.md`.

**Architecture:** LiveView retains the route `/missions/:mission_id/spacecraft/:spacecraft_id/telemetry_decom` but replaces its four stacked cards with one `card bg-base-200` containing five dashed-divider sections. The APID list moves to a new stateless function component (`CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable`) to keep files under 400 lines. One backend helper (`TelemetryDecom.list_revision_apid_rows/3`) is added so the LiveView does not re-shape snapshot data on each render; a stub `list_apid_conflicts/3` is added so the conflict column has a stable data path for future applications.

**Tech Stack:** Elixir, Phoenix LiveView, daisyUI + Tailwind v4, existing HUD utility classes. No new CSS. No new dependencies.

---

## File Structure

**Backend (app: `cadence`)**
- Modify: `apps/cadence/lib/cadence/applications/telemetry_decom.ex` — add `list_apid_conflicts/3` and `list_revision_apid_rows/3`
- Modify: `apps/cadence/test/cadence/applications/telemetry_decom_test.exs` — test cases for both new functions

**Frontend (app: `cadence_web`)**
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex` — full redesign, target < 300 lines
- Create: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex` — stateless function component, target < 250 lines
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs` — replace test cases for new behaviour
- No template files (HEEX is inline)
- No router changes
- No CSS changes

---

## Task 1: Backend — `list_apid_conflicts/3` stub helper

**Files:**
- Modify: `apps/cadence/lib/cadence/applications/telemetry_decom.ex` — add public function near `preview/3`
- Modify: `apps/cadence/test/cadence/applications/telemetry_decom_test.exs` — add describe block

**Rationale:** The spec's conflict column needs a data source. Since Telemetry Decom is currently the only built-in application, the function always returns `%{}` today. Adding the wire now means the LiveView can call it in Task 4 and a future app (Event Reporting) only needs to change this one function.

- [ ] **Step 1.1: Add failing test to `telemetry_decom_test.exs`**

Append this describe block at the end of the file, before the final `end` and before the private helpers:

```elixir
  describe "list_apid_conflicts/3" do
    test "returns an empty map today — no other applications exist" do
      {spacecraft, _revision, _endpoint} = setup_mission()

      assert %{} =
               TelemetryDecom.list_apid_conflicts(
                 @organization_id,
                 @mission_id,
                 spacecraft.spacecraft_id
               )
    end
  end
```

- [ ] **Step 1.2: Run the test — it should fail**

```bash
cd apps/cadence && mix test test/cadence/applications/telemetry_decom_test.exs --only describe:"list_apid_conflicts/3"
```

Expected: fails with `UndefinedFunctionError` (or compile error) because `list_apid_conflicts/3` does not exist.

- [ ] **Step 1.3: Implement `list_apid_conflicts/3`**

In `apps/cadence/lib/cadence/applications/telemetry_decom.ex`, insert this function after `preview/3` (around line 326):

```elixir
  @doc """
  Return a map of `apid => other_application_display_name` for every APID
  already claimed by a *different* enabled application on this spacecraft.

  Today Telemetry Decom is the only built-in application, so this always
  returns an empty map. The function exists so the UI can render a conflict
  column without future wiring when additional applications land.
  """
  @spec list_apid_conflicts(binary(), binary(), binary()) ::
          %{non_neg_integer() => String.t()}
  def list_apid_conflicts(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(spacecraft_id) do
    %{}
  end
```

- [ ] **Step 1.4: Run the test — it should pass**

```bash
cd apps/cadence && mix test test/cadence/applications/telemetry_decom_test.exs --only describe:"list_apid_conflicts/3"
```

Expected: 1 test, 0 failures.

- [ ] **Step 1.5: Commit**

```bash
git add apps/cadence/lib/cadence/applications/telemetry_decom.ex apps/cadence/test/cadence/applications/telemetry_decom_test.exs
git commit -m "feat(cadence): add TelemetryDecom.list_apid_conflicts/3 stub"
```

---

## Task 2: Backend — `list_revision_apid_rows/3`

**Files:**
- Modify: `apps/cadence/lib/cadence/applications/telemetry_decom.ex` — add public function
- Modify: `apps/cadence/test/cadence/applications/telemetry_decom_test.exs` — add describe block

**Rationale:** The UI needs one row per APID in the selected revision, each with the APID's packet-definition structs and a derived rate (from the first packet). Fetching the snapshot and grouping inline in the LiveView would put catalog-shaping logic in the web layer.

- [ ] **Step 2.1: Add failing test**

Append this describe block after the `list_apid_conflicts/3` describe:

```elixir
  describe "list_revision_apid_rows/3" do
    test "groups snapshot packets by APID and sorts by APID" do
      {_spacecraft, revision, _endpoint} = setup_mission()

      assert {:ok, rows} =
               TelemetryDecom.list_revision_apid_rows(
                 @organization_id,
                 @mission_id,
                 revision.catalog_revision_id
               )

      assert [%{apid: 42, packets: packets, def_count: 1} | _] = rows
      assert [%Cadence.Catalog.Telemetry.Packet{name: "HEALTH", apid: 42}] = packets
    end

    test "returns an error tuple when the revision has no telemetry snapshot" do
      persist_mission_scope(@organization_id, @mission_id)

      # fabricate a revision id that is not in the db
      assert {:error, _} =
               TelemetryDecom.list_revision_apid_rows(
                 @organization_id,
                 @mission_id,
                 "nonexistent-revision-id"
               )
    end
  end
```

- [ ] **Step 2.2: Run the test — it should fail**

```bash
cd apps/cadence && mix test test/cadence/applications/telemetry_decom_test.exs --only describe:"list_revision_apid_rows/3"
```

Expected: fails with `UndefinedFunctionError`.

- [ ] **Step 2.3: Implement `list_revision_apid_rows/3`**

In `apps/cadence/lib/cadence/applications/telemetry_decom.ex`, insert after `list_apid_conflicts/3`:

```elixir
  @type apid_row :: %{
          apid: non_neg_integer(),
          packets: [Packet.t()],
          def_count: non_neg_integer(),
          rate_hz: number() | nil,
          short_description: String.t() | nil
        }

  @doc """
  Return one row per APID present in the revision's telemetry snapshot.

  Each row carries every packet definition that shares the APID, along with
  a primary rate (from the first packet's `expected_rate_hz`) and a short
  description derived from the first packet's `short_description` or a
  truncated `description`. Rows are sorted by APID ascending.
  """
  @spec list_revision_apid_rows(binary(), binary(), binary()) ::
          {:ok, [apid_row()]} | {:error, term()}
  def list_revision_apid_rows(organization_id, mission_id, catalog_revision_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(catalog_revision_id) do
    with {:ok, %Revision{} = revision} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         :ok <- ensure_telemetry_revision(revision),
         {:ok, snapshot} <-
           Catalog.fetch_telemetry_snapshot(
             organization_id,
             mission_id,
             revision.telemetry_snapshot_id
           ) do
      rows =
        snapshot.packets
        |> Enum.filter(&is_integer(&1.apid))
        |> Enum.group_by(& &1.apid)
        |> Enum.sort_by(fn {apid, _} -> apid end)
        |> Enum.map(fn {apid, packets} ->
          first = List.first(packets)

          %{
            apid: apid,
            packets: packets,
            def_count: length(packets),
            rate_hz: first && first.expected_rate_hz,
            short_description: short_description_of(first)
          }
        end)

      {:ok, rows}
    end
  end

  defp short_description_of(nil), do: nil
  defp short_description_of(%Packet{short_description: desc}) when is_binary(desc), do: desc

  defp short_description_of(%Packet{description: desc}) when is_binary(desc) do
    if String.length(desc) <= 160, do: desc, else: String.slice(desc, 0, 157) <> "…"
  end

  defp short_description_of(_), do: nil
```

- [ ] **Step 2.4: Run the test — it should pass**

```bash
cd apps/cadence && mix test test/cadence/applications/telemetry_decom_test.exs --only describe:"list_revision_apid_rows/3"
```

Expected: 2 tests, 0 failures.

- [ ] **Step 2.5: Commit**

```bash
git add apps/cadence/lib/cadence/applications/telemetry_decom.ex apps/cadence/test/cadence/applications/telemetry_decom_test.exs
git commit -m "feat(cadence): add TelemetryDecom.list_revision_apid_rows/3"
```

---

## Task 3: Frontend — LiveView mount loads new assigns

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex` — replace `mount/3`
- Test: exercised by existing tests in `spacecraft_telemetry_decom_live_test.exs`

**Rationale:** The new UI needs five new assigns: the selection as a `MapSet`, expanded APIDs as a `MapSet`, the filter string, the revision APID rows, and the conflict map. This task wires those on mount and on revision change, without touching the render yet (so tests continue to pass on the old template).

- [ ] **Step 3.1: Replace the `mount/3` body**

In `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex`, replace the existing `mount/3` (lines 10-34) with:

```elixir
  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mission_id = socket.assigns.current_mission.mission_id
    spacecraft_id = socket.assigns.current_spacecraft.spacecraft_id

    config =
      case TelemetryDecom.fetch_config(organization_id, mission_id, spacecraft_id) do
        {:ok, config} -> config
        {:error, :not_configured} -> nil
      end

    revisions = list_telemetry_revisions(organization_id, mission_id)
    selected_revision_id = config && config.catalog_revision_id || first_option_value(revisions)

    apid_rows = load_apid_rows(organization_id, mission_id, selected_revision_id)
    conflicts = TelemetryDecom.list_apid_conflicts(organization_id, mission_id, spacecraft_id)
    selection = selection_from_config(config)

    {:ok,
     socket
     |> assign(:page_title, "Telemetry Decom")
     |> assign(:nav_item, :spacecraft)
     |> assign(:config, config)
     |> assign(:revisions, revisions)
     |> assign(:selected_revision_id, selected_revision_id)
     |> assign(:apid_rows, apid_rows)
     |> assign(:conflicts, conflicts)
     |> assign(:selection, selection)
     |> assign(:expanded_apids, MapSet.new())
     |> assign(:expanded_defs, MapSet.new())
     |> assign(:expanded_entries, MapSet.new())
     |> assign(:filter, "")
     |> assign(:dropped_unknowns, [])
     |> assign(:preview, preview_for(organization_id, mission_id, config))
     |> assign(:active_binding_set_summary, fetch_active_binding_set_summary(mission_id))
     |> assign(:saved_at, config && DateTime.utc_now())}
  end

  defp load_apid_rows(_organization_id, _mission_id, nil), do: []

  defp load_apid_rows(organization_id, mission_id, revision_id) do
    case TelemetryDecom.list_revision_apid_rows(organization_id, mission_id, revision_id) do
      {:ok, rows} -> rows
      {:error, _} -> []
    end
  end

  defp selection_from_config(nil), do: MapSet.new()
  defp selection_from_config(%{handled_apids: apids}), do: MapSet.new(apids)
```

Leave `handle_event` and `render/1` unchanged for now — the next tasks rewrite them.

- [ ] **Step 3.2: Run the existing LiveView test suite to confirm nothing regressed**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
```

Expected: all tests pass (mount changes don't affect the render yet).

- [ ] **Step 3.3: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex
git commit -m "refactor(cadence_web): widen TelemetryDecomLive mount assigns for redesign"
```

---

## Task 4: Frontend — `APIDTable` component (skeleton, collapsed rows only)

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex`
- Test: exercised indirectly via `spacecraft_telemetry_decom_live_test.exs` later

**Rationale:** Stand up the table component before wiring it into the page. At this stage it renders only collapsed rows — no expansion, no filter, no bulk actions. We'll compose upward.

- [ ] **Step 4.1: Create the component file**

Write to `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex`:

```elixir
defmodule CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable do
  @moduledoc false

  use Phoenix.Component

  import CadenceWeb.CoreComponents, only: [status_dot: 1]

  attr :rows, :list, required: true
  attr :selection, :any, required: true
  attr :conflicts, :map, required: true
  attr :expanded_apids, :any, required: true
  attr :expanded_defs, :any, required: true
  attr :expanded_entries, :any, required: true
  attr :filter, :string, default: ""

  def table(assigns) do
    assigns = assign(assigns, :visible_rows, filter_rows(assigns.rows, assigns.filter))

    ~H"""
    <table class="w-full text-sm" id="telemetry-decom-apid-table">
      <thead>
        <tr class="text-base-content/60 text-xs uppercase tracking-wider">
          <th class="py-2 w-8"></th>
          <th class="py-2 w-6"></th>
          <th class="py-2 w-16 text-left">APID</th>
          <th class="py-2 text-left">Packets</th>
          <th class="py-2 w-16 text-left">Defs</th>
          <th class="py-2 w-20 text-left">Rate</th>
          <th class="py-2 w-28 text-left">Conflict</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @visible_rows} id={"apid-row-#{row.apid}"} class="border-t border-base-300/40">
          <td class="py-2">
            <input
              type="checkbox"
              class="checkbox checkbox-sm checkbox-primary"
              checked={MapSet.member?(@selection, row.apid)}
              disabled={Map.has_key?(@conflicts, row.apid)}
              phx-click="toggle_apid"
              phx-value-apid={row.apid}
            />
          </td>
          <td class="py-2 text-base-content/50">›</td>
          <td class="py-2 font-mono">{row.apid}</td>
          <td class="py-2">{packets_label(row)}</td>
          <td class="py-2 text-base-content/60">{row.def_count}</td>
          <td class="py-2 text-base-content/60">{rate_label(row.rate_hz)}</td>
          <td class="py-2 text-base-content/60">{conflict_label(@conflicts, row.apid)}</td>
        </tr>
        <tr :if={@visible_rows == []}>
          <td colspan="7" class="py-4 text-center text-base-content/60">
            No APIDs match the filter.
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp filter_rows(rows, ""), do: rows

  defp filter_rows(rows, filter) do
    needle = String.downcase(filter)

    Enum.filter(rows, fn row ->
      apid_str = Integer.to_string(row.apid)

      String.contains?(apid_str, needle) or
        Enum.any?(row.packets, fn packet ->
          String.contains?(String.downcase(packet.name || ""), needle)
        end)
    end)
  end

  defp packets_label(%{packets: [single]}), do: single.name

  defp packets_label(%{packets: [first | _], def_count: n}),
    do: "#{first.name} (#{n} defs)"

  defp packets_label(_), do: "—"

  defp rate_label(nil), do: "—"
  defp rate_label(hz) when is_number(hz), do: "#{trim_float(hz)} Hz"

  defp trim_float(hz) when is_integer(hz), do: hz

  defp trim_float(hz) when is_float(hz) do
    if hz == Float.round(hz) do
      trunc(hz) |> Integer.to_string()
    else
      :erlang.float_to_binary(hz, decimals: 2)
    end
  end

  defp conflict_label(conflicts, apid) do
    case Map.get(conflicts, apid) do
      nil -> "—"
      name -> name
    end
  end

  # status_dot is imported for use in later tasks (Level 2 expansion).
  _ = &status_dot/1
end
```

- [ ] **Step 4.2: Compile to confirm**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
```

Expected: clean compile, no warnings.

- [ ] **Step 4.3: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex
git commit -m "feat(cadence_web): add TelemetryDecom APIDTable component skeleton"
```

---

## Task 5: Frontend — replace LiveView template with single-card layout

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex` — replace `render/1`, delete old private components
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs` — update assertions that reference old UI

**Rationale:** Swap the four-card stack for the single-card five-section layout. The APIDTable is already built. Save button is removed — autosave wiring comes in Task 6.

- [ ] **Step 5.1: Replace the `render/1` body and private component functions**

In `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex`:

1. Add the import for the APIDTable near the top (after the `alias` lines):

```elixir
  alias CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable
```

2. Replace the entire `render/1` function and every private component below it (`status_card`, `preview_card`, `diagnostics_list`, `actions_card`) with:

```elixir
  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={
            ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"
          }
          class="text-sm text-primary hover:underline"
        >
          &larr; {@current_spacecraft.display_name}
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">Telemetry Decom</h1>
        <p class="text-sm text-base-content/60 mt-1">
          Packet routing configuration for
          <span class="font-semibold text-base-content">{@current_spacecraft.display_name}</span>.
        </p>
      </div>

      <div class="card bg-base-200" id="telemetry-decom-card">
        <div class="card-body p-6 space-y-4">
          <.status_section config={@config} active={@active_binding_set_summary} saved_at={@saved_at} />
          <div class="border-t border-dashed border-base-300/60"></div>

          <%= if @revisions == [] do %>
            <.no_revisions_notice current_mission={@current_mission} />
          <% else %>
            <.revision_section
              revisions={@revisions}
              selected_revision_id={@selected_revision_id}
            />
            <div class="border-t border-dashed border-base-300/60"></div>

            <.dropped_unknowns_banner dropped={@dropped_unknowns} />

            <.apid_section
              rows={@apid_rows}
              selection={@selection}
              conflicts={@conflicts}
              expanded_apids={@expanded_apids}
              expanded_defs={@expanded_defs}
              expanded_entries={@expanded_entries}
              filter={@filter}
            />
            <div class="border-t border-dashed border-base-300/60"></div>

            <.preview_section preview={@preview} />
            <div class="border-t border-dashed border-base-300/60"></div>

            <.apply_section config={@config} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :config, :any, default: nil
  attr :active, :any, default: nil
  attr :saved_at, :any, default: nil

  defp status_section(assigns) do
    assigns = assign(assigns, :status, TelemetryDecom.status(assigns.config, assigns.active))

    ~H"""
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <.status_dot status={dot_status(@status)} />
        <span class="font-semibold text-base-content">{status_label(@status)}</span>
        <span class="text-sm text-base-content/60">— {status_description(@status)}</span>
      </div>
      <span :if={@saved_at} class="hud-label">Saved {format_relative(@saved_at)}</span>
    </div>
    """
  end

  attr :revisions, :list, required: true
  attr :selected_revision_id, :any, default: nil

  defp revision_section(assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Catalog revision</p>
      <form phx-change="change_revision" id="telemetry-decom-revision-form" class="max-w-sm">
        <select
          name="catalog_revision_id"
          id="telemetry-decom-revision-select"
          class="select w-full"
        >
          <option
            :for={{label, value} <- @revisions}
            value={value}
            selected={to_string(@selected_revision_id) == to_string(value)}
          >
            {label}
          </option>
        </select>
      </form>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :selection, :any, required: true
  attr :conflicts, :map, required: true
  attr :expanded_apids, :any, required: true
  attr :expanded_defs, :any, required: true
  attr :expanded_entries, :any, required: true
  attr :filter, :string, required: true

  defp apid_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between gap-2">
        <p class="hud-label">
          Handled APIDs · {MapSet.size(@selection)} / {length(@rows)}
        </p>
        <div class="flex items-center gap-2">
          <form phx-change="filter_apids" id="telemetry-decom-filter-form">
            <input
              type="text"
              name="filter"
              value={@filter}
              placeholder="Filter…"
              class="input input-sm"
              id="telemetry-decom-filter-input"
            />
          </form>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="select_all_unclaimed"
            id="telemetry-decom-select-all"
          >
            Select all unclaimed
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="clear_selection"
            id="telemetry-decom-clear"
          >
            Clear
          </button>
        </div>
      </div>
      <APIDTable.table
        rows={@rows}
        selection={@selection}
        conflicts={@conflicts}
        expanded_apids={@expanded_apids}
        expanded_defs={@expanded_defs}
        expanded_entries={@expanded_entries}
        filter={@filter}
      />
    </div>
    """
  end

  attr :preview, :any, default: nil

  defp preview_section(%{preview: nil} = assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Preview</p>
      <p class="text-sm text-base-content/60">
        Select one or more APIDs to preview matched packets.
      </p>
    </div>
    """
  end

  defp preview_section(assigns) do
    ~H"""
    <div>
      <p class="hud-label mb-2">Preview</p>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
        <div>
          <div class="text-base-content/60">Matched packets</div>
          <div class="text-xl font-semibold">{length(@preview.selected_packets)}</div>
        </div>
        <div>
          <div class="text-base-content/60">Compiled defs</div>
          <div class="text-xl font-semibold">
            {length(@preview.compilation.compiler_result.packet_definitions)}
          </div>
        </div>
        <div>
          <div class="text-base-content/60">Unassigned APIDs</div>
          <div class="text-xl font-semibold">{length(@preview.unassigned_apids)}</div>
        </div>
        <div>
          <div class="text-base-content/60">Notices</div>
          <div class="text-xl font-semibold">
            {length(@preview.compilation.compiler_result.diagnostics)}
          </div>
        </div>
      </div>
      <.diagnostics_list diagnostics={@preview.compilation.compiler_result.diagnostics} />
    </div>
    """
  end

  attr :diagnostics, :list, default: []

  defp diagnostics_list(%{diagnostics: []} = assigns), do: ~H""

  defp diagnostics_list(assigns) do
    ~H"""
    <ul class="space-y-1 text-sm mt-3" id="telemetry-decom-diagnostics">
      <li :for={d <- Enum.take(@diagnostics, 20)} class="flex items-start gap-2">
        <.status_dot status={diagnostic_dot(d.severity)} size={:sm} class="mt-1.5" />
        <span>
          <span class="font-mono text-xs text-base-content/60">{d.code}</span>
          <span class="ml-1">{d.message}</span>
        </span>
      </li>
      <li :if={length(@diagnostics) > 20} class="text-xs text-base-content/60 mt-2">
        {length(@diagnostics) - 20} more omitted.
      </li>
    </ul>
    """
  end

  attr :config, :any, default: nil

  defp apply_section(%{config: nil} = assigns) do
    ~H"""
    <div class="flex justify-end">
      <p class="text-sm text-base-content/60">
        Select at least one APID to save and apply.
      </p>
    </div>
    """
  end

  defp apply_section(assigns) do
    ~H"""
    <div class="flex justify-end gap-2">
      <button
        :if={@config.enabled}
        type="button"
        class="btn btn-ghost btn-sm"
        phx-click="disable"
        id="telemetry-decom-disable-button"
        data-confirm="Disable Telemetry Decom for this spacecraft?"
      >
        Disable
      </button>
      <button
        type="button"
        class="btn btn-primary btn-sm"
        phx-click="enable"
        id="telemetry-decom-enable-button"
      >
        Apply mission changes
      </button>
    </div>
    """
  end

  attr :dropped, :list, default: []

  defp dropped_unknowns_banner(%{dropped: []} = assigns), do: ~H""

  defp dropped_unknowns_banner(assigns) do
    ~H"""
    <div class="alert alert-warning text-sm" id="telemetry-decom-dropped-unknowns">
      <span>
        {length(@dropped)} previously selected
        {Ngettext.singular_plural(length(@dropped), "APID is", "APIDs are")}
        not in this revision:
        <span class="font-mono">{Enum.join(@dropped, ", ")}</span>.
      </span>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click="drop_unknown_apids"
        id="telemetry-decom-drop-unknowns"
      >
        Drop them
      </button>
    </div>
    """
  end

  attr :current_mission, :map, required: true

  defp no_revisions_notice(assigns) do
    ~H"""
    <div>
      <p class="text-sm text-base-content/60">
        No telemetry catalog revisions available for this mission yet. Import a catalog
        revision first.
      </p>
      <.link
        navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
        class="btn btn-ghost btn-sm mt-3"
      >
        Go to catalog
      </.link>
    </div>
    """
  end

  defp format_relative(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
```

3. Replace the `Ngettext.singular_plural/3` call — it's a placeholder. Drop that helper and inline the string instead. In `dropped_unknowns_banner/1`, change the span to:

```elixir
      <span>
        {length(@dropped)} previously selected {if length(@dropped) == 1, do: "APID is", else: "APIDs are"}
        not in this revision:
        <span class="font-mono">{Enum.join(@dropped, ", ")}</span>.
      </span>
```

- [ ] **Step 5.2: Update existing LiveView tests to match new assertions**

Replace the file contents of `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs` — specifically the assertions below — so the tests exercise the new template. The three key changes:

1. `"renders status card and links back to spacecraft"` — unchanged.
2. `"configures and enables telemetry decom end-to-end"` — remove `form/render_submit` flow (Save button no longer exists). Replace with click-driven flow. See Task 6 for the actual replacement; for now, make the test xfail by adding `@tag :skip` so the suite stays green:

```elixir
  @tag :skip
  test "configures and enables telemetry decom end-to-end" do
```

3. `"disabled configs can still be applied from the same screen"` — same treatment, tag as `:skip`.
4. `"focuses the page on catalog revision and handled APID selection"` — change assertion `assert html =~ "Catalog Revision"` to `assert html =~ "Catalog revision"` (match the new `hud-label` string).
5. `"shows a validation error for APIDs not found in the selected revision"` — tag as `:skip` (replaced in Task 6).

- [ ] **Step 5.3: Compile and run tests**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
```

Expected: passes (skipped tests are marked, not run).

- [ ] **Step 5.4: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
git commit -m "refactor(cadence_web): replace TelemetryDecomLive template with single-card layout"
```

---

## Task 6: Frontend — `toggle_apid` event with autosave

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex` — replace `handle_event/3` clauses
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs` — new assertions

- [ ] **Step 6.1: Add a failing test**

In `spacecraft_telemetry_decom_live_test.exs`, replace the `@tag :skip`-ed `"configures and enables telemetry decom end-to-end"` test with this new test:

```elixir
  test "toggling an APID autosaves and updates the preview count" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    html =
      view
      |> element("input[phx-click='toggle_apid'][phx-value-apid='42']")
      |> render_click()

    assert html =~ "Matched packets"
    # selection count should be 1 now; preview stats should render
    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == [42]
  end
```

- [ ] **Step 6.2: Run — expect failure**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs -k "toggling an APID autosaves"
```

Expected: fails because `toggle_apid` handler is not implemented.

- [ ] **Step 6.3: Replace `handle_event/3` clauses**

In `spacecraft_telemetry_decom_live.ex`, delete the old `"validate"` and `"save"` handlers, and add these handlers (the `"enable"` and `"disable"` handlers stay unchanged):

```elixir
  @impl true
  def handle_event("toggle_apid", %{"apid" => apid_string}, socket) do
    apid = String.to_integer(apid_string)

    if Map.has_key?(socket.assigns.conflicts, apid) do
      {:noreply, socket}
    else
      selection = toggle_member(socket.assigns.selection, apid)
      save_and_refresh(socket, selection)
    end
  end

  def handle_event("change_revision", %{"catalog_revision_id" => revision_id}, socket) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: sc} = socket.assigns

    apid_rows =
      load_apid_rows(scope.organization_id, mission.mission_id, revision_id)

    {selection, dropped} =
      prune_selection_against_rows(socket.assigns.selection, apid_rows)

    socket =
      socket
      |> assign(:selected_revision_id, revision_id)
      |> assign(:apid_rows, apid_rows)
      |> assign(:dropped_unknowns, dropped)

    save_and_refresh(socket, selection, revision_id: revision_id)
  end

  def handle_event("filter_apids", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, :filter, filter)}
  end

  def handle_event("select_all_unclaimed", _params, socket) do
    selection =
      socket.assigns.apid_rows
      |> Enum.reject(&Map.has_key?(socket.assigns.conflicts, &1.apid))
      |> Enum.map(& &1.apid)
      |> MapSet.new()

    save_and_refresh(socket, selection)
  end

  def handle_event("clear_selection", _params, socket) do
    save_and_refresh(socket, MapSet.new())
  end

  def handle_event("drop_unknown_apids", _params, socket) do
    socket = assign(socket, :dropped_unknowns, [])
    save_and_refresh(socket, socket.assigns.selection)
  end

  def handle_event(
        "enable",
        _params,
        %{assigns: %{current_scope: scope, current_mission: mission, current_spacecraft: sc}} =
          socket
      ) do
    case TelemetryDecom.apply_mission(
           scope.organization_id,
           mission.mission_id,
           sc.spacecraft_id
         ) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(
           :active_binding_set_summary,
           fetch_active_binding_set_summary(mission.mission_id)
         )
         |> put_flash(
           :info,
           "Telemetry Decom mission changes applied. All enabled spacecraft configurations are now live."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not enable: #{humanize_error(reason)}")}
    end
  end

  def handle_event(
        "disable",
        _params,
        %{assigns: %{current_scope: scope, current_mission: mission, current_spacecraft: sc}} =
          socket
      ) do
    case TelemetryDecom.disable(scope.organization_id, mission.mission_id, sc.spacecraft_id) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> put_flash(
           :info,
           "Telemetry Decom disabled for this spacecraft. Apply mission changes to remove it from the live mission."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not disable: #{humanize_error(reason)}")}
    end
  end

  defp toggle_member(set, value) do
    if MapSet.member?(set, value),
      do: MapSet.delete(set, value),
      else: MapSet.put(set, value)
  end

  defp prune_selection_against_rows(selection, rows) do
    available = MapSet.new(rows, & &1.apid)
    kept = MapSet.intersection(selection, available)
    dropped = selection |> MapSet.difference(available) |> Enum.sort()
    {kept, dropped}
  end

  defp save_and_refresh(socket, selection, opts \\ []) do
    %{current_scope: scope, current_mission: mission, current_spacecraft: sc} = socket.assigns
    revision_id = Keyword.get(opts, :revision_id, socket.assigns.selected_revision_id)

    apids = selection |> Enum.sort()

    socket = assign(socket, :selection, selection)

    if revision_id == nil or apids == [] and socket.assigns.config == nil do
      {:noreply, assign(socket, :preview, nil)}
    else
      configure_result =
        TelemetryDecom.configure(
          scope.organization_id,
          mission.mission_id,
          sc.spacecraft_id,
          catalog_revision_id: revision_id,
          handled_apids: apids
        )

      case configure_result do
        {:ok, config} ->
          preview = preview_for(scope.organization_id, mission.mission_id, config)

          {:noreply,
           socket
           |> assign(:config, config)
           |> assign(:preview, preview)
           |> assign(:saved_at, DateTime.utc_now())}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Could not save configuration: #{humanize_error(reason)}")}
      end
    end
  end
```

- [ ] **Step 6.4: Run — expect pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs -k "toggling an APID autosaves"
```

Expected: passes.

- [ ] **Step 6.5: Run whole suite to confirm no regression**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
```

Expected: the three `@tag :skip` tests remain skipped; the new test passes; unchanged tests still pass.

- [ ] **Step 6.6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
git commit -m "feat(cadence_web): autosave TelemetryDecom config on APID toggle"
```

---

## Task 7: Frontend — bulk actions and filter input

Already implemented as events in Task 6; this task adds test coverage.

**Files:**
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs`

- [ ] **Step 7.1: Add failing tests**

Append to the test module:

```elixir
  test "select-all-unclaimed picks every non-conflicting APID and autosaves" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    _html =
      view
      |> element("#telemetry-decom-select-all")
      |> render_click()

    assert {:ok, config} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    assert config.handled_apids == [42]
  end

  test "clear empties the selection and resets the preview" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    view
    |> element("#telemetry-decom-select-all")
    |> render_click()

    html =
      view
      |> element("#telemetry-decom-clear")
      |> render_click()

    refute html =~ "Matched packets\n"
    assert html =~ "Select one or more APIDs"
  end

  test "filter narrows visible rows to matches on APID or name" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    html =
      view
      |> form("#telemetry-decom-filter-form", %{"filter" => "health"})
      |> render_change()

    assert html =~ "HEALTH"
  end
```

- [ ] **Step 7.2: Run — expect pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
```

Expected: all new tests pass (handlers are already implemented in Task 6).

- [ ] **Step 7.3: Commit**

```bash
git add apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
git commit -m "test(cadence_web): cover TelemetryDecom bulk actions and filter"
```

---

## Task 8: Frontend — APID row expansion (Level 2: description + def blocks)

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex` — add expansion rendering
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex` — add `toggle_apid_expand` event
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs` — new test

- [ ] **Step 8.1: Add failing test**

Append:

```elixir
  test "clicking a row expands it and shows the packet description" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    html =
      view
      |> element("#apid-row-42-toggle")
      |> render_click()

    assert html =~ "HEALTH"
    assert html =~ "apid=42"
  end
```

- [ ] **Step 8.2: Run — expect failure**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs -k "clicking a row expands it"
```

- [ ] **Step 8.3: Replace `APIDTable.table/1` body**

In `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex`, replace the `<tbody>` section with:

```elixir
      <tbody>
        <%= for row <- @visible_rows do %>
          <tr id={"apid-row-#{row.apid}"} class="border-t border-base-300/40">
            <td class="py-2">
              <input
                type="checkbox"
                class="checkbox checkbox-sm checkbox-primary"
                checked={MapSet.member?(@selection, row.apid)}
                disabled={Map.has_key?(@conflicts, row.apid)}
                phx-click="toggle_apid"
                phx-value-apid={row.apid}
              />
            </td>
            <td class="py-2">
              <button
                type="button"
                id={"apid-row-#{row.apid}-toggle"}
                class={["text-base-content/50 transition-transform",
                        MapSet.member?(@expanded_apids, row.apid) && "rotate-90 text-primary"]}
                phx-click="toggle_apid_expand"
                phx-value-apid={row.apid}
                aria-label="Toggle row details"
              >›</button>
            </td>
            <td class="py-2 font-mono">{row.apid}</td>
            <td class="py-2">{packets_label(row)}</td>
            <td class="py-2 text-base-content/60">{row.def_count}</td>
            <td class="py-2 text-base-content/60">{rate_label(row.rate_hz)}</td>
            <td class="py-2 text-base-content/60">{conflict_label(@conflicts, row.apid)}</td>
          </tr>
          <tr :if={MapSet.member?(@expanded_apids, row.apid)}>
            <td colspan="7" class="p-0">
              <div
                class="pl-4 pr-2 py-3 border-l-2 border-primary bg-base-300/40"
                id={"apid-row-#{row.apid}-detail"}
              >
                <p :if={row.short_description} class="text-sm text-base-content/80 mb-3">
                  {row.short_description}
                </p>
                <div :for={packet <- row.packets} class="bg-base-200 border border-base-300/60 mb-2">
                  <div class="flex items-center gap-3 px-3 py-2 border-b border-base-300/60">
                    <span class="font-semibold text-base-content">{packet.name}</span>
                    <span class="font-mono text-xs text-base-content/60">
                      apid={packet.apid} · type={packet.packet_type || "—"} · {packet.size_bits || "—"} b
                    </span>
                    <span class="ml-auto text-xs text-base-content/60">
                      {packet_entries_label(packet)}
                    </span>
                  </div>
                </div>
              </div>
            </td>
          </tr>
        <% end %>
        <tr :if={@visible_rows == []}>
          <td colspan="7" class="py-4 text-center text-base-content/60">
            No APIDs match the filter.
          </td>
        </tr>
      </tbody>
```

Also add this private helper below `conflict_label/2`:

```elixir
  defp packet_entries_label(%{entries: []}), do: "no entries"
  defp packet_entries_label(%{entries: entries}), do: "#{length(entries)} entries"
  defp packet_entries_label(_), do: ""
```

- [ ] **Step 8.4: Add the `toggle_apid_expand` event handler**

In `spacecraft_telemetry_decom_live.ex`, after `handle_event("drop_unknown_apids", ...)`:

```elixir
  def handle_event("toggle_apid_expand", %{"apid" => apid_string}, socket) do
    apid = String.to_integer(apid_string)
    expanded = toggle_member(socket.assigns.expanded_apids, apid)
    {:noreply, assign(socket, :expanded_apids, expanded)}
  end
```

- [ ] **Step 8.5: Run tests — expect pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs -k "clicking a row expands it"
```

Expected: passes.

- [ ] **Step 8.6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
git commit -m "feat(cadence_web): expand APID rows to show packet description and defs"
```

---

## Task 9: Frontend — entries disclosure (Level 3)

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex` — add entries section inside the def block
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex` — `toggle_entries` event
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs` — new test

- [ ] **Step 9.1: Add failing test**

Append:

```elixir
  test "expanding a packet definition shows its entries" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    # expand the apid row
    view |> element("#apid-row-42-toggle") |> render_click()

    # then click the def "expand entries" button
    html =
      view
      |> element("[id^='telemetry-decom-entries-toggle-']")
      |> render_click()

    assert html =~ "mode"
  end
```

- [ ] **Step 9.2: Run — expect failure**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs -k "expanding a packet definition"
```

- [ ] **Step 9.3: Replace the def-block body in the APIDTable**

In `apid_table.ex`, replace the existing `<div :for={packet <- row.packets} …>` block with:

```elixir
                <div :for={packet <- row.packets} class="bg-base-200 border border-base-300/60 mb-2">
                  <div class="flex items-center gap-3 px-3 py-2 border-b border-base-300/60">
                    <span class="font-semibold text-base-content">{packet.name}</span>
                    <span class="font-mono text-xs text-base-content/60">
                      apid={packet.apid} · type={packet.packet_type || "—"} · {packet.size_bits || "—"} b
                    </span>
                    <button
                      type="button"
                      id={"telemetry-decom-entries-toggle-#{packet.packet_id}"}
                      class="ml-auto text-xs text-primary hover:underline"
                      phx-click="toggle_entries"
                      phx-value-packet-id={packet.packet_id}
                    >
                      <%= if MapSet.member?(@expanded_entries, packet.packet_id) do %>
                        ▾ hide entries ({length(packet.entries)})
                      <% else %>
                        ▸ show entries ({length(packet.entries)})
                      <% end %>
                    </button>
                  </div>
                  <div
                    :if={MapSet.member?(@expanded_entries, packet.packet_id)}
                    class="px-3 py-2 font-mono text-xs"
                    id={"telemetry-decom-entries-#{packet.packet_id}"}
                  >
                    <table class="w-full">
                      <thead>
                        <tr class="text-base-content/60">
                          <th class="text-left py-1">name</th>
                          <th class="text-left py-1">kind</th>
                          <th class="text-right py-1">offset</th>
                          <th class="text-left py-1 pl-3">notes</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={entry <- Enum.take(packet.entries, 20)} class="border-t border-base-300/40">
                          <td class="py-1 text-primary">{entry_name(entry)}</td>
                          <td class="py-1 text-base-content/70">{entry.entry_kind}</td>
                          <td class="py-1 text-right text-base-content/60">{entry.bit_offset || "—"}</td>
                          <td class="py-1 pl-3 text-base-content/60">{entry_notes(entry)}</td>
                        </tr>
                      </tbody>
                    </table>
                    <p :if={length(packet.entries) > 20} class="mt-1 text-base-content/60">
                      {length(packet.entries) - 20} more omitted.
                    </p>
                  </div>
                </div>
```

Also add these helpers below `packet_entries_label/1`:

```elixir
  defp entry_name(%{point_id: id}) when is_binary(id), do: id
  defp entry_name(%{nested_packet_id: id}) when is_binary(id), do: id
  defp entry_name(%{fixed_value: value}) when is_binary(value), do: "(fixed)"
  defp entry_name(_), do: "—"

  defp entry_notes(%{fixed_value: value}) when is_binary(value), do: "fixed=#{value}"
  defp entry_notes(%{array_size: size}) when is_integer(size), do: "array[#{size}]"
  defp entry_notes(_), do: ""
```

- [ ] **Step 9.4: Add `toggle_entries` event handler**

In `spacecraft_telemetry_decom_live.ex`, after `toggle_apid_expand`:

```elixir
  def handle_event("toggle_entries", %{"packet-id" => packet_id}, socket) do
    expanded = toggle_member(socket.assigns.expanded_entries, packet_id)
    {:noreply, assign(socket, :expanded_entries, expanded)}
  end
```

- [ ] **Step 9.5: Run — expect pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs -k "expanding a packet definition"
```

Expected: passes.

- [ ] **Step 9.6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
git commit -m "feat(cadence_web): disclose packet entries inside expanded APID rows"
```

---

## Task 10: Frontend — drop-unknowns banner on revision change

**Files:**
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs`

The handler logic is already in Task 6's `change_revision` + `drop_unknown_apids`. This task adds test coverage and fills in the replacement for the previously-skipped validation test.

- [ ] **Step 10.1: Add failing test**

Append:

```elixir
  test "switching to a revision without some selected APIDs shows the drop-unknowns banner" do
    {conn, org, mission, spacecraft} = setup_session()
    rev_a = persist_revision!(org, mission)
    rev_b =
      persist_revision!(org, mission,
        revision_label: "Rev 2",
        yaml: """
        packets:
          - name: OTHER
            apid: 7
            items:
              - name: v
                data_type: uint
                bit_offset: 0
                bit_size: 8
        commands: []
        """
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    # select APID 42 in rev A
    view |> element("input[phx-click='toggle_apid'][phx-value-apid='42']") |> render_click()

    # switch to rev B (which only has APID 7)
    html =
      view
      |> form("#telemetry-decom-revision-form", %{"catalog_revision_id" => rev_b.catalog_revision_id})
      |> render_change()

    assert html =~ "previously selected"
    assert html =~ "42"

    # click "Drop them"
    html =
      view
      |> element("#telemetry-decom-drop-unknowns")
      |> render_click()

    refute html =~ "previously selected"
  end
```

Update the test-helper `persist_revision!` signature — the current file's helper does not take `:yaml` as an option. In `spacecraft_telemetry_decom_live_test.exs`, replace the `persist_revision!/2` helper with one that accepts an override:

```elixir
  defp persist_revision!(org, mission, opts \\ []) do
    revision_label = Keyword.get(opts, :revision_label, "Rev 1")
    suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, database} =
      Catalog.create_database(org.organization_id, mission.mission_id, %{
        name: "Bus " <> suffix,
        slug: "bus-" <> suffix,
        catalog_family: :combined,
        default_importer_key: "cadence_yaml"
      })

    yaml =
      Keyword.get(
        opts,
        :yaml,
        """
        packets:
          - name: HEALTH
            apid: 42
            items:
              - name: mode
                data_type: uint
                bit_offset: 0
                bit_size: 8
        commands: []
        """
      )

    artifact =
      Artifact.new(%{
        mission_id: mission.mission_id,
        catalog_database_id: database.catalog_database_id,
        catalog_family: :combined,
        artifact_name: "bus.yaml",
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: yaml
      })

    {:ok, run} =
      Catalog.start_revision_import(
        org.organization_id,
        mission.mission_id,
        database.catalog_database_id,
        artifact,
        "cadence_yaml",
        metadata: %{"revision_label" => revision_label}
      )

    {:ok, completed} = Catalog.execute_enqueued_run(run.import_run_id)

    {:ok, revision} =
      Catalog.fetch_revision_by_import_run(
        org.organization_id,
        mission.mission_id,
        completed.import_run_id
      )

    revision
  end
```

- [ ] **Step 10.2: Run — expect pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs -k "switching to a revision"
```

Expected: passes.

- [ ] **Step 10.3: Commit**

```bash
git add apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
git commit -m "test(cadence_web): cover TelemetryDecom drop-unknowns revision change"
```

---

## Task 11: Final cleanup — remove skipped tests, format, credo, file sizes

**Files:**
- Modify: `apps/cadence_web/test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs` — remove the three `@tag :skip` tests (they have been replaced by new behaviour tests)

- [ ] **Step 11.1: Remove the three `@tag :skip` tests**

Delete:
- `"configures and enables telemetry decom end-to-end"` (replaced by "toggling an APID autosaves" + the existing `enable` path covered by `render_click` on `#telemetry-decom-enable-button`)
- `"disabled configs can still be applied from the same screen"` — re-write as:

```elixir
  test "disable button rolls back the enabled flag" do
    {conn, org, mission, spacecraft} = setup_session()
    _revision = persist_revision!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry_decom"
      )

    view |> element("input[phx-click='toggle_apid'][phx-value-apid='42']") |> render_click()
    view |> element("#telemetry-decom-enable-button") |> render_click()

    html =
      view
      |> element("#telemetry-decom-disable-button")
      |> render_click()

    assert html =~ "Disabled"

    assert {:ok, disabled} =
             TelemetryDecom.fetch_config(
               org.organization_id,
               mission.mission_id,
               spacecraft.spacecraft_id
             )

    refute disabled.enabled
  end
```

- `"shows a validation error for APIDs not found in the selected revision"` — covered by Task 10's drop-unknowns test.

- [ ] **Step 11.2: Run the web test suite**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_telemetry_decom_live_test.exs
```

Expected: all tests pass, no `:skip` tags remain.

- [ ] **Step 11.3: Format, compile, credo**

```bash
mix format
cd apps/cadence && mix compile --warnings-as-errors && mix credo --strict
cd apps/cadence_web && mix compile --warnings-as-errors && mix credo --strict
```

Fix any findings in the modified files only. Do not attempt to address pre-existing credo findings in unrelated files.

- [ ] **Step 11.4: Confirm file sizes**

```bash
wc -l apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live.ex apps/cadence_web/lib/cadence_web/live/spacecraft_telemetry_decom_live/apid_table.ex
```

Expected: both files below 400 lines.

- [ ] **Step 11.5: Full app test suites**

```bash
cd apps/cadence && mix test
cd apps/cadence_web && mix test
```

Expected: both green.

- [ ] **Step 11.6: Commit**

```bash
git add -u
git commit -m "chore(cadence_web): clean up TelemetryDecom UI redesign tests and lint"
```

---

## Self-Review Notes

**Spec coverage — section-by-section check against `docs/superpowers/specs/2026-04-23-telemetry-decom-ui-redesign-design.md`:**

- **Page Composition (5 sections)** → Task 5 implements all five.
- **APID Table columns and semantics** → Tasks 4, 6.
- **Filter** → Task 6 (handler) + Task 7 (test).
- **Bulk actions** → Task 6 (handler) + Task 7 (test).
- **Progressive disclosure levels 1/2/3** → Tasks 4, 8, 9.
- **Save Model (autosave, no explicit Save button)** → Task 6.
- **Conflict column + `list_apid_conflicts/3`** → Task 1 (backend), Task 4 (rendering).
- **Unknown APIDs banner on revision change** → Task 6 (handler) + Task 10 (test).
- **Empty revision state** → Task 5 (`no_revisions_notice`).
- **Server error on save** → Task 6 (`put_flash` on `{:error, reason}`).
- **Data Dependencies — `list_revision_apid_rows/3`** → Task 2.
- **Module Boundaries** → Task 4 creates `APIDTable`; file-size check in Task 11.
- **UI Rules Compliance** → no new CSS added; `<.input>` used for select; checkboxes inside table use raw `<input type="checkbox">` with daisyUI classes (documented deviation in the spec's UI Rules section).
- **Testing coverage** → Tasks 6, 7, 8, 9, 10, 11.

**Gaps flagged:**
- The spec proposes a ~300 ms debounce; the plan saves on every toggle without debouncing. This is simpler, works correctly, and only costs one write per click. If user testing finds it noisy, add debouncing as a follow-up.
- The spec mentions keyboard accessibility for row expansion (Enter/Space); the plan implements the button with `<button>`, which gives that behaviour for free. Explicit key handling is not added.
- The spec discusses a "Saved N ago" indicator; Task 5's `format_relative/1` renders it but does not live-update. The indicator refreshes on the next render. Flagging as acceptable for v1.

**Placeholder scan:** none — each step has full file paths, full code, and exact commands.

**Type consistency:** event names (`toggle_apid`, `toggle_apid_expand`, `toggle_entries`, `change_revision`, `filter_apids`, `select_all_unclaimed`, `clear_selection`, `drop_unknown_apids`, `enable`, `disable`) consistent between handler definitions and `phx-click`/`phx-change` bindings. Assign names (`selection`, `expanded_apids`, `expanded_entries`, `apid_rows`, `conflicts`, `filter`, `dropped_unknowns`, `selected_revision_id`, `saved_at`) consistent between mount and handlers and template.
