defmodule CadenceWeb.OpsFleetPlanningRunLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"fleet_planning_run_id" => run_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Fleet Planning Run")
     |> assign(:ops_nav_item, :planning)
     |> assign(:fleet_planning_run_id, run_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-fleet-planning-run-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="fleet_planning_run"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"fleet_planning_run_id" => @fleet_planning_run_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
