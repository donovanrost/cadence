defmodule Cadence.Telemetry.HistoryStore.Postgres do
  @moduledoc """
  Postgres-backed telemetry sample history.
  """

  @behaviour Cadence.Telemetry.HistoryStore

  import Ecto.Query

  alias Cadence.Persistence.Schemas.TelemetrySampleRow
  alias Cadence.Repo

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_samples(samples) when is_list(samples) do
    rows = sample_rows(samples)

    case rows do
      [] ->
        :ok

      [_ | _] ->
        case Repo.insert_all(TelemetrySampleRow, rows) do
          {count, _rows} when count == length(rows) -> :ok
          {count, _rows} -> {:error, {:insert_all_count_mismatch, :telemetry_samples, count}}
        end
    end
  end

  @impl true
  def sample_history(mission_id, point_id, opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)
    from_receipt_time = Keyword.get(opts, :from_receipt_time)
    to_receipt_time = Keyword.get(opts, :to_receipt_time)

    query =
      TelemetrySampleRow
      |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
      |> maybe_filter_spacecraft(spacecraft_id)
      |> maybe_filter_from_receipt_time(from_receipt_time)
      |> maybe_filter_to_receipt_time(to_receipt_time)
      |> order_history(order)
      |> limit(^limit)

    query
    |> Repo.all()
    |> Enum.map(&TelemetrySampleRow.to_domain/1)
  end

  @impl true
  def reset do
    _ = Repo.delete_all(TelemetrySampleRow)
    :ok
  end

  defp sample_rows(samples) do
    inserted_at = DateTime.utc_now()
    Enum.map(samples, &TelemetrySampleRow.insert_attrs(&1, inserted_at))
  end

  defp maybe_filter_spacecraft(query, nil), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id) do
    where(query, [row], row.spacecraft_id == ^spacecraft_id)
  end

  defp maybe_filter_from_receipt_time(query, nil), do: query

  defp maybe_filter_from_receipt_time(query, %DateTime{} = from_receipt_time) do
    where(query, [row], row.receipt_time >= ^from_receipt_time)
  end

  defp maybe_filter_to_receipt_time(query, nil), do: query

  defp maybe_filter_to_receipt_time(query, %DateTime{} = to_receipt_time) do
    where(query, [row], row.receipt_time <= ^to_receipt_time)
  end

  defp order_history(query, :asc) do
    order_by(query, [row], asc: row.receipt_time, asc: row.sample_id)
  end

  defp order_history(query, _order) do
    order_by(query, [row], desc: row.receipt_time, desc: row.sample_id)
  end
end
