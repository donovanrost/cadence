defmodule Cadence.Dashboards.DocumentStore.History do
  @moduledoc false
  import Ecto.Query
  alias Cadence.Dashboards.DocumentStore.{DashboardRow, LifecycleEventRow, VersionRow}
  alias Cadence.Repo
  @page_size 25
  @version_fields [
    :version,
    :snapshot_kind,
    :parent_version,
    :based_on_version,
    :schema_version,
    :change_summary,
    :created_by,
    :inserted_at
  ]
  @event_fields [
    :dashboard_lifecycle_event_id,
    :event_type,
    :dashboard_version,
    :actor_id,
    :occurred_at
  ]

  def load(org, mission, dashboard, query) do
    Repo.transaction(fn ->
      # A brief shared row lock keeps publication/draft pointers consistent with
      # the selected immutable document. Lists never hydrate document or event payloads.
      row =
        scoped(DashboardRow, org, mission, dashboard)
        |> select(
          [r],
          map(r, [:name, :latest_version, :lock_version, :published_version, :lifecycle_state])
        )
        |> lock("FOR SHARE")
        |> Repo.one()

      if is_nil(row) or is_nil(row.latest_version), do: Repo.rollback(:unavailable)
      versions = scoped(VersionRow, org, mission, dashboard)
      selected_number = query.version || row.latest_version
      selected = versions |> where([r], r.version == ^selected_number) |> Repo.one()
      if is_nil(selected) or selected_number > row.latest_version, do: Repo.rollback(:unavailable)

      version_page =
        versions
        |> before_version(query.before_version)
        |> order_by([r], desc: r.version)
        |> limit(@page_size + 1)
        |> select([r], map(r, @version_fields))
        |> Repo.all()

      events = scoped(LifecycleEventRow, org, mission, dashboard)

      event_page =
        events
        |> before_event(events, query.before_event)
        |> order_by([r], desc: r.occurred_at, desc: r.dashboard_lifecycle_event_id)
        |> limit(@page_size + 1)
        |> select([r], map(r, @event_fields))
        |> Repo.all()

      %{
        dashboard: row,
        selected: VersionRow.to_domain(selected),
        versions: Enum.take(version_page, @page_size),
        next_version:
          if(length(version_page) > @page_size, do: Enum.at(version_page, @page_size - 1).version),
        events: Enum.take(event_page, @page_size),
        next_event:
          if(length(event_page) > @page_size,
            do: Enum.at(event_page, @page_size - 1).dashboard_lifecycle_event_id
          )
      }
    end)
  end

  defp scoped(schema, org, mission, dashboard),
    do:
      where(
        schema,
        [r],
        r.organization_id == ^org and r.mission_id == ^mission and r.dashboard_id == ^dashboard
      )

  defp before_version(query, nil), do: query
  defp before_version(query, version), do: where(query, [r], r.version < ^version)
  defp before_event(query, _events, nil), do: query

  defp before_event(query, events, id) do
    cursor =
      events
      |> where([r], r.dashboard_lifecycle_event_id == ^id)
      |> select([r], map(r, [:occurred_at, :dashboard_lifecycle_event_id]))
      |> Repo.one()

    if is_nil(cursor), do: Repo.rollback(:unavailable)

    where(
      query,
      [r],
      r.occurred_at < ^cursor.occurred_at or
        (r.occurred_at == ^cursor.occurred_at and r.dashboard_lifecycle_event_id < ^id)
    )
  end
end
