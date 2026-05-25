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
           to: ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start import: #{inspect(reason)}")}
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
        <.breadcrumbs items={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Catalog", ~p"/missions/#{@current_mission.mission_id}/catalog"},
          {@artifact.artifact_name, nil}
        ]} />
        <h1 class="text-2xl font-bold text-base-content mt-2">{@artifact.artifact_name}</h1>
      </div>

      <.artifact_metadata_card current_mission={@current_mission} artifact={@artifact} />

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
            href={
              ~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@artifact.artifact_id}/download"
            }
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
        <.artifact_runs_empty />
      <% else %>
        <.artifact_runs_table current_mission={@current_mission} runs={@runs} />
      <% end %>
    </div>
    """
  end

  defp artifact_runs_empty(assigns) do
    ~H"""
    <div class="card bg-base-200">
      <div class="card-body p-4 text-sm text-base-content/60">
        No runs yet.
      </div>
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :runs, :list, required: true

  defp artifact_runs_table(assigns) do
    ~H"""
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
              <%= if run.completed_at,
                do: Calendar.strftime(run.completed_at, "%Y-%m-%d %H:%M:%S"),
                else: "—" %>
            </td>
            <td class="text-right">
              <.action_menu>
                <:action>
                  <.link navigate={
                    ~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{run.import_run_id}"
                  }>
                    View run
                  </.link>
                </:action>
              </.action_menu>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
