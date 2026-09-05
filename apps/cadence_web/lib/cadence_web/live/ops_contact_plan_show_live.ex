defmodule CadenceWeb.OpsContactPlanShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"contact_plan_id" => plan_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Contact Plan")
     |> assign(:ops_nav_item, :requirements)
     |> assign(:contact_plan_id, plan_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-plan-show-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_plan_show"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"contact_plan_id" => @contact_plan_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
