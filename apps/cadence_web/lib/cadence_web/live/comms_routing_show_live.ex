defmodule CadenceWeb.CommsRoutingShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"routing_rule_id" => routing_rule_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Routing Rule")
     |> assign(:nav_item, :comms_routing)
     |> assign(:routing_rule_id, routing_rule_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="comms-routing-show-page">
        <.vue
          id="comms-routing-show-component"
          v-component="FederatedFullPageSurface"
          application_key="comms"
          surface_id="routing_detail"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{routing_rule_id: @routing_rule_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
