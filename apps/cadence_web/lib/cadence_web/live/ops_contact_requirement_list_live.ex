defmodule CadenceWeb.OpsContactRequirementListLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Contact Requirements")
     |> assign(:ops_nav_item, :requirements)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-requirements-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_requirement_list"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
