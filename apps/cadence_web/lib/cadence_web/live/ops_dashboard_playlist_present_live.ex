defmodule CadenceWeb.OpsDashboardPlaylistPresentLive do
  @moduledoc false

  use CadenceWeb, :live_view

  @impl true
  def mount(%{"playlist_id" => playlist_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard Playlist")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:dashboard_playlist, %{dashboard_playlist_id: playlist_id})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="dashboard-playlist-present-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_playlist_present"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{"playlist_id" => @dashboard_playlist.dashboard_playlist_id}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end
end
