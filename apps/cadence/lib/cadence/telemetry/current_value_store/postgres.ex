defmodule Cadence.Telemetry.CurrentValueStore.Postgres do
  @moduledoc """
  Postgres-backed current value table used for tests and rebuild flows.
  """

  @behaviour Cadence.Telemetry.CurrentValueStore

  import Ecto.Query

  alias Cadence.Persistence.Schemas.TelemetryLatestValueRow
  alias Cadence.Repo
  alias Cadence.Telemetry.Sample

  @mission_scope_key "__mission__"

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def hot_path_safe?, do: false

  @impl true
  def record_samples(samples) when is_list(samples) do
    samples
    |> latest_per_key()
    |> persist_latest_samples()
  end

  @impl true
  def latest_value(mission_id, point_id, opts) do
    mission_id
    |> latest_value_query(point_id, opts)
    |> Repo.one()
    |> maybe_to_sample()
  end

  @impl true
  def latest_values_for_mission(mission_id, opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    query =
      TelemetryLatestValueRow
      |> where([row], row.mission_id == ^mission_id)
      |> maybe_filter_spacecraft(spacecraft_scope_id, opts)
      |> order_by([row], asc: row.point_name)

    query
    |> Repo.all()
    |> Enum.map(&TelemetryLatestValueRow.to_domain/1)
  end

  @impl true
  def reset do
    _ = Repo.delete_all(TelemetryLatestValueRow)
    :ok
  end

  @impl true
  def reset(mission_id) when is_binary(mission_id) do
    _ =
      TelemetryLatestValueRow
      |> where([row], row.mission_id == ^mission_id)
      |> Repo.delete_all()

    :ok
  end

  defp latest_value_query(mission_id, point_id, opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    TelemetryLatestValueRow
    |> where([row], row.mission_id == ^mission_id and row.point_id == ^point_id)
    |> maybe_filter_spacecraft(spacecraft_scope_id, opts)
    |> order_by([row], desc: row.receipt_time, desc: row.generation_time, desc: row.sample_id)
    |> limit(1)
  end

  defp maybe_filter_spacecraft(query, spacecraft_scope_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      where(query, [row], row.spacecraft_scope_id == ^spacecraft_scope_id)
    else
      query
    end
  end

  defp maybe_to_sample(nil), do: nil
  defp maybe_to_sample(row), do: TelemetryLatestValueRow.to_domain(row)

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id

  defp latest_per_key(samples) do
    Enum.reduce(samples, %{}, fn %Sample{} = sample, acc ->
      key = key(sample)

      Map.update(acc, key, sample, &latest_sample(sample, &1))
    end)
  end

  defp persist_latest_samples(samples_by_key) when map_size(samples_by_key) == 0, do: :ok

  defp persist_latest_samples(samples_by_key) do
    existing_rows = existing_rows_by_key(Map.keys(samples_by_key))

    samples_to_persist =
      samples_by_key
      |> Enum.filter(fn {key, %Sample{} = sample} ->
        case Map.get(existing_rows, key) do
          nil -> true
          %TelemetryLatestValueRow{} = existing_row -> sample_newer?(sample, existing_row)
        end
      end)
      |> Enum.map(fn {_key, %Sample{} = sample} -> sample end)

    upsert_latest_samples(samples_to_persist)
  end

  defp existing_rows_by_key(keys) do
    mission_ids = keys |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    spacecraft_scope_ids = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    point_ids = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
    key_set = MapSet.new(keys)

    TelemetryLatestValueRow
    |> where([row], row.mission_id in ^mission_ids)
    |> where([row], row.spacecraft_scope_id in ^spacecraft_scope_ids)
    |> where([row], row.point_id in ^point_ids)
    |> Repo.all()
    |> Enum.reduce(%{}, fn %TelemetryLatestValueRow{} = row, acc ->
      row_key = {row.mission_id, row.spacecraft_scope_id, row.point_id}

      if MapSet.member?(key_set, row_key) do
        Map.put(acc, row_key, row)
      else
        acc
      end
    end)
  end

  defp upsert_latest_samples([]), do: :ok

  defp upsert_latest_samples(samples) do
    now = DateTime.utc_now()
    rows = Enum.map(samples, &TelemetryLatestValueRow.insert_attrs(&1, now))

    case Repo.insert_all(TelemetryLatestValueRow, rows,
           conflict_target: [:mission_id, :spacecraft_scope_id, :point_id],
           on_conflict: {:replace, replace_fields()}
         ) do
      {count, _rows} when count == length(rows) -> :ok
      {count, _rows} -> {:error, {:insert_all_count_mismatch, :telemetry_latest_values, count}}
    end
  end

  defp replace_fields do
    [
      :spacecraft_id,
      :point_name,
      :sample_id,
      :packet_id,
      :evidence_id,
      :packet_definition_id,
      :packet_definition_version,
      :raw_value,
      :engineering_value,
      :quality_state,
      :generation_time,
      :receipt_time,
      :provenance,
      :updated_at
    ]
  end

  defp key(%Sample{} = sample) do
    {sample.mission_id, spacecraft_scope_id(sample.spacecraft_id), sample.point_id}
  end

  defp latest_sample(%Sample{} = sample, %Sample{} = existing_sample) do
    if sample_newer?(sample, existing_sample), do: sample, else: existing_sample
  end

  defp sample_newer?(%Sample{} = sample, %TelemetryLatestValueRow{} = latest_value_row) do
    compare_sort_keys(sample_sort_key(sample), row_sort_key(latest_value_row)) == :gt
  end

  defp sample_newer?(%Sample{} = sample, %Sample{} = existing_sample) do
    compare_sort_keys(sample_sort_key(sample), sample_sort_key(existing_sample)) == :gt
  end

  defp sample_sort_key(%Sample{} = sample) do
    {sample.generation_time || sample.receipt_time, sample.receipt_time, sample.sample_id}
  end

  defp row_sort_key(%TelemetryLatestValueRow{} = row) do
    {row.generation_time || row.receipt_time, row.receipt_time, row.sample_id}
  end

  defp compare_sort_keys({time_a, receipt_a, sample_id_a}, {time_b, receipt_b, sample_id_b}) do
    case DateTime.compare(time_a, time_b) do
      :eq ->
        case DateTime.compare(receipt_a, receipt_b) do
          :eq -> compare_ids(sample_id_a, sample_id_b)
          other -> other
        end

      other ->
        other
    end
  end

  defp compare_ids(id_a, id_b) when is_binary(id_a) and is_binary(id_b) do
    cond do
      id_a > id_b -> :gt
      id_a < id_b -> :lt
      true -> :eq
    end
  end
end
