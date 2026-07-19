defmodule Cadence.OperationalEvents.EventQuery do
  @moduledoc false

  import Ecto.Query

  alias Cadence.OperationalEvents.Event
  alias Cadence.OperationalEvents.EventRow, as: OperationalEventRow
  alias Cadence.Repo

  @spec fetch_event(binary()) :: {:ok, Event.t()} | {:error, :not_found}
  def fetch_event(event_id) when is_binary(event_id) do
    case Repo.get(OperationalEventRow, event_id) do
      nil -> {:error, :not_found}
      %OperationalEventRow{} = row -> {:ok, OperationalEventRow.to_domain(row)}
    end
  end

  @spec fetch_event(binary(), binary(), binary()) :: {:ok, Event.t()} | {:error, :not_found}
  def fetch_event(organization_id, mission_id, event_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(event_id) do
    case Repo.get_by(OperationalEventRow,
           organization_id: organization_id,
           mission_id: mission_id,
           event_id: event_id
         ) do
      nil -> {:error, :not_found}
      %OperationalEventRow{} = row -> {:ok, OperationalEventRow.to_domain(row)}
    end
  end

  @doc false
  @spec list_all_events(binary()) :: [Event.t()]
  def list_all_events(mission_id) when is_binary(mission_id) do
    OperationalEventRow
    |> where([row], row.mission_id == ^mission_id)
    |> Repo.all()
    |> Enum.map(&OperationalEventRow.to_domain/1)
  end

  @spec list_events(binary(), keyword()) :: [Event.t()]
  def list_events(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    OperationalEventRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter_atoms(:category, Keyword.get(opts, :category))
    |> maybe_filter_atoms(:kind, Keyword.get(opts, :kind))
    |> maybe_filter_atoms(:severity, Keyword.get(opts, :severity))
    |> maybe_filter_equals(
      :subject_kind,
      normalize_optional_filter(Keyword.get(opts, :subject_kind))
    )
    |> maybe_filter_equals(:subject_id, Keyword.get(opts, :subject_id))
    |> maybe_filter_equals(
      :source_record_kind,
      normalize_optional_filter(Keyword.get(opts, :source_record_kind))
    )
    |> maybe_filter_equals(:source_record_id, Keyword.get(opts, :source_record_id))
    |> maybe_filter_replay_run_id(Keyword.get(opts, :replay_run_id))
    |> maybe_filter_time_range(opts)
    |> order_by_direction(Keyword.get(opts, :order, :desc))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&OperationalEventRow.to_domain/1)
  end

  @spec list_events(binary(), binary(), keyword()) :: [Event.t()]
  def list_events(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    OperationalEventRow
    |> where([row], row.organization_id == ^organization_id and row.mission_id == ^mission_id)
    |> maybe_filter_atoms(:category, Keyword.get(opts, :category))
    |> maybe_filter_atoms(:kind, Keyword.get(opts, :kind))
    |> maybe_filter_atoms(:severity, Keyword.get(opts, :severity))
    |> maybe_filter_equals(
      :subject_kind,
      normalize_optional_filter(Keyword.get(opts, :subject_kind))
    )
    |> maybe_filter_equals(:subject_id, Keyword.get(opts, :subject_id))
    |> maybe_filter_equals(
      :source_record_kind,
      normalize_optional_filter(Keyword.get(opts, :source_record_kind))
    )
    |> maybe_filter_equals(:source_record_id, Keyword.get(opts, :source_record_id))
    |> maybe_filter_replay_run_id(Keyword.get(opts, :replay_run_id))
    |> maybe_filter_time_range(opts)
    |> order_by_direction(Keyword.get(opts, :order, :desc))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&OperationalEventRow.to_domain/1)
  end

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

  defp maybe_filter_equals(query, field, values) when is_list(values) do
    normalized_values = Enum.map(values, &normalize_filter_value/1)
    where(query, [row], field(row, ^field) in ^normalized_values)
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp maybe_filter_replay_run_id(query, :none),
    do: where(query, [row], is_nil(row.replay_run_id))

  defp maybe_filter_replay_run_id(query, replay_run_id),
    do: maybe_filter_equals(query, :replay_run_id, replay_run_id)

  defp order_by_direction(query, :asc) do
    order_by(query, [row], asc: row.occurred_at, asc: row.event_id)
  end

  defp order_by_direction(query, "asc"), do: order_by_direction(query, :asc)

  defp order_by_direction(query, _order) do
    order_by(query, [row], desc: row.occurred_at, desc: row.event_id)
  end

  defp normalize_optional_filter(nil), do: nil
  defp normalize_optional_filter(values) when is_list(values), do: values
  defp normalize_optional_filter(value), do: normalize_filter_value(value)

  defp normalize_filter_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_filter_value(value) when is_binary(value), do: value
end
