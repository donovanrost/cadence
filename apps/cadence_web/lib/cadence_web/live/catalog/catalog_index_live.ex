defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  # Authz note: Catalog upload currently permitted for any active org member.
  # Tighten once finer-grained catalog capability is defined.
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
    update(socket, :latest_runs, &merge_run(&1, run))
  end

  defp merge_run(latest, run) do
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
                <.artifact_run_cell
                  run={Map.get(@latest_runs, artifact.artifact_id)}
                  current_mission={@current_mission}
                />
              </td>
              <td class="text-right">
                <.artifact_row_actions
                  artifact={artifact}
                  latest_runs={@latest_runs}
                  current_mission={@current_mission}
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  attr :run, :map, default: nil
  attr :current_mission, :map, required: true

  defp artifact_run_cell(%{run: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 text-xs">—</span>
    """
  end

  defp artifact_run_cell(assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@run.import_run_id}"
      }
      class="inline-flex"
    >
      <.import_run_status_badge status={@run.status} />
    </.link>
    """
  end

  attr :artifact, :map, required: true
  attr :latest_runs, :map, required: true
  attr :current_mission, :map, required: true

  defp artifact_row_actions(assigns) do
    ~H"""
    <.action_menu>
      <:action>
        <.link navigate={
          ~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@artifact.artifact_id}"
        }>
          View artifact
        </.link>
      </:action>
      <:action :if={Map.has_key?(@latest_runs, @artifact.artifact_id)}>
        <.link navigate={
          ~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@latest_runs[@artifact.artifact_id].import_run_id}"
        }>
          View latest run
        </.link>
      </:action>
    </.action_menu>
    """
  end
end
