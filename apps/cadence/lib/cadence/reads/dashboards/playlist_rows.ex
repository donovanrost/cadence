defmodule Cadence.Reads.Dashboards.PlaylistRows do
  @moduledoc """
  Console playlist reads (D23, dashboards' docs/apogee/plans/dashboards-slice6.md): the list with
  who changed each one last, and one playlist with its dashboards in order (archived ones kept and
  flagged; present mode skips them). Mission operators read; `can_edit` is the author check.
  """

  import Ecto.Query

  alias Cadence.Auth.Policy
  alias Cadence.Dashboards.{Authoring, DashboardPlaylist, Documents}
  alias Cadence.Reads.Dashboards.Authors
  alias Cadence.Repo

  @limit 200

  @spec list(map(), binary(), binary() | nil) :: {:ok, map()} | {:error, :forbidden}
  def list(scope, mission, q) do
    with :ok <- authorize(scope, mission) do
      rows =
        DashboardPlaylist
        |> where([p], p.organization_id == ^scope.organization_id and p.mission_id == ^mission)
        |> search(q)
        |> order_by([p], asc: p.name, asc: p.dashboard_playlist_id)
        |> limit(@limit)
        |> Repo.all()

      names = Authors.names(scope.organization_id, Enum.map(rows, & &1.updated_by))

      {:ok,
       %{playlists: Enum.map(rows, &summary(&1, names)), can_edit: can_edit?(scope, mission)}}
    end
  end

  @spec get(map(), binary(), binary()) ::
          {:ok, map()} | {:error, :forbidden | :playlist_not_found}
  def get(scope, mission, id) do
    with :ok <- authorize(scope, mission),
         %DashboardPlaylist{} = playlist <- fetch(scope.organization_id, mission, id) do
      {:ok, %{playlist: detail(playlist), can_edit: can_edit?(scope, mission)}}
    else
      nil -> {:error, :playlist_not_found}
      error -> error
    end
  end

  @doc "One playlist in the detail shape (a write's answer, a stale edit's `current`)."
  @spec detail(DashboardPlaylist.t()) :: map()
  def detail(%DashboardPlaylist{} = playlist) do
    dashboards = dashboards(playlist)
    names = Authors.names(playlist.organization_id, [playlist.updated_by])

    playlist
    |> summary(names)
    |> Map.delete(:dashboard_count)
    |> Map.put(
      :dashboards,
      Enum.map(
        playlist.dashboard_ids,
        &Map.get(dashboards, &1, %{id: &1, name: nil, archived: true})
      )
    )
  end

  defp summary(playlist, names),
    do: %{
      id: playlist.dashboard_playlist_id,
      name: playlist.name,
      description: playlist.description || "",
      dwell_seconds: playlist.dwell_seconds,
      wallboard_mode: playlist.wallboard_mode,
      dashboard_count: length(playlist.dashboard_ids),
      updated_at: playlist.updated_at,
      updated_by: person(playlist.updated_by || playlist.created_by, names)
    }

  # Names of the playlist's dashboards, active or archived.
  defp dashboards(playlist) do
    org = playlist.organization_id
    mission = playlist.mission_id

    archived =
      for summary <- Documents.list_archived_summaries(org, mission),
          into: %{},
          do:
            {summary.dashboard_id,
             %{id: summary.dashboard_id, name: summary.name, archived: true}}

    for summary <- Documents.list_summaries(org, mission),
        into: archived,
        do:
          {summary.dashboard_id, %{id: summary.dashboard_id, name: summary.name, archived: false}}
  end

  defp fetch(org, mission, id),
    do:
      Repo.get_by(DashboardPlaylist,
        dashboard_playlist_id: id,
        organization_id: org,
        mission_id: mission
      )

  defp search(query, q) when is_binary(q) and q != "",
    do: where(query, [p], fragment("strpos(lower(?), lower(?)) > 0", p.name, ^String.trim(q)))

  defp search(query, _q), do: query

  defp person(id, names) when is_binary(id), do: %{id: id, name: Map.get(names, id)}
  defp person(_none, _names), do: nil

  defp authorize(scope, mission) do
    case Policy.authorize(scope, :operate_mission, %{
           organization_id: scope.organization_id,
           mission_id: mission
         }) do
      :ok -> :ok
      _denied -> {:error, :forbidden}
    end
  end

  defp can_edit?(scope, mission), do: Authoring.authorize(scope, mission) == :ok
end
