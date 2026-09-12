defmodule Cadence.Dashboards.PlaylistStore do
  @moduledoc false
  import Ecto.Query
  alias Cadence.Dashboards.{DashboardPlaylist, Management}
  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Repo

  def list(org, mission, query) do
    scoped(DashboardPlaylist, org, mission)
    |> search(query.q)
    |> after_id(:dashboard_playlist_id, query.after)
    |> order_by([p], asc: p.dashboard_playlist_id)
    |> select([p], %{
      id: p.dashboard_playlist_id,
      name: p.name,
      description: p.description,
      count: fragment("cardinality(?)", p.dashboard_ids),
      dwell_seconds: p.dwell_seconds,
      wallboard_mode: p.wallboard_mode
    })
    |> page()
  end

  def choices(org, mission, query) do
    active(org, mission)
    |> search(query.q)
    |> after_id(:dashboard_id, query.after)
    |> order_by([d], asc: d.dashboard_id)
    |> select([d], %{id: d.dashboard_id, name: d.name, published_version: d.published_version})
    |> page()
  end

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

  def dashboard(org, mission, id) do
    active(org, mission)
    |> where([d], d.dashboard_id == ^id)
    |> select([d], %{id: d.dashboard_id, name: d.name})
    |> Repo.one()
  end

  defp active(org, mission),
    do: scoped(DashboardRow, org, mission) |> where([d], d.lifecycle_state == "active")

  defp scoped(schema, org, mission),
    do: where(schema, [r], r.organization_id == ^org and r.mission_id == ^mission)

  defp search(query, ""), do: query

  defp search(query, text),
    do: where(query, [r], fragment("strpos(lower(?), lower(?)) > 0", r.name, ^text))

  defp after_id(query, _, nil), do: query
  defp after_id(query, key, cursor), do: where(query, [r], field(r, ^key) > ^cursor)

  defp page(query) do
    rows = query |> limit(26) |> Repo.all()
    visible = Enum.take(rows, 25)
    %{rows: visible, next: if(length(rows) > 25, do: List.last(visible).id, else: nil)}
  end
end
