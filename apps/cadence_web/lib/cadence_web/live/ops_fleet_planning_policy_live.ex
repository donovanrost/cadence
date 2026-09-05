defmodule CadenceWeb.OpsFleetPlanningPolicyLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    organization_admin? =
      MapSet.member?(socket.assigns.current_scope.capabilities, :organization_admin) or
        MapSet.member?(socket.assigns.current_scope.capabilities, :platform_admin)

    {:ok,
     socket
     |> assign(:page_title, "Fleet Planning Policy")
     |> assign(:ops_nav_item, :planning)
     |> assign(:organization_admin?, organization_admin?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="ops-fleet-planning-policy-page" class="h-full overflow-y-auto bg-base-100">
        <div id={if(@organization_admin?, do: nil, else: "fleet-policy-admin-required")} class="contents">
          <.vue
            id="ops-fleet-planning-policy-component"
            v-component="FederatedFullPageSurface"
            application_key="ops_console"
            surface_id="fleet_planning_policy"
            host_scope="mission"
            mission_id={@current_mission.mission_id}
            query_params={%{}}
            v-ssr={false}
            class="contents"
          />
        </div>
      </section>
    </Layouts.app>
    """
  end
end
