defmodule Cadence.Dashboards.PlaylistStore do
  @moduledoc false
  import Ecto.Query
  alias Cadence.Dashboards.{DashboardPlaylist, Management}
  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Repo

  def create(org, mission, attrs, actor) do
    Repo.transaction(fn ->
      ids = attrs["dashboard_ids"]
      selected = active(org, mission) |> where([d], d.dashboard_id in ^ids)

      available =
        selected
        |> order_by([d], asc: d.dashboard_id)
        |> lock("FOR SHARE")
        |> select([d], d.dashboard_id)
        |> Repo.all()

      if Enum.any?(ids, &(&1 not in available)), do: Repo.rollback(:invalid_dashboard)

      case Management.create_playlist(org, mission, attrs, created_by: actor) do
        {:ok, playlist} -> playlist
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates a playlist observed at `expected_updated_at` (Q6): `{:ok, playlist}`, or
  `{:error, :not_found | {:invalid_dashboard, ids} | {:stale, current} | changeset}`.
  """
  def update(org, mission, id, attrs, actor, expected_updated_at) do
    Repo.transaction(fn ->
      playlist =
        scoped(DashboardPlaylist, org, mission)
        |> where([p], p.dashboard_playlist_id == ^id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        is_nil(playlist) -> Repo.rollback(:not_found)
        playlist.updated_at != expected_updated_at -> Repo.rollback({:stale, playlist})
        true -> :ok
      end

      if ids = attrs["dashboard_ids"], do: available!(org, mission, ids)

      changes =
        attrs
        |> Map.take(~w(name description dashboard_ids dwell_seconds wallboard_mode))
        |> Map.put("updated_by", actor)

      case playlist |> DashboardPlaylist.changeset(changes) |> Repo.update() do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Deletes a playlist (hard: nothing references one). `{:ok, playlist}` or `{:error, :not_found}`."
  def delete(org, mission, id) do
    Repo.transaction(fn ->
      scoped(DashboardPlaylist, org, mission)
      |> where([p], p.dashboard_playlist_id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> case do
        nil -> Repo.rollback(:not_found)
        playlist -> Repo.delete!(playlist)
      end
    end)
  end

  defp available!(org, mission, ids) do
    available =
      active(org, mission)
      |> where([d], d.dashboard_id in ^ids)
      |> order_by([d], asc: d.dashboard_id)
      |> lock("FOR SHARE")
      |> select([d], d.dashboard_id)
      |> Repo.all()

    case Enum.reject(ids, &(&1 in available)) do
      [] -> :ok
      missing -> Repo.rollback({:invalid_dashboard, missing})
    end
  end

  @doc "Playlists that show this dashboard, by name (archive's 'used by', director Q10)."
  def using_dashboard(org, mission, dashboard_id) do
    scoped(DashboardPlaylist, org, mission)
    |> where([p], ^dashboard_id in p.dashboard_ids)
    |> order_by([p], asc: p.name, asc: p.dashboard_playlist_id)
    |> select([p], %{id: p.dashboard_playlist_id, name: p.name})
    |> Repo.all()
  end

  defp active(org, mission),
    do: scoped(DashboardRow, org, mission) |> where([d], d.lifecycle_state == "active")

  defp scoped(schema, org, mission),
    do: where(schema, [r], r.organization_id == ^org and r.mission_id == ^mission)
end
