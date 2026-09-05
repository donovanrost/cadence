defmodule CadenceWeb.OpsTelemetryExploreComponents do
  @moduledoc false

  use CadenceWeb, :html

  def page(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-telemetry-explore-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="telemetry_explore"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={@federated_query_params}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
