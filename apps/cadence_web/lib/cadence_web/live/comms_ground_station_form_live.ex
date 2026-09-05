defmodule CadenceWeb.CommsGroundStationFormLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"ground_station_id" => ground_station_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Edit Ground Station")
     |> assign(:nav_item, :comms_ground_stations)
     |> assign(:ground_station_id, ground_station_id)}
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Ground Station")
     |> assign(:nav_item, :comms_ground_stations)
     |> assign(:ground_station_id, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-ground-station-form-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id={if(@live_action == :new, do: "ground_station_new", else: "ground_station_edit")}
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={
          if @live_action == :new,
            do: %{mission_id: @current_mission.mission_id},
            else: %{mission_id: @current_mission.mission_id, ground_station_id: @ground_station_id}
        }
        v-ssr={false}
      />
    </Layouts.app>
    """
  end
end
