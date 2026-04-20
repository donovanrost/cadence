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

  defp format_failure_reason({:job_enqueue_failed, reason}),
    do: "Job enqueue failed: #{inspect(reason)}"

  defp format_failure_reason({kind, reason}) when is_atom(kind), do: "#{kind}: #{inspect(reason)}"
  defp format_failure_reason(reason), do: inspect(reason)

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
