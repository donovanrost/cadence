defmodule CadenceWeb.OpsDataOperationsLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Data Operations")
     |> assign(:ops_nav_item, :data_operations)
     |> assign(:data_operations_admin?, socket.assigns.live_action == :manage)
     |> assign(:selected_group_id, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :selected_group_id, params["group"])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-data-operations-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id={if(@data_operations_admin?, do: "data_operations_manage", else: "data_operations")}
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={if(@selected_group_id, do: %{"group" => @selected_group_id}, else: %{})}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
