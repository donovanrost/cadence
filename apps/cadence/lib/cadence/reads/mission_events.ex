defmodule Cadence.Reads.MissionEvents do
  @moduledoc """
  Mission-scoped timeline reads over the `mission_events` projection.
  """

  import Ecto.Query

  alias Cadence.MissionEvents.Entry
  alias Cadence.Persistence.Schemas.MissionEventRow
  alias Cadence.Repo

  @spec fetch_for_mission(binary(), binary(), binary()) ::
          {:ok, Entry.t()} | {:error, :mission_event_not_found}
  def fetch_for_mission(organization_id, mission_id, mission_event_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(mission_event_id) do
    MissionEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.mission_event_id == ^mission_event_id
    )
    |> Repo.one()
    |> case do
      %MissionEventRow{} = row -> {:ok, MissionEventRow.to_domain(row)}
      nil -> {:error, :mission_event_not_found}
    end
  end

  @spec list_for_mission(binary(), keyword()) :: [Entry.t()]
  def list_for_mission(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    cursor = Keyword.get(opts, :cursor)

    MissionEventRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_apply_cursor(cursor)
    |> maybe_filter_time_range(opts)
    |> maybe_filter_atoms(:category, Keyword.get(opts, :category))
    |> maybe_filter_atoms(:kind, Keyword.get(opts, :kind))
    |> maybe_filter_atoms(:severity, Keyword.get(opts, :severity))
    |> maybe_filter_equals(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:scheduled_contact_id, Keyword.get(opts, :scheduled_contact_id))
    |> maybe_filter_equals(:realized_contact_id, Keyword.get(opts, :realized_contact_id))
    |> maybe_filter_equals(:path_id, Keyword.get(opts, :path_id))
    |> maybe_filter_equals(:capability_instance_id, Keyword.get(opts, :capability_instance_id))
    |> order_by_direction(Keyword.get(opts, :order, :desc))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&MissionEventRow.to_domain/1)
  end

  @spec list_for_mission(binary(), binary(), keyword()) :: [Entry.t()]
  def list_for_mission(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)
    cursor = Keyword.get(opts, :cursor)

    MissionEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_apply_cursor(cursor)
    |> maybe_filter_time_range(opts)
    |> maybe_filter_atoms(:category, Keyword.get(opts, :category))
    |> maybe_filter_atoms(:kind, Keyword.get(opts, :kind))
    |> maybe_filter_atoms(:severity, Keyword.get(opts, :severity))
    |> maybe_filter_equals(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:scheduled_contact_id, Keyword.get(opts, :scheduled_contact_id))
    |> maybe_filter_equals(:realized_contact_id, Keyword.get(opts, :realized_contact_id))
    |> maybe_filter_equals(:path_id, Keyword.get(opts, :path_id))
    |> maybe_filter_equals(:capability_instance_id, Keyword.get(opts, :capability_instance_id))
    |> order_by_direction(Keyword.get(opts, :order, :desc))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&MissionEventRow.to_domain/1)
  end

  defp maybe_apply_cursor(query, %{
         occurred_at: %DateTime{} = occurred_at,
         mission_event_id: event_id
       })
       when is_binary(event_id) do
    where(
      query,
      [row],
      row.occurred_at < ^occurred_at or
        (row.occurred_at == ^occurred_at and row.mission_event_id < ^event_id)
    )
  end

  defp maybe_apply_cursor(query, %{occurred_at: %DateTime{} = occurred_at}) do
    where(query, [row], row.occurred_at < ^occurred_at)
  end

  defp maybe_apply_cursor(query, _cursor), do: query

  defp maybe_filter_time_range(query, opts) do
    query
    |> maybe_filter_from_occurred_at(Keyword.get(opts, :from_occurred_at))
    |> maybe_filter_to_occurred_at(Keyword.get(opts, :to_occurred_at))
  end

  defp maybe_filter_from_occurred_at(query, %DateTime{} = from) do
    where(query, [row], row.occurred_at >= ^from)
  end

  defp maybe_filter_from_occurred_at(query, _from), do: query

  defp maybe_filter_to_occurred_at(query, %DateTime{} = to) do
    where(query, [row], row.occurred_at < ^to)
  end

  defp maybe_filter_to_occurred_at(query, _to), do: query

  defp maybe_filter_atoms(query, _field, nil), do: query

  defp maybe_filter_atoms(query, field, values) do
    normalized_values =
      values
      |> List.wrap()
      |> Enum.map(&normalize_filter_value/1)

    where(query, [row], field(row, ^field) in ^normalized_values)
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp order_by_direction(query, :asc) do
    order_by(query, [row], asc: row.occurred_at, asc: row.mission_event_id)
  end

  defp order_by_direction(query, "asc"), do: order_by_direction(query, :asc)

  defp order_by_direction(query, _order) do
    order_by(query, [row], desc: row.occurred_at, desc: row.mission_event_id)
  end

  defp normalize_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_filter_value(value) when is_binary(value), do: value
end
