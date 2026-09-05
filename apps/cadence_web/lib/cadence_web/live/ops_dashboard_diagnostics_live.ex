defmodule CadenceWeb.OpsDashboardDiagnosticsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"dashboard_id" => dashboard_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard Diagnostics")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:dashboard_id, dashboard_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-diagnostics-page-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_diagnostics"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"dashboard_id" => @dashboard_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
