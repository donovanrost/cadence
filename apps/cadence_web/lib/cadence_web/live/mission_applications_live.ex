defmodule CadenceWeb.MissionApplicationsLive do
  @moduledoc "Mission-scoped inventory for registered product applications."

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "#{socket.assigns.current_mission.display_name} Applications")
     |> assign(:nav_item, :mission_applications)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="mission-applications-page-component"
        v-component="FederatedFullPageSurface"
        application_key="mission_catalog"
        surface_id="mission_applications"
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
