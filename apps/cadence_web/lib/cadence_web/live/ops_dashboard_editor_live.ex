defmodule CadenceWeb.OpsDashboardEditorLive do
  @moduledoc """
  Dashboard authoring route boundary.

  The router mounts this LiveView only after the dashboard-author policy check.
  """

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"dashboard_id" => dashboard_id}, _session, socket),
    do: {:ok, assign(socket, :dashboard_id, dashboard_id)}

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, :federated_query_params, Map.take(params, ["dashboard_id"]))}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-editor-surface"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_editor"
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
