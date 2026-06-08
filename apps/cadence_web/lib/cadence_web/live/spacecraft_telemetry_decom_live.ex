defmodule CadenceWeb.SpacecraftTelemetryDecomLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecom.APIDSelection
  alias Cadence.Catalog
  alias CadenceWeb.SpacecraftTelemetryDecomLive.Components

  @impl true
  def mount(params, _session, socket) do
    if supported_application?(Map.get(params, "application_key")) do
      mount_application(socket)
    else
      {:ok,
       socket
       |> put_flash(:error, "Application not found.")
       |> push_navigate(
         to:
           ~p"/missions/#{socket.assigns.current_mission.mission_id}/spacecraft/#{socket.assigns.current_spacecraft.spacecraft_id}/applications"
       )}
    end
  end

  defp supported_application?(nil), do: true
  defp supported_application?("telemetry_decom"), do: true
  defp supported_application?(_application_key), do: false

  defp mount_application(socket) do
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
     |> assign(:filter, "")
     |> assign(:dropped_unknowns, [])
     |> assign(:preview, preview_for(organization_id, mission_id, config))
     |> assign(:active_binding_set_summary, fetch_active_binding_set_summary(mission_id))
     |> assign(:saved_at, config && config.updated_at)}
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
      |> assign(:selection, selection)

    if dropped == [] do
      save_and_refresh(socket, selection, revision_id: revision_id)
    else
      {:noreply, socket}
    end
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
           |> assign(:saved_at, config.updated_at)}

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
        <.breadcrumbs items={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Spacecraft", ~p"/missions/#{@current_mission.mission_id}/spacecraft"},
          {@current_spacecraft.display_name,
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}"},
          {"Applications",
           ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{@current_spacecraft.spacecraft_id}/applications"},
          {"Telemetry Decom", nil}
        ]} />
        <h1 class="text-2xl font-bold text-base-content mt-2">Telemetry Decom</h1>
        <p class="text-sm text-base-content/60 mt-1">
          Application packet claims and publication state for
          <span class="font-semibold text-base-content">{@current_spacecraft.display_name}</span>.
        </p>
      </div>

      <div class="card bg-base-200" id="telemetry-decom-card">
        <div class="card-body p-6 space-y-4">
          <Components.status_section
            config={@config}
            active={@active_binding_set_summary}
            saved_at={@saved_at}
          />
          <div class="border-t border-base-300/30"></div>

          <%= if @revisions == [] do %>
            <Components.no_revisions_notice current_mission={@current_mission} />
          <% else %>
            <Components.revision_section
              revisions={@revisions}
              selected_revision_id={@selected_revision_id}
            />
            <div class="border-t border-base-300/30"></div>

            <Components.dropped_unknowns_banner dropped={@dropped_unknowns} />

            <Components.apid_section
              rows={@apid_rows}
              selection={@selection}
              conflicts={@conflicts}
              expanded_apids={@expanded_apids}
              filter={@filter}
              points_by_id={@points_by_id}
            />
            <div class="border-t border-base-300/30"></div>

            <Components.preview_section preview={@preview} />
            <div class="border-t border-base-300/30"></div>

            <Components.apply_section config={@config} />
          <% end %>
        </div>
      </div>
    </div>
    """
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
