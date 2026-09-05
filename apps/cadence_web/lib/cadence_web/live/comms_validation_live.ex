defmodule CadenceWeb.CommsValidationLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Comms Validation")
     |> assign(:nav_item, :comms_validation)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-validation-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="validation"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end
end
