defmodule CadenceWeb.CatalogImportRunShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Diagnostic
  alias Cadence.Catalog.Events
  alias Cadence.Catalog.Telemetry.{Packet, PacketEntry, Point, Snapshot}

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
          |> assign_snapshots(run)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Import run not found.")
         |> redirect(to: ~p"/missions/#{mission.mission_id}/catalog")}
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
    |> assign(:run, enrich_run_diagnostics(run, telemetry))
    |> assign(:telemetry_snapshot, telemetry)
    |> assign(:command_snapshot, command)
  end

  defp assign_snapshots(socket, run) do
    socket
    |> assign(:run, enrich_run_diagnostics(run, nil))
    |> assign(:telemetry_snapshot, nil)
    |> assign(:command_snapshot, nil)
  end

  defp enrich_run_diagnostics(%{diagnostics: diagnostics} = run, telemetry_snapshot) do
    %{run | diagnostics: resolve_diagnostics(diagnostics, telemetry_snapshot)}
  end

  defp resolve_diagnostics(diagnostics, telemetry_snapshot) when is_list(diagnostics) do
    lookup = telemetry_diagnostic_lookup(telemetry_snapshot)
    Enum.map(diagnostics, &resolve_diagnostic(&1, lookup))
  end

  defp telemetry_diagnostic_lookup(nil), do: nil

  defp telemetry_diagnostic_lookup(%Snapshot{} = snapshot) do
    %{
      packets_by_id: Map.new(snapshot.packets, &{&1.packet_id, &1}),
      points_by_id: Map.new(snapshot.points, &{&1.point_id, &1}),
      types_by_id: Map.new(snapshot.types, &{&1.type_id, &1}),
      packet_entries_by_id: packet_entries_by_id(snapshot.packets)
    }
  end

  defp packet_entries_by_id(packets) do
    for %Packet{} = packet <- packets,
        %PacketEntry{} = entry <- packet.entries,
        into: %{} do
      {entry.packet_entry_id, {packet, entry}}
    end
  end

  defp resolve_diagnostic(%Diagnostic{} = diagnostic, nil), do: diagnostic

  defp resolve_diagnostic(%Diagnostic{} = diagnostic, lookup) do
    metadata = diagnostic.metadata || %{}
    resolution = diagnostic_resolution(metadata, lookup)

    %{diagnostic | metadata: enriched_diagnostic_metadata(metadata, resolution)}
  end

  defp diagnostic_resolution(metadata, lookup) do
    primary_packet = resolved_packet(metadata, lookup)
    {entry_packet, entry} = resolved_entry(metadata, lookup)
    packet = primary_packet || entry_packet
    point = resolved_point(metadata, entry, lookup)
    type = resolved_type(metadata, point, lookup)

    %{packet: packet, entry: entry, point: point, type: type}
  end

  defp enriched_diagnostic_metadata(metadata, resolution) do
    metadata
    |> maybe_put("packet_name", resolution.packet && resolution.packet.name)
    |> maybe_put("entry_name", resolved_entry_name(resolution.entry, resolution.point))
    |> maybe_put("point_name", resolution.point && point_display_name(resolution.point))
    |> maybe_put("type_name", resolution.type && resolution.type.name)
    |> maybe_put("point_id", resolution.point && resolution.point.point_id)
    |> maybe_put("type_id", resolution.type && resolution.type.type_id)
    |> maybe_put(
      "base_type",
      metadata["base_type"] || (resolution.type && Atom.to_string(resolution.type.base_type))
    )
  end

  defp resolved_packet(metadata, lookup) do
    case Map.get(metadata, "packet_id") do
      packet_id when is_binary(packet_id) -> Map.get(lookup.packets_by_id, packet_id)
      _ -> nil
    end
  end

  defp resolved_entry(metadata, lookup) do
    case {Map.get(metadata, "source_kind"), Map.get(metadata, "source_id")} do
      {"packet_entry", source_id} when is_binary(source_id) ->
        Map.get(lookup.packet_entries_by_id, source_id, {nil, nil})

      _ ->
        {nil, nil}
    end
  end

  defp resolved_point(metadata, %PacketEntry{} = entry, lookup) do
    point_id = Map.get(metadata, "point_id") || entry.point_id
    point_id && Map.get(lookup.points_by_id, point_id)
  end

  defp resolved_point(metadata, _entry, lookup) do
    case Map.get(metadata, "point_id") do
      point_id when is_binary(point_id) -> Map.get(lookup.points_by_id, point_id)
      _ -> nil
    end
  end

  defp resolved_type(metadata, %Point{} = point, lookup) do
    type_id = Map.get(metadata, "type_id") || point.type_id
    type_id && Map.get(lookup.types_by_id, type_id)
  end

  defp resolved_type(metadata, _point, lookup) do
    case Map.get(metadata, "type_id") do
      type_id when is_binary(type_id) -> Map.get(lookup.types_by_id, type_id)
      _ -> nil
    end
  end

  defp resolved_entry_name(%PacketEntry{entry_kind: :point_ref}, %Point{} = point),
    do: point_display_name(point)

  defp resolved_entry_name(%PacketEntry{} = entry, _point), do: entry.packet_entry_id
  defp resolved_entry_name(nil, _point), do: nil

  defp point_display_name(%Point{} = point), do: point.display_name || point.name

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Import run"
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Catalog", ~p"/missions/#{@current_mission.mission_id}/catalog"},
          {"Artifact",
           ~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@run.artifact_id}"},
          {"Import run", nil}
        ]}
      >
        <:title_suffix><.import_run_status_badge status={@run.status} /></:title_suffix>
      </.page_header>

      <.run_header run={@run} />

      <.telemetry_runtime_summary_card
        :if={telemetry_runtime_summary(@run)}
        summary={telemetry_runtime_summary(@run)}
      />

      <.diagnostic_list diagnostics={@run.diagnostics} />

      <.failure_block :if={@run.status == :failed} failure_reason={@run.failure_reason} />

      <.snapshots_grid
        :if={@run.status == :completed}
        current_mission={@current_mission}
        telemetry_snapshot={@telemetry_snapshot}
        command_snapshot={@command_snapshot}
      />
    </div>
    """
  end

  attr :run, :map, required: true

  defp run_header(assigns) do
    ~H"""
    <.card>
      <div class="text-sm space-y-1">
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
    </.card>
    """
  end

  attr :summary, :map, required: true

  defp telemetry_runtime_summary_card(assigns) do
    ~H"""
    <.card title="Built-in telemetry runtime">
      <dl class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-sm">
        <div>
          <dt class="text-base-content/60">Catalog packets</dt>
          <dd class="text-lg font-semibold">{@summary["packet_count"]}</dd>
        </div>
        <div>
          <dt class="text-base-content/60">Compiled for built-in telemetry</dt>
          <dd class="text-lg font-semibold">{@summary["built_in_telemetry_packet_count"]}</dd>
        </div>
        <div>
          <dt class="text-base-content/60">Available for custom applications</dt>
          <dd class="text-lg font-semibold">
            {@summary["custom_application_candidate_packet_count"]}
          </dd>
        </div>
      </dl>

      <div
        :if={@summary["custom_application_candidate_packets"] != []}
        class="rounded-lg border border-base-300 bg-base-100/60 p-3 text-sm space-y-2"
      >
        <p class="font-medium">
          Some packets were preserved in the imported catalog but were not compiled into built-in telemetry.
          They remain available for custom application binding.
        </p>
        <ul class="space-y-1">
          <li
            :for={packet <- @summary["custom_application_candidate_packets"]}
            class="font-mono text-xs text-base-content/70"
          >
            {packet["packet_name"] || packet["packet_id"]} ({packet["reason"]})
          </li>
        </ul>
      </div>
    </.card>
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

  defp format_failure_reason({:job_enqueue_failed, reason}),
    do: "Job enqueue failed: #{inspect(reason)}"

  defp format_failure_reason({kind, reason}) when is_atom(kind), do: "#{kind}: #{inspect(reason)}"
  defp format_failure_reason(reason), do: inspect(reason)

  defp telemetry_runtime_summary(%{result_document: %{"telemetry_runtime" => summary}})
       when is_map(summary),
       do: summary

  defp telemetry_runtime_summary(_run), do: nil

  attr :current_mission, :map, required: true
  attr :telemetry_snapshot, :any, required: true
  attr :command_snapshot, :any, required: true

  defp snapshots_grid(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <.snapshot_summary_card
        :if={@telemetry_snapshot}
        title="Telemetry snapshot"
        icon="hero-signal"
        counts={telemetry_counts(@telemetry_snapshot)}
        navigate={
          ~p"/missions/#{@current_mission.mission_id}/catalog/telemetry_snapshots/#{@telemetry_snapshot.snapshot_id}"
        }
      />

      <.snapshot_summary_card
        :if={@command_snapshot}
        title="Command snapshot"
        icon="hero-command-line"
        counts={command_counts(@command_snapshot)}
        navigate={
          ~p"/missions/#{@current_mission.mission_id}/catalog/command_snapshots/#{@command_snapshot.snapshot_id}"
        }
      />
    </div>
    """
  end

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
