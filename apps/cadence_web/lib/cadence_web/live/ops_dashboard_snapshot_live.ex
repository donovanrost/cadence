defmodule CadenceWeb.OpsDashboardSnapshotLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{Document, Management}

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Management.fetch_snapshot(scope.organization_id, mission.mission_id, snapshot_id) do
      {:ok, snapshot} ->
        document = Document.from_map(snapshot.document)

        {:ok,
         socket
         |> assign(:page_title, "#{document.name} Snapshot")
         |> assign(:ops_nav_item, :dashboards)
         |> assign(:active_dashboard_id, snapshot.dashboard_id)
         |> assign(:dashboard_snapshot, snapshot)
         |> assign(:snapshot_document, document)
         |> assign(:dashboard_snapshot_props, dashboard_snapshot_dto(mission, snapshot, document))}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Dashboard snapshot is unavailable: #{inspect(reason)}")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-snapshot-component"
        v-component="OpsDashboardSnapshot"
        snapshot={@dashboard_snapshot_props}
        v-ssr={false}
        class="h-full"
      />
    </Layouts.app>
    """
  end

  defp dashboard_snapshot_dto(mission, snapshot, document) do
    %{
      id: "dashboard-snapshot-page",
      eyebrow: "Read-only snapshot",
      name: document.name,
      policy: %{
        id: "dashboard-snapshot-policy",
        text:
          "Definition version #{snapshot.dashboard_version} · #{snapshot.data_semantics} · #{snapshot.data_visibility}"
      },
      warning:
        "The definition and selectors are immutable. Runtime values are only visible through the declared data policy and may still reflect current data when the time window was not frozen.",
      definition: %{
        id: "dashboard-snapshot-definition",
        items: [
          %{label: "Widgets", value: length(document.placements)},
          %{label: "Captured selectors", value: map_size(snapshot.runtime_context)},
          %{label: "Schema", value: "v#{document.schema_version}"}
        ]
      },
      action: %{
        id: "dashboard-snapshot-open-current",
        label: "Open current dashboard",
        href: ~p"/missions/#{mission.mission_id}/ops/dashboards/#{snapshot.dashboard_id}"
      }
    }
  end
end
