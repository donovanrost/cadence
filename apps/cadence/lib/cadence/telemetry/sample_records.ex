defmodule Cadence.Telemetry.SampleRecords do
  @moduledoc """
  Data-plane persistence boundary for canonical Postgres telemetry samples.

  Consumers receive telemetry domain structs; the Ecto row remains private to
  this store so projections and management-facing resolvers do not depend on
  the physical read-model schema.
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.SampleRecords.TelemetrySampleRow

  @spec persist_samples([Sample.t()]) :: :ok | {:error, term()}
  def persist_samples(samples) when is_list(samples) do
    rows = insert_rows(samples)

    case rows do
      [] ->
        :ok

      [_ | _] ->
        case Repo.insert_all(TelemetrySampleRow, rows,
               conflict_target: :sample_id,
               on_conflict: :nothing
             ) do
          {count, _rows} when count <= length(rows) -> :ok
          {count, _rows} -> {:error, {:insert_all_count_mismatch, :telemetry_samples, count}}
        end
    end
  end

  @spec fetch_sample(binary(), binary(), binary()) :: {:ok, Sample.t()} | {:error, :not_found}
  def fetch_sample(organization_id, mission_id, sample_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(sample_id) do
    TelemetrySampleRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.sample_id == ^sample_id
    )
    |> Repo.one()
    |> case do
      %TelemetrySampleRow{} = row -> {:ok, TelemetrySampleRow.to_domain(row)}
      nil -> {:error, :not_found}
    end
  end

  @spec list_samples(binary(), keyword()) :: [Sample.t()]
  def list_samples(mission_id, opts \\ []) when is_binary(mission_id) and is_list(opts) do
    TelemetrySampleRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter(:organization_id, Keyword.get(opts, :organization_id))
    |> maybe_filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter(:point_id, Keyword.get(opts, :point_id))
    |> maybe_filter(:evidence_id, Keyword.get(opts, :evidence_id))
    |> maybe_filter_in(:evidence_id, Keyword.get(opts, :evidence_ids))
    |> maybe_filter_from_receipt_time(Keyword.get(opts, :from_receipt_time))
    |> maybe_filter_to_receipt_time(Keyword.get(opts, :to_receipt_time))
    |> maybe_filter_from_observed_at(Keyword.get(opts, :from_observed_at))
    |> maybe_filter_to_observed_at(Keyword.get(opts, :to_observed_at))
    |> maybe_order(Keyword.get(opts, :order), Keyword.get(opts, :time_axis))
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(&TelemetrySampleRow.to_domain/1)
  end

  @spec reset() :: :ok
  def reset do
    _ = Repo.delete_all(TelemetrySampleRow)
    :ok
  end

  defp insert_rows(samples) do
    inserted_at = DateTime.utc_now()
    Enum.map(samples, &TelemetrySampleRow.insert_attrs(&1, inserted_at))
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp maybe_filter_in(query, _field, nil), do: query
  defp maybe_filter_in(query, _field, []), do: where(query, false)

  defp maybe_filter_in(query, field, values) when is_list(values) do
    where(query, [row], field(row, ^field) in ^values)
  end

  defp maybe_filter_from_receipt_time(query, nil), do: query

  defp maybe_filter_from_receipt_time(query, %DateTime{} = value),
    do: where(query, [row], row.receipt_time >= ^value)

  defp maybe_filter_to_receipt_time(query, nil), do: query

  defp maybe_filter_to_receipt_time(query, %DateTime{} = value),
    do: where(query, [row], row.receipt_time <= ^value)

  defp maybe_filter_from_observed_at(query, nil), do: query

  defp maybe_filter_from_observed_at(query, %DateTime{} = value),
    do: where(query, [row], coalesce(row.generation_time, row.receipt_time) >= ^value)

  defp maybe_filter_to_observed_at(query, nil), do: query

  defp maybe_filter_to_observed_at(query, %DateTime{} = value),
    do: where(query, [row], coalesce(row.generation_time, row.receipt_time) <= ^value)

  defp maybe_order(query, :asc, axis) when axis in [:generation_time, "generation_time"],
    do:
      order_by(query, [row],
        asc: coalesce(row.generation_time, row.receipt_time),
        asc: row.receipt_time,
        asc: row.sample_id
      )

  defp maybe_order(query, _order, axis) when axis in [:generation_time, "generation_time"],
    do:
      order_by(query, [row],
        desc: coalesce(row.generation_time, row.receipt_time),
        desc: row.receipt_time,
        desc: row.sample_id
      )

  defp maybe_order(query, :receipt_asc, _axis),
    do: order_by(query, [row], asc: row.receipt_time, asc: row.sample_id)

  defp maybe_order(query, :receipt_desc, _axis),
    do: order_by(query, [row], desc: row.receipt_time, desc: row.sample_id)

  defp maybe_order(query, :evidence_point, _axis),
    do: order_by(query, [row], asc: row.evidence_id, asc: row.point_id, asc: row.sample_id)

  defp maybe_order(query, :asc, _axis),
    do: order_by(query, [row], asc: row.receipt_time, asc: row.sample_id)

  defp maybe_order(query, order, _axis) when order in [:desc, nil],
    do: order_by(query, [row], desc: row.receipt_time, desc: row.sample_id)

  defp maybe_order(query, _order, _axis), do: query

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query
end
