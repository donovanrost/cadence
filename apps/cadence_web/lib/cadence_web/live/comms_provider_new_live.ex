defmodule CadenceWeb.CommsProviderNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Ground Network Provider")
     |> assign(:nav_item, :comms_providers)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-provider-new-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="provider_new"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{mission_id: @current_mission.mission_id}}
        v-ssr={false}
        class="max-w-3xl space-y-6"
      />
    </Layouts.app>
    """
  end
end
