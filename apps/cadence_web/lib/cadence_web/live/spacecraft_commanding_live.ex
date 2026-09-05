defmodule CadenceWeb.SpacecraftCommandingLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft

    {:ok,
     socket
     |> assign(:page_title, "#{spacecraft.display_name} Command Interpretation")
     |> assign(:nav_item, :spacecraft)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-commanding-component"
        v-component="FederatedFullPageSurface"
        application_key="spacecraft"
        surface_id="commanding"
        host_scope="spacecraft"
        mission_id={@current_mission.mission_id}
        spacecraft_id={@current_spacecraft.spacecraft_id}
        query_params={%{}}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end
end
