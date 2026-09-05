defmodule CadenceWeb.CommsRoutingNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Routing Rule")
     |> assign(:nav_item, :comms_routing)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-routing-new-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="routing_new"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{mission_id: @current_mission.mission_id}}
        v-ssr={false}
        class="space-y-6 max-w-2xl"
      />
    </Layouts.app>
    """
  end
end
