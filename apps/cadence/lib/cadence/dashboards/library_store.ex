defmodule Cadence.Dashboards.LibraryStore do
  @moduledoc false
  import Ecto.Query
  alias Cadence.Dashboards.{DashboardLibraryItem, DashboardLibraryVersion}
  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Repo
  @page_size 25

  def load(org, mission, query) do
    Repo.transaction(fn ->
      items = scoped(DashboardLibraryItem, org, mission)
      selected = selected(items, query)

      {item_page, next_item} =
        items
        |> search(query.q)
        |> after_item(query.after)
        |> order_by([r], asc: r.dashboard_library_item_id)
        |> page(& &1.dashboard_library_item_id)

      dashboards = scoped(DashboardRow, org, mission) |> where([r], r.lifecycle_state == "active")

      {dashboard_page, next_dashboard} =
        dashboards
        |> search(query.dashboard_query)
        |> after_dashboard(query.dashboard_after)
        |> order_by([r], asc: r.dashboard_id)
        |> select([r], map(r, [:dashboard_id, :name, :latest_version]))
        |> page(& &1.dashboard_id)

      %{
        items: item_page,
        next_item: next_item,
        selected: selected,
        dashboards: dashboard_page,
        next_dashboard: next_dashboard,
        consumers: consumers(dashboards, selected, query.consumer_after)
      }
    end)
  end

  defp selected(_items, %{item_id: nil}), do: nil

  defp selected(items, query) do
    item =
      items
      |> where([r], r.dashboard_library_item_id == ^query.item_id)
      |> lock("FOR SHARE")
      |> Repo.one()

    if is_nil(item), do: Repo.rollback(:unavailable)

    versions =
      where(
        DashboardLibraryVersion,
        [r],
        r.dashboard_library_item_id == ^item.dashboard_library_item_id
      )

    number = query.version || item.latest_version
    version = versions |> where([r], r.version == ^number) |> Repo.one()
    if is_nil(version) or number > item.latest_version, do: Repo.rollback(:unavailable)

    {history, next_version} =
      versions
      |> before_version(query.before_version)
      |> order_by([r], desc: r.version)
      |> select([r], map(r, [:version, :change_summary, :created_by, :inserted_at]))
      |> page(& &1.version)

    %{item: item, version: version, versions: history, next_version: next_version}
  end

  defp consumers(_dashboards, nil, _cursor), do: nil

  defp consumers(dashboards, selected, cursor) do
    item = selected.item.dashboard_library_item_id

    match = %{
      "placements" => [%{"content" => %{"kind" => "library", "library_widget_id" => item}}]
    }

    consumers = where(dashboards, [r], fragment("? @> ?", r.document, ^match))
    total = Repo.aggregate(consumers, :count)

    {rows, next} =
      consumers
      |> after_dashboard(cursor)
      |> order_by([r], asc: r.dashboard_id)
      |> select([r], %{
        dashboard_id: r.dashboard_id,
        name: r.name,
        latest_version: r.latest_version,
        pins:
          fragment(
            "(SELECT coalesce(jsonb_agg(p), '[]'::jsonb) FROM jsonb_array_elements(?->'placements') AS p WHERE p->'content'->>'kind' = 'library' AND p->'content'->>'library_widget_id' = ?)",
            r.document,
            ^item
          )
      })
      |> page(& &1.dashboard_id)

    %{total: total, rows: rows, next: next}
  end

  defp scoped(schema, org, mission),
    do: where(schema, [r], r.organization_id == ^org and r.mission_id == ^mission)

  defp search(query, ""), do: query

  defp search(query, text),
    do: where(query, [r], fragment("strpos(lower(?), lower(?)) > 0", r.name, ^text))

  defp after_item(query, nil), do: query
  defp after_item(query, id), do: where(query, [r], r.dashboard_library_item_id > ^id)
  defp after_dashboard(query, nil), do: query
  defp after_dashboard(query, id), do: where(query, [r], r.dashboard_id > ^id)
  defp before_version(query, nil), do: query
  defp before_version(query, version), do: where(query, [r], r.version < ^version)

  defp page(query, key) do
    rows = query |> limit(@page_size + 1) |> Repo.all()

    {Enum.take(rows, @page_size),
     if(length(rows) > @page_size, do: rows |> Enum.at(@page_size - 1) |> key.())}
  end
end
