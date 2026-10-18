defmodule Cadence.Management.DataSources.Inventory do
  @moduledoc "Bounded, scoped pages of source configuration and immutable lifecycle evidence."
  import Ecto.Query

  alias Cadence.Management.DataSources.Store.{
    DataBindingEventRow,
    DataBindingRow,
    DataSourceEventRow,
    DataSourceRow
  }

  alias Cadence.Repo

  @page_size 25

  def sources(organization_id, mission_id, page, source_id \\ nil) do
    DataSourceRow
    |> scoped(organization_id, mission_id)
    |> subject(:data_source_id, source_id)
    |> order_by([row], asc: row.data_source_id)
    |> page(page, &DataSourceRow.to_domain/1)
  end

  def bindings(organization_id, mission_id, page, source_id \\ nil) do
    DataBindingRow
    |> scoped(organization_id, mission_id)
    |> subject(:data_source_id, source_id)
    |> order_by([row],
      asc: row.logical_source,
      asc: row.realm,
      asc: row.priority,
      asc: row.binding_id
    )
    |> page(page, &DataBindingRow.to_domain/1)
  end

  def source_events(organization_id, mission_id, page, source_id) do
    DataSourceEventRow
    |> scoped(organization_id, mission_id)
    |> subject(:data_source_id, source_id)
    |> order_by([row], desc: row.occurred_at, desc: row.data_source_event_id)
    |> page(page, &DataSourceEventRow.to_domain/1)
  end

  def binding_events(organization_id, mission_id, page, binding_id) do
    DataBindingEventRow
    |> scoped(organization_id, mission_id)
    |> subject(:binding_id, binding_id)
    |> order_by([row], desc: row.occurred_at, desc: row.data_binding_event_id)
    |> page(page, &DataBindingEventRow.to_domain/1)
  end

  defp scoped(query, organization_id, mission_id)
       when is_binary(organization_id) and organization_id != "" and is_binary(mission_id) and
              mission_id != "" do
    where(
      query,
      [row],
      (is_nil(row.organization_id) or row.organization_id == ^organization_id) and
        (is_nil(row.mission_id) or row.mission_id == ^mission_id)
    )
  end

  defp subject(query, _field, nil), do: query

  defp subject(query, field, id) when is_binary(id),
    do: where(query, [row], field(row, ^field) == ^id)

  defp page(query, page, convert) when is_integer(page) and page in 1..1_000_000 do
    rows = query |> offset(^((page - 1) * @page_size)) |> limit(^(@page_size + 1)) |> Repo.all()

    %{
      entries: rows |> Enum.take(@page_size) |> Enum.map(convert),
      page: page,
      page_size: @page_size,
      has_next: length(rows) > @page_size
    }
  end
end
