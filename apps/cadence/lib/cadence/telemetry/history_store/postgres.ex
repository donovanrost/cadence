defmodule Cadence.Telemetry.HistoryStore.Postgres do
  @moduledoc """
  Postgres-backed telemetry sample history.
  """

  @behaviour Cadence.Telemetry.HistoryStore

  import Ecto.Query

  alias Cadence.Persistence.Schemas.{
    TelemetryObservationIdentityStateRow,
    TelemetrySampleRow
  }

  alias Cadence.Repo
  alias Cadence.Telemetry.{EffectiveSelection, SourceFilters}

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def persist_samples(samples) when is_list(samples) do
    rows = sample_rows(samples)

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

  @impl true
  def sample_history(mission_id, point_id, opts) do
    limit = Keyword.get(opts, :limit, 100)
    spacecraft_id = Keyword.get(opts, :spacecraft_id)
    order = Keyword.get(opts, :order, :desc)
    from_receipt_time = Keyword.get(opts, :from_receipt_time)
    to_receipt_time = Keyword.get(opts, :to_receipt_time)
    from_observed_at = Keyword.get(opts, :from_observed_at)
    to_observed_at = Keyword.get(opts, :to_observed_at)

    query =
      TelemetrySampleRow
      |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
      |> maybe_filter_spacecraft(spacecraft_id)
      |> maybe_filter_from_receipt_time(from_receipt_time)
      |> maybe_filter_to_receipt_time(to_receipt_time)
      |> maybe_filter_from_observed_at(from_observed_at)
      |> maybe_filter_to_observed_at(to_observed_at)
      |> order_history(order, Keyword.get(opts, :time_axis))

    query
    |> Repo.all()
    |> Enum.map(&TelemetrySampleRow.to_domain/1)
    |> SourceFilters.filter_samples(opts)
    |> EffectiveSelection.selected_samples(
      identity_rows_for_point(mission_id, point_id, opts),
      opts
    )
    |> Enum.take(limit)
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

  defp identity_rows_for_point(mission_id, point_id, opts) do
    TelemetryObservationIdentityStateRow
    |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
    |> maybe_filter_organization(Keyword.get(opts, :organization_id))
    |> maybe_filter_spacecraft(Keyword.get(opts, :spacecraft_id))
    |> maybe_filter_realm(Keyword.get(opts, :realm))
    |> maybe_filter_replay_run(SourceFilters.replay_run_id(opts))
    |> maybe_filter_data_source(Keyword.get(opts, :data_source_id))
    |> maybe_filter_binding(SourceFilters.binding_id(opts))
    |> Repo.all()
  end

  defp maybe_filter_organization(query, nil), do: query

  defp maybe_filter_organization(query, organization_id) do
    where(query, [row], row.organization_id == ^organization_id)
  end

  defp maybe_filter_realm(query, nil), do: query
  defp maybe_filter_realm(query, ""), do: query

  defp maybe_filter_realm(query, realm) do
    realm = to_string(realm)
    where(query, [row], row.realm == ^realm)
  end

  defp maybe_filter_replay_run(query, nil), do: query
  defp maybe_filter_replay_run(query, ""), do: query

  defp maybe_filter_replay_run(query, replay_run_id) do
    where(query, [row], row.replay_run_id == ^replay_run_id)
  end

  defp maybe_filter_data_source(query, nil), do: query
  defp maybe_filter_data_source(query, ""), do: query

  defp maybe_filter_data_source(query, data_source_id) do
    where(query, [row], row.data_source_id == ^data_source_id)
  end

  defp maybe_filter_binding(query, nil), do: query
  defp maybe_filter_binding(query, ""), do: query

  defp maybe_filter_binding(query, binding_id) do
    where(query, [row], row.binding_id == ^binding_id)
  end

  defp maybe_filter_from_receipt_time(query, nil), do: query

  defp maybe_filter_from_receipt_time(query, %DateTime{} = from_receipt_time) do
    where(query, [row], row.receipt_time >= ^from_receipt_time)
  end

  defp maybe_filter_to_receipt_time(query, nil), do: query

  defp maybe_filter_to_receipt_time(query, %DateTime{} = to_receipt_time) do
    where(query, [row], row.receipt_time <= ^to_receipt_time)
  end

  defp maybe_filter_from_observed_at(query, nil), do: query

  defp maybe_filter_from_observed_at(query, %DateTime{} = from_observed_at) do
    where(query, [row], coalesce(row.generation_time, row.receipt_time) >= ^from_observed_at)
  end

  defp maybe_filter_to_observed_at(query, nil), do: query

  defp maybe_filter_to_observed_at(query, %DateTime{} = to_observed_at) do
    where(query, [row], coalesce(row.generation_time, row.receipt_time) <= ^to_observed_at)
  end

  defp order_history(query, :asc, axis) when axis in [:generation_time, "generation_time"] do
    order_by(query, [row],
      asc: coalesce(row.generation_time, row.receipt_time),
      asc: row.receipt_time,
      asc: row.sample_id
    )
  end

  defp order_history(query, _order, axis) when axis in [:generation_time, "generation_time"] do
    order_by(query, [row],
      desc: coalesce(row.generation_time, row.receipt_time),
      desc: row.receipt_time,
      desc: row.sample_id
    )
  end

  defp order_history(query, :asc, _axis) do
    order_by(query, [row], asc: row.receipt_time, asc: row.sample_id)
  end

  defp order_history(query, _order, _axis) do
    order_by(query, [row], desc: row.receipt_time, desc: row.sample_id)
  end
end
