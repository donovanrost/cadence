defmodule CadenceWeb.OpsAlarmsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @filter_keys ~w(severity state spacecraft_id query)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Alarms")
     |> assign(:ops_nav_item, :alarms)
     |> assign(:federated_query_params, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :federated_query_params, Map.take(params, @filter_keys))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-alarms-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="alarms"
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
