defmodule CadenceWeb.OpsDashboardPlaylistsLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.Management
  alias Phoenix.LiveView.JS

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
     |> assign(:playlist_page, playlist_page_dto())
     |> assign(:playlist_form, playlist_form_dto(0))
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
         |> assign(
           :playlist_form,
           playlist_form_dto(socket.assigns.playlist_form.reset_revision + 1)
         )
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
      <.vue
        id="dashboard-playlists-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_playlists"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp reload_playlists(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    playlists =
      scope.organization_id
      |> Management.list_playlists(mission.mission_id)
      |> Enum.map(&playlist_dto(mission.mission_id, &1))

    stream(socket, :dashboard_playlists, playlists, reset: true)
  end

  defp dashboard_options(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    scope.organization_id
    |> Cadence.Dashboards.list_dashboard_summaries(mission.mission_id)
    |> Enum.map(&%{label: &1.name, value: &1.dashboard_id})
  end

  defp playlist_page_dto do
    %{
      id: "dashboard-playlists-page",
      eyebrow: "Dashboards / Playlists",
      heading: "Operations display rotation",
      copy:
        "Playlists keep ordered dashboard references; the canonical documents and live health remain independent.",
      list: %{
        id: "dashboard-playlist-list",
        empty: %{id: "dashboard-playlist-empty", copy: "No playlists yet."}
      },
      form_eyebrow: "New playlist",
      present_action: %{label: "Present", icon: "hero-play"}
    }
  end

  defp playlist_form_dto(reset_revision) do
    %{
      id: "dashboard-playlist-form",
      reset_revision: reset_revision,
      name: %{
        id: "playlist_name",
        name: "playlist[name]",
        type: "text",
        label: "Name",
        value: "",
        required: true
      },
      description: %{
        id: "playlist_description",
        name: "playlist[description]",
        type: "textarea",
        label: "Description",
        value: "",
        required: false
      },
      dashboard_ids: %{
        id: "playlist_dashboard_ids",
        name: "playlist[dashboard_ids][]",
        type: "select",
        label: "Dashboards in order",
        value: [],
        required: false,
        multiple: true
      },
      dwell_seconds: %{
        id: "playlist_dwell_seconds",
        name: "playlist[dwell_seconds]",
        type: "number",
        label: "Dwell seconds",
        value: "30",
        required: false,
        min: 5,
        max: 900
      },
      wallboard_mode: %{
        id: "playlist_wallboard_mode",
        name: "playlist[wallboard_mode]",
        type: "checkbox",
        label: "Wallboard mode",
        value: false,
        required: false
      },
      submit: %{id: "dashboard-playlist-create", label: "Create playlist"}
    }
  end

  defp playlist_dto(mission_id, playlist) do
    %{
      dashboard_playlist_id: playlist.dashboard_playlist_id,
      name: playlist.name,
      description: playlist.description,
      dashboard_ids: playlist.dashboard_ids,
      dashboard_count: length(playlist.dashboard_ids),
      dwell_seconds: playlist.dwell_seconds,
      wallboard_mode: playlist.wallboard_mode,
      mode_label: if(playlist.wallboard_mode, do: "wallboard", else: "presentation"),
      present: %{
        id: "dashboard-playlist-present-#{playlist.dashboard_playlist_id}",
        href:
          ~p"/missions/#{mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"
      }
    }
  end

  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
