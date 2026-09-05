defmodule CadenceWeb.CommsProviderShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(%{"provider_id" => provider_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Ground Network Provider")
     |> assign(:nav_item, :comms_providers)
     |> assign(:provider_id, provider_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-provider-show-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="provider_show"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{provider_id: @provider_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
