defmodule CadenceWeb.OpsDashboardSnapshotLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"snapshot_id" => snapshot_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard Snapshot")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:snapshot_id, snapshot_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-snapshot-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_snapshot"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"snapshot_id" => @snapshot_id}}
        v-ssr={false}
        class="h-full"
      />
    </Layouts.app>
    """
  end
end
