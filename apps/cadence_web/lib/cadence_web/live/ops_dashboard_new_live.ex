defmodule CadenceWeb.OpsDashboardNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Dashboard")
     |> assign(:ops_nav_item, :dashboards)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-new-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_new"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
