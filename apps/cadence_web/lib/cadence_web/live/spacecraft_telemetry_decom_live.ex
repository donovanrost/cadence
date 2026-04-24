defmodule CadenceWeb.SpacecraftTelemetryDecomLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.Catalog
  alias CadenceWeb.SpacecraftTelemetryDecomLive.APIDTable

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
    selected_revision_id = (config && config.catalog_revision_id) || first_option_value(revisions)

    {apid_rows, points_by_id} = load_apid_rows(organization_id, mission_id, selected_revision_id)
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
     |> assign(:points_by_id, points_by_id)
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

  defp load_apid_rows(_organization_id, _mission_id, nil), do: {[], %{}}

  defp load_apid_rows(organization_id, mission_id, revision_id) do
    case TelemetryDecom.list_revision_apid_rows(organization_id, mission_id, revision_id) do
      {:ok, %{rows: rows, points_by_id: points_by_id}} -> {rows, points_by_id}
      {:error, _} -> {[], %{}}
    end
  end

  defp selection_from_config(nil), do: MapSet.new()
  defp selection_from_config(%{handled_apids: apids}), do: MapSet.new(apids)

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
    %{current_scope: scope, current_mission: mission, current_spacecraft: _sc} = socket.assigns

    {apid_rows, points_by_id} =
      load_apid_rows(scope.organization_id, mission.mission_id, revision_id)

    {selection, dropped} =
      prune_selection_against_rows(socket.assigns.selection, apid_rows)

    socket =
      socket
      |> assign(:selected_revision_id, revision_id)
      |> assign(:apid_rows, apid_rows)
      |> assign(:points_by_id, points_by_id)
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

  def handle_event("toggle_apid_expand", %{"apid" => apid_string}, socket) do
    apid = String.to_integer(apid_string)
    expanded = toggle_member(socket.assigns.expanded_apids, apid)
    {:noreply, assign(socket, :expanded_apids, expanded)}
  end

  def handle_event("toggle_entries", %{"packet-id" => packet_id}, socket) do
    expanded = toggle_member(socket.assigns.expanded_entries, packet_id)
    {:noreply, assign(socket, :expanded_entries, expanded)}
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

    if revision_id == nil or (apids == [] and socket.assigns.config == nil) do
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
              points_by_id={@points_by_id}
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
  attr :points_by_id, :map, required: true

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
        points_by_id={@points_by_id}
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
        {length(@dropped)} previously selected {if length(@dropped) == 1, do: "APID is", else: "APIDs are"}
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

  defp first_option_value([]), do: nil
  defp first_option_value([{_, value} | _]), do: value

  defp list_telemetry_revisions(organization_id, mission_id) do
    Catalog.list_revisions(organization_id, mission_id)
    |> Enum.filter(&(&1.telemetry_snapshot_id != nil))
    |> Enum.map(fn revision ->
      {"#{revision.revision_label} (##{revision.revision_number})", revision.catalog_revision_id}
    end)
  end

  defp preview_for(_organization_id, _mission_id, nil), do: nil

  defp preview_for(organization_id, mission_id, config) do
    case TelemetryDecom.preview(organization_id, mission_id, config) do
      {:ok, preview} -> Map.put(preview, :config, config)
      {:error, _reason} -> nil
    end
  end

  defp fetch_active_binding_set_summary(mission_id) do
    case Cadence.fetch_active_binding_set_activation(mission_id) do
      {:ok, activation} ->
        %{
          binding_set_id: activation.binding_set_id,
          binding_set_version: activation.binding_set_version
        }

      {:error, _} ->
        nil
    end
  end

  defp dot_status(:applied), do: :nominal
  defp dot_status(:configured), do: :info
  defp dot_status(:outdated), do: :warning
  defp dot_status(:disabled), do: :offline
  defp dot_status(:not_configured), do: :offline

  defp status_label(:applied), do: "Applied"
  defp status_label(:configured), do: "Configured — not yet applied"
  defp status_label(:outdated), do: "Applied configuration is out of date"
  defp status_label(:disabled), do: "Disabled"
  defp status_label(:not_configured), do: "Not configured"

  defp status_description(:applied),
    do: "This configuration is live on the mission."

  defp status_description(:configured),
    do: "Choices are saved. Apply mission changes to publish them."

  defp status_description(:outdated),
    do:
      "The saved configuration differs from what is live. Apply mission changes to publish the latest state."

  defp status_description(:disabled),
    do:
      "This spacecraft is excluded from Telemetry Decom. Apply mission changes to publish the disabled state."

  defp status_description(:not_configured),
    do: "Choose a catalog revision and handled APIDs, then apply mission changes."

  defp diagnostic_dot(:error), do: :critical
  defp diagnostic_dot(:warning), do: :warning
  defp diagnostic_dot(_), do: :info

  defp format_apids(apids), do: APIDSelection.format(apids)

  defp humanize_error({:missing_attr, attr}), do: "missing #{attr}"
  defp humanize_error(:handled_apids_required), do: "handled APIDs are required"
  defp humanize_error(:no_enabled_configs), do: "no enabled spacecraft configurations"
  defp humanize_error({:invalid_apid_token, token}), do: "invalid APID token #{inspect(token)}"
  defp humanize_error({:invalid_apid_range, token}), do: "invalid APID range #{inspect(token)}"

  defp humanize_error({:handled_apids_not_in_revision, apids}),
    do: "APIDs not found in this revision: #{format_apids(apids)}"

  defp humanize_error(:spacecraft_runtime_scope_ambiguous),
    do: "spacecraft runtime scope is ambiguous"

  defp humanize_error(%Ecto.Changeset{} = changeset),
    do: changeset |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end) |> inspect()

  defp humanize_error(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp humanize_error(other), do: inspect(other)
end
