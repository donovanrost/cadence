defmodule CadenceWeb.OpsContactRequirementShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"contact_requirement_id" => requirement_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Contact Requirement")
     |> assign(:ops_nav_item, :requirements)
     |> assign(:contact_requirement_id, requirement_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-requirement-show-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_requirement_show"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"contact_requirement_id" => @contact_requirement_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
