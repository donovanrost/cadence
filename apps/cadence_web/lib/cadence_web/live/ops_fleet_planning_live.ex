defmodule CadenceWeb.OpsFleetPlanningLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Fleet Planning")
     |> assign(:ops_nav_item, :planning)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-fleet-planning-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="fleet_planning"
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
