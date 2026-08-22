defmodule CadenceWeb.OpsDashboardPlaylistsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Management

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:dashboard_playlists,
       dom_id: &"dashboard-playlist-#{&1.dashboard_playlist_id}"
     )
     |> assign(:page_title, "Dashboard Playlists")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:active_dashboard_id, nil)
     |> assign(:playlist_form, playlist_form())
     |> assign(:dashboard_options, dashboard_options(socket))
     |> stream(:dashboard_playlists, [])
     |> reload_playlists()}
  end

  @impl true
  def handle_event("create_playlist", %{"playlist" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    attrs =
      params
      |> Map.put("dashboard_ids", List.wrap(params["dashboard_ids"]))
      |> Map.put("wallboard_mode", truthy?(params["wallboard_mode"]))

    case Management.create_playlist(
           scope.organization_id,
           mission.mission_id,
           attrs,
           created_by: current_user_id(scope)
         ) do
      {:ok, _playlist} ->
        {:noreply,
         socket
         |> assign(:playlist_form, playlist_form())
         |> reload_playlists()
         |> put_flash(:info, "Playlist created with dashboard references.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create playlist: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dashboard-playlists-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-6 py-5 hud-grid">
          <div class="mx-auto max-w-6xl">
            <p class="hud-label">Dashboards / Playlists</p>
            <h1 class="mt-1 text-2xl font-semibold">Operations display rotation</h1>
            <p class="mt-2 text-sm text-base-content/60">
              Playlists keep ordered dashboard references; the canonical documents and live health remain independent.
            </p>
          </div>
        </header>
        <div class="mx-auto grid max-w-6xl gap-5 p-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <div id="dashboard-playlist-list" phx-update="stream" class="space-y-3">
            <div id="dashboard-playlist-empty" class="hidden only:block border border-dashed border-base-300 p-8 text-center text-sm text-base-content/50">No playlists yet.</div>
            <article :for={{id, playlist} <- @streams.dashboard_playlists} id={id} class="border border-base-300 bg-base-200/20 p-4">
              <div class="flex items-start justify-between gap-4">
                <div><h2 class="font-semibold">{playlist.name}</h2><p class="mt-1 text-xs text-base-content/55">{playlist.description}</p></div>
                <span class="badge badge-outline">{length(playlist.dashboard_ids)} dashboards</span>
              </div>
              <p class="mt-3 font-mono text-xs text-base-content/50">{playlist.dwell_seconds}s dwell · {if playlist.wallboard_mode, do: "wallboard", else: "presentation"}</p>
              <.link id={"dashboard-playlist-present-#{playlist.dashboard_playlist_id}"} navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"} class="btn btn-outline btn-sm mt-3">
                <.icon name="hero-play" class="h-4 w-4" /> Present
              </.link>
            </article>
          </div>
          <aside>
            <.form for={@playlist_form} id="dashboard-playlist-form" phx-submit="create_playlist" class="space-y-3 border border-primary/30 bg-primary/5 p-4">
              <p class="hud-label">New playlist</p>
              <.input field={@playlist_form[:name]} type="text" label="Name" required />
              <.input field={@playlist_form[:description]} type="textarea" label="Description" />
              <.input field={@playlist_form[:dashboard_ids]} name={@playlist_form[:dashboard_ids].name <> "[]"} type="select" multiple label="Dashboards in order" options={@dashboard_options} />
              <.input field={@playlist_form[:dwell_seconds]} type="number" min="5" max="900" label="Dwell seconds" />
              <.input field={@playlist_form[:wallboard_mode]} type="checkbox" label="Wallboard mode" />
              <.button id="dashboard-playlist-create" type="submit">Create playlist</.button>
            </.form>
          </aside>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp reload_playlists(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    stream(
      socket,
      :dashboard_playlists,
      Management.list_playlists(scope.organization_id, mission.mission_id),
      reset: true
    )
  end

  defp dashboard_options(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    scope.organization_id
    |> Cadence.Dashboards.list_dashboard_summaries(mission.mission_id)
    |> Enum.map(&{&1.name, &1.dashboard_id})
  end

  defp playlist_form do
    to_form(
      %{
        "name" => "",
        "description" => "",
        "dashboard_ids" => [],
        "dwell_seconds" => "30",
        "wallboard_mode" => "false"
      },
      as: :playlist
    )
  end

  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
