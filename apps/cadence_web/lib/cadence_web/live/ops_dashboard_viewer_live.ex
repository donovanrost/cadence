defmodule CadenceWeb.OpsDashboardViewerLive do
  @moduledoc "Read-oriented dashboard route boundary."

  use CadenceWeb, :live_view

  @query_keys ~w(
    dashboard_id panel activity_filter activity_event selected_publish_issue selected_time
    time_mode time_axis from to limit_mode replay_run_id selection_view selected_widget
    selected_target selected_id selected_placement selected_data_view selected_scope_kind
    selected_scope_id selected_resource_id selected_spacecraft_id selected_contact_id
    selected_transport_id selected_source_endpoint_id selected_ground_station_id
    selected_scope_link_id realm data_source_id source_binding_id
  )

  @impl true
  def mount(%{"dashboard_id" => dashboard_id}, _session, socket),
    do: {:ok, assign(socket, :dashboard_id, dashboard_id)}

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, :federated_query_params, Map.take(params, @query_keys))}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-show-surface"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_show"
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
