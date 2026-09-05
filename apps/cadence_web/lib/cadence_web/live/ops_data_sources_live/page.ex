defmodule CadenceWeb.OpsDataSourcesLive.Page do
  @moduledoc false

  use CadenceWeb, :html

  def render(assigns) do
    {surface_id, query_params} =
      case assigns.live_action do
        action when action in [:new, :settings] ->
          {if(action == :new, do: "data_source_registration", else: "data_source_settings"),
           Map.get(assigns, :federated_query_params, %{})}

        _reader ->
          {"data_sources", Map.get(assigns, :federated_query_params, %{})}
      end

    assigns = assign(assigns, surface_id: surface_id, query_params: query_params)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-data-sources-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id={@surface_id}
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={@query_params}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
