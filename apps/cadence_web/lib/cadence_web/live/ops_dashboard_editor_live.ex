defmodule CadenceWeb.OpsDashboardEditorLive do
  @moduledoc """
  Dashboard authoring route boundary.

  The router mounts this LiveView only after the dashboard-author policy check.
  """

  use CadenceWeb, :live_view

  alias CadenceWeb.OpsDashboardShowLive.Controller

  @impl true
  def mount(params, session, socket) do
    with {:ok, socket} <- Controller.mount(params, session, socket) do
      {:ok, assign(socket, :federated_query_params, %{})}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    with {:noreply, socket} <- Controller.handle_params(params, uri, socket) do
      {:noreply, assign(socket, :federated_query_params, Map.take(params, ["dashboard_id"]))}
    end
  end

  @impl true
  defdelegate handle_info(message, socket), to: Controller

  @impl true
  defdelegate handle_async(name, result, socket), to: Controller

  @impl true
  defdelegate handle_event(event, params, socket), to: Controller

  @impl true
  defdelegate terminate(reason, socket), to: Controller

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
