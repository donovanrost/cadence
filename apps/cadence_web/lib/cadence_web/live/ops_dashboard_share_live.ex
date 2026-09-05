defmodule CadenceWeb.OpsDashboardShareLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"share_id" => share_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Shared Dashboard")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:share_id, share_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-share-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_share"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"share_id" => @share_id}}
        v-ssr={false}
        class="h-full"
      />
    </Layouts.app>
    """
  end
end
