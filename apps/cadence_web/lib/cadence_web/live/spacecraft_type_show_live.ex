defmodule CadenceWeb.SpacecraftTypeShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @query_keys ["profile_id"]

  @impl true
  def mount(%{"profile_id" => profile_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Spacecraft Profile")
     |> assign(:nav_item, :spacecraft)
     |> assign(:profile_id, profile_id)
     |> assign(:federated_query_params, %{"profile_id" => profile_id})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :federated_query_params, Map.take(params, @query_keys))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="spacecraft-profile-show-page">
        <.vue
          id="spacecraft-profile-show-component"
          v-component="FederatedFullPageSurface"
          application_key="spacecraft"
          surface_id="profile_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={@federated_query_params}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end
end
