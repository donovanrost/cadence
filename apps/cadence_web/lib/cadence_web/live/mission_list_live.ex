defmodule CadenceWeb.MissionListLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:nav_item, :missions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="mission-list-component"
        v-component="FederatedFullPageSurface"
        application_key="mission_catalog"
        surface_id="mission_list"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        query_params={%{organization_id: @current_scope.organization.organization_id}}
        v-ssr={false}
      />
    </Layouts.app>
    """
  end
end
