defmodule CadenceWeb.CommsTransportShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"transport_id" => transport_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Transport")
     |> assign(:nav_item, :comms_transports)
     |> assign(:transport_id, transport_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-transport-show-page">
        <.vue
          id="comms-transport-show-component"
          v-component="FederatedFullPageSurface"
          application_key="comms"
          surface_id="transport"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id, transport_id: @transport_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
