defmodule CadenceWeb.CommsRoutingListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Comms Routing")
     |> assign(:nav_item, :comms_routing)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-routing-list-page-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="routing"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{mission_id: @current_mission.mission_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
