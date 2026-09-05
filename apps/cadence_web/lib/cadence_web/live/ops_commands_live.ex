defmodule CadenceWeb.OpsCommandsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @filter_keys ~w(status target query focus_command_id)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Commands")
     |> assign(:ops_nav_item, :commands)
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
        id="ops-commands-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="commands"
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
