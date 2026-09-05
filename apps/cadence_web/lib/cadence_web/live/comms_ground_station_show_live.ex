defmodule CadenceWeb.CommsGroundStationShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"ground_station_id" => ground_station_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Ground Station")
     |> assign(:nav_item, :comms_ground_stations)
     |> assign(:ground_station_id, ground_station_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-ground-station-show-page">
        <.vue
          id="comms-ground-station-show-component"
          v-component="FederatedFullPageSurface"
          application_key="comms"
          surface_id="ground_station"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id, ground_station_id: @ground_station_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
