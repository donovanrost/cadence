defmodule CadenceWeb.OpsDashboardPlaylistPresentLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{DashboardSummary, Management}

  @impl true
  def mount(%{"playlist_id" => playlist_id} = params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case Management.fetch_playlist(scope.organization_id, mission.mission_id, playlist_id) do
      {:ok, playlist} ->
        if connected?(socket),
          do: Process.send_after(self(), :rotate_playlist, playlist.dwell_seconds * 1_000)

        {:ok,
         socket
         |> assign(:page_title, playlist.name)
         |> assign(:ops_nav_item, :dashboards)
         |> assign(:active_dashboard_id, nil)
         |> assign(:dashboard_playlist, playlist)
         |> assign_current(params["index"])}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Dashboard playlist is unavailable: #{inspect(reason)}")
         |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_current(socket, params["index"])}
  end

  @impl true
  def handle_info(:rotate_playlist, socket) do
    Process.send_after(
      self(),
      :rotate_playlist,
      socket.assigns.dashboard_playlist.dwell_seconds * 1_000
    )

    {:noreply, rotate(socket)}
  end

  @impl true
  def handle_event("next_dashboard", _params, socket), do: {:noreply, rotate(socket)}

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

  defp rotate(socket) do
    count = length(socket.assigns.dashboard_playlist.dashboard_ids)
    next_index = rem(socket.assigns.current_index + 1, count)

    push_patch(socket,
      to:
        ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/dashboards/playlists/#{socket.assigns.dashboard_playlist.dashboard_playlist_id}/present?index=#{next_index}"
    )
  end

  defp assign_current(socket, index_param) do
    playlist = socket.assigns.dashboard_playlist
    summaries = dashboard_summaries(socket)
    count = length(playlist.dashboard_ids)
    index = normalize_index(index_param, count)
    dashboard_id = Enum.at(playlist.dashboard_ids, index)

    summary =
      Map.get(summaries, dashboard_id, %DashboardSummary{
        dashboard_id: dashboard_id,
        name: "Unavailable dashboard",
        lifecycle_state: "unsupported"
      })

    available? = Map.has_key?(summaries, dashboard_id)

    current_dashboard_path =
      ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/dashboards/#{dashboard_id}?presentation=playlist"

    socket
    |> assign(:current_index, index)
    |> assign(:current_dashboard, summary)
    |> assign(:current_dashboard_available?, available?)
    |> assign(:current_dashboard_path, current_dashboard_path)
    |> assign(:playlist_present_page, playlist_present_page_dto(playlist, index))
    |> assign(
      :current_dashboard_details,
      current_dashboard_dto(summary, available?, current_dashboard_path)
    )
  end

  defp playlist_present_page_dto(playlist, index) do
    %{
      id: "dashboard-playlist-present-page",
      wallboard_mode: playlist.wallboard_mode,
      mode_label: if(playlist.wallboard_mode, do: "Wallboard", else: "Presentation"),
      playlist_name: playlist.name,
      freshness_signal: %{
        id: "dashboard-playlist-freshness-signal",
        visible: true,
        icon: "hero-signal",
        copy:
          "Live freshness, stale, partial, disconnected, and unsupported states remain visible in the canvas and context rail."
      },
      position: %{
        id: "dashboard-playlist-position",
        current: index + 1,
        total: length(playlist.dashboard_ids)
      },
      next_action: %{
        id: "dashboard-playlist-next",
        label: "Next"
      },
      unavailable: %{
        id: "dashboard-playlist-unavailable",
        state: "unsupported",
        icon: "hero-exclamation-triangle",
        title: "Referenced dashboard is unavailable",
        copy:
          "The playlist reference is preserved, but presentation cannot silently skip or mask a missing or archived dashboard."
      }
    }
  end

  defp current_dashboard_dto(summary, available?, path) do
    %{
      dashboard_id: summary.dashboard_id,
      name: summary.name,
      available: available?,
      path: path,
      frame_id: "dashboard-playlist-frame"
    }
  end

  defp dashboard_summaries(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_playlist: playlist} =
      socket.assigns

    scope.organization_id
    |> Cadence.Dashboards.list_dashboard_summaries(mission.mission_id)
    |> Enum.filter(&(&1.dashboard_id in playlist.dashboard_ids))
    |> Map.new(&{&1.dashboard_id, &1})
  end

  defp normalize_index(value, count) do
    case Integer.parse(value || "0") do
      {index, ""} when index >= 0 -> rem(index, count)
      _invalid -> 0
    end
  end
end
