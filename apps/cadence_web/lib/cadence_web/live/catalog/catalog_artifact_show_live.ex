defmodule CadenceWeb.CatalogArtifactShowLive do
  @moduledoc false

  # Authz note: Catalog management currently permitted for any active org member.
  use CadenceWeb, :live_view

  alias Cadence.Catalog
  alias Cadence.Catalog.Events
  alias Phoenix.LiveView.JS

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
         |> assign_runs(runs)}

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
      {:noreply, assign_runs(socket, upsert_run(socket.assigns.runs, run))}
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="catalog-artifact-show-page" class="space-y-6">
        <.page_header
          title={@artifact.artifact_name}
          breadcrumbs={[
            {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
            {"Catalog", ~p"/missions/#{@current_mission.mission_id}/catalog"},
            {@artifact.artifact_name, nil}
          ]}
        />

        <.vue
          id="catalog-artifact-show-component"
          v-component="CatalogArtifactShow"
          artifact={@artifact_show_props.artifact}
          runs={@artifact_show_props.runs}
          v-on:reimport={JS.push("reimport")}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp assign_runs(socket, runs) do
    mission_id = socket.assigns.current_mission.mission_id
    artifact = socket.assigns.artifact

    socket
    |> assign(:runs, runs)
    |> assign(:artifact_show_props, artifact_show_props(artifact, runs, mission_id))
  end

  defp artifact_show_props(artifact, runs, mission_id) do
    %{
      artifact: %{
        format_key: artifact.format_key,
        media_type: artifact.media_type || "—",
        content_sha256: artifact.content_sha256,
        uploaded_at: Calendar.strftime(artifact.uploaded_at, "%Y-%m-%d %H:%M:%S UTC"),
        download_href:
          ~p"/missions/#{mission_id}/catalog/artifacts/#{artifact.artifact_id}/download"
      },
      runs: Enum.map(runs, &run_dto(&1, mission_id))
    }
  end

  defp run_dto(run, mission_id) do
    %{
      id: "catalog-artifact-run-#{run.import_run_id}",
      actions_id: "#{run.import_run_id}-actions",
      status: status_badge(run.status),
      status_label: status_label(run.status),
      started_at: Calendar.strftime(run.started_at, "%Y-%m-%d %H:%M:%S"),
      completed_at: completed_at(run.completed_at),
      href: ~p"/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }
  end

  defp completed_at(nil), do: "—"
  defp completed_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp status_badge(:running), do: "info"
  defp status_badge(:completed), do: "ready"
  defp status_badge(:failed), do: "blocked"
  defp status_badge(_status), do: "info"

  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:failed), do: "Failed"
  defp status_label(status), do: status |> to_string() |> String.capitalize()
end
