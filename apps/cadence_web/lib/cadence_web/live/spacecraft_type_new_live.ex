defmodule CadenceWeb.SpacecraftTypeNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Spacecraft Profile")
     |> assign(:nav_item, :spacecraft)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-profile-new-component"
        v-component="FederatedFullPageSurface"
        application_key="spacecraft"
        surface_id="profile_new"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="space-y-6 max-w-2xl"
      />
    </Layouts.app>
    """
  end
end
