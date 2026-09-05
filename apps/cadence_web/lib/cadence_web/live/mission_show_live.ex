defmodule CadenceWeb.MissionShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, socket.assigns.current_mission.display_name)
     |> assign(:nav_item, :mission_overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="mission-overview-page" class="space-y-6">
        <.vue
          id="mission-overview-component"
          v-component="FederatedFullPageSurface"
          application_key="mission_catalog"
          surface_id="mission_overview"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
          v-ssr={false}
          class="space-y-6"
        />
      </div>
    </Layouts.app>
    """
  end
end
