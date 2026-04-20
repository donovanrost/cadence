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
         |> redirect(to: ~p"/missions/#{mission.mission_id}/catalog")}
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
