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
      <section id="dashboard-playlist-present-page" class="flex h-full min-h-0 flex-col bg-base-100" data-wallboard-mode={to_string(@dashboard_playlist.wallboard_mode)}>
        <header class="flex shrink-0 flex-wrap items-center gap-3 border-b border-warning/35 bg-warning/10 px-4 py-2">
          <div class="min-w-0 flex-1">
            <p class="hud-label">{if @dashboard_playlist.wallboard_mode, do: "Wallboard", else: "Presentation"} · {@dashboard_playlist.name}</p>
            <p class="truncate text-sm font-semibold">{@current_dashboard.name}</p>
          </div>
          <div id="dashboard-playlist-freshness-signal" data-freshness-visible="true" class="flex items-center gap-2 border border-warning/30 bg-base-100 px-3 py-1.5 text-xs">
            <.icon name="hero-signal" class="h-4 w-4 text-warning" />
            <span>Live freshness, stale, partial, disconnected, and unsupported states remain visible in the canvas and context rail.</span>
          </div>
          <span id="dashboard-playlist-position" class="font-mono text-xs">{@current_index + 1}/{length(@dashboard_playlist.dashboard_ids)}</span>
          <.button id="dashboard-playlist-next" size={:xs} variant={:ghost} phx-click="next_dashboard">Next</.button>
        </header>
        <iframe :if={@current_dashboard_available?} id="dashboard-playlist-frame" title={@current_dashboard.name} src={@current_dashboard_path} class="min-h-0 flex-1 w-full border-0" data-dashboard-id={@current_dashboard.dashboard_id}></iframe>
        <div :if={not @current_dashboard_available?} id="dashboard-playlist-unavailable" data-dashboard-state="unsupported" class="flex min-h-0 flex-1 items-center justify-center bg-error/5 p-8">
          <div class="max-w-xl border border-error/35 bg-base-100 p-6 text-center">
            <.icon name="hero-exclamation-triangle" class="mx-auto h-8 w-8 text-error" />
            <h2 class="mt-3 text-lg font-semibold">Referenced dashboard is unavailable</h2>
            <p class="mt-2 text-sm text-base-content/60">The playlist reference is preserved, but presentation cannot silently skip or mask a missing or archived dashboard.</p>
          </div>
        </div>
      </section>
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

    socket
    |> assign(:current_index, index)
    |> assign(:current_dashboard, summary)
    |> assign(:current_dashboard_available?, available?)
    |> assign(
      :current_dashboard_path,
      ~p"/missions/#{socket.assigns.current_mission.mission_id}/ops/dashboards/#{dashboard_id}?presentation=playlist"
    )
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
