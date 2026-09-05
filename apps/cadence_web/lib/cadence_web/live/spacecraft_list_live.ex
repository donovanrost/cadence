defmodule CadenceWeb.SpacecraftListLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @query_keys ~w(q sort dir page pageSize filter)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:federated_query_params, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :federated_query_params, Map.take(params, @query_keys))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-list-component"
        v-component="FederatedFullPageSurface"
        application_key="spacecraft"
        surface_id="list"
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
