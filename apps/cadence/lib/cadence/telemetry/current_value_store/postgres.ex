defmodule Cadence.Telemetry.CurrentValueStore.Postgres do
  @moduledoc """
  Postgres-backed current value table used for tests and rebuild flows.
  """

  @behaviour Cadence.Telemetry.CurrentValueStore

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Telemetry.CurrentValueStore.Postgres.TelemetryLatestValueRow
  alias Cadence.Telemetry.LatestProjectionOrder
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.SelectionPolicy
  alias Cadence.Telemetry.SourceFilters

  @mission_scope_key "__mission__"

  @impl true
  def child_spec(_opts), do: nil

  @impl true
  def hot_path_safe?, do: false

  @impl true
  def record_samples(samples) when is_list(samples) do
    samples
    |> SelectionPolicy.selected_samples([])
    |> latest_per_key()
    |> persist_latest_samples()
  end

  @impl true
  def replace_value(mission_id, point_id, nil, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    _ =
      TelemetryLatestValueRow
      |> where(
        [row],
        row.mission_id == ^mission_id and row.point_id == ^point_id and
          row.spacecraft_scope_id == ^spacecraft_scope_id
      )
      |> maybe_filter_source(opts)
      |> Repo.delete_all()

    :ok
  end

  @impl true
  def replace_value(mission_id, point_id, %Sample{} = sample, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    with :ok <- validate_replacement_scope(mission_id, point_id, sample) do
      upsert_latest_samples([sample])
    end
  end

  @impl true
  def replace_values_for_scope(mission_id, samples, opts)
      when is_binary(mission_id) and is_list(samples) and is_list(opts) do
    Repo.transaction(fn ->
      TelemetryLatestValueRow
      |> where([row], row.mission_id == ^mission_id)
      |> maybe_filter_rebuild_spacecraft(Keyword.get(opts, :spacecraft_id))
      |> maybe_filter_source(opts)
      |> Repo.delete_all()

      case upsert_latest_samples(samples) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def latest_value(mission_id, point_id, opts) do
    mission_id
    |> latest_value_query(point_id, opts)
    |> Repo.one()
    |> maybe_to_sample(opts)
  end

  @impl true
  def latest_values_for_mission(mission_id, opts) do
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    query =
      TelemetryLatestValueRow
      |> where([row], row.mission_id == ^mission_id)
      |> maybe_filter_spacecraft(spacecraft_scope_id, opts)
      |> maybe_filter_source(opts)
      |> order_by([row], asc: row.point_name)

    query
    |> Repo.all()
    |> Enum.map(&TelemetryLatestValueRow.to_domain/1)
    |> SelectionPolicy.selected_samples(opts)
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
    |> maybe_filter_source(opts)
    |> order_by([row],
      desc: fragment("COALESCE(?, ?)", row.generation_time, row.receipt_time),
      desc: row.receipt_time,
      desc: row.sample_id
    )
    |> limit(1)
  end

  defp maybe_filter_spacecraft(query, spacecraft_scope_id, opts) do
    if Keyword.has_key?(opts, :spacecraft_id) do
      where(query, [row], row.spacecraft_scope_id == ^spacecraft_scope_id)
    else
      query
    end
  end

  defp maybe_filter_rebuild_spacecraft(query, nil), do: query

  defp maybe_filter_rebuild_spacecraft(query, spacecraft_id) do
    where(query, [row], row.spacecraft_scope_id == ^spacecraft_id)
  end

  defp maybe_filter_source(query, opts) do
    opts
    |> SourceFilters.normalize()
    |> Enum.reduce(query, fn
      {:realm, realm}, query ->
        where(query, [row], row.realm == ^realm)

      {:data_source_id, data_source_id}, query ->
        where(query, [row], row.data_source_id == ^data_source_id)

      {:binding_id, binding_id}, query ->
        where(query, [row], row.binding_id == ^binding_id)

      {:replay_run_id, replay_run_id}, query ->
        where(
          query,
          [row],
          fragment("?->'storage'->>'replay_run_id'", row.provenance) == ^replay_run_id
        )

      {:source_endpoint_ids, source_endpoint_ids}, query ->
        where(
          query,
          [row],
          fragment("?->'storage'->>'source_endpoint_id'", row.provenance) in ^source_endpoint_ids
        )
    end)
  end

  defp maybe_to_sample(nil, _opts), do: nil

  defp maybe_to_sample(row, opts) do
    sample = TelemetryLatestValueRow.to_domain(row)

    if SelectionPolicy.selected_sample?(sample, opts), do: sample
  end

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
    realms = keys |> Enum.map(&elem(&1, 3)) |> Enum.uniq()
    data_source_ids = keys |> Enum.map(&elem(&1, 4)) |> Enum.uniq()
    binding_ids = keys |> Enum.map(&elem(&1, 5)) |> Enum.uniq()
    key_set = MapSet.new(keys)

    TelemetryLatestValueRow
    |> where([row], row.mission_id in ^mission_ids)
    |> where([row], row.spacecraft_scope_id in ^spacecraft_scope_ids)
    |> where([row], row.point_id in ^point_ids)
    |> where([row], row.realm in ^realms)
    |> where([row], row.data_source_id in ^data_source_ids)
    |> where([row], row.binding_id in ^binding_ids)
    |> Repo.all()
    |> Enum.reduce(%{}, fn %TelemetryLatestValueRow{} = row, acc ->
      row_key =
        {row.mission_id, row.spacecraft_scope_id, row.point_id, row.realm, row.data_source_id,
         row.binding_id}

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
           conflict_target: [
             :mission_id,
             :spacecraft_scope_id,
             :point_id,
             :realm,
             :data_source_id,
             :binding_id
           ],
           on_conflict: {:replace, replace_fields()}
         ) do
      {count, _rows} when count == length(rows) -> :ok
      {count, _rows} -> {:error, {:insert_all_count_mismatch, :telemetry_latest_values, count}}
    end
  end

  defp validate_replacement_scope(mission_id, point_id, %Sample{} = sample) do
    cond do
      sample.mission_id != mission_id ->
        {:error, {:mission_mismatch, mission_id, sample.mission_id}}

      sample.point_id != point_id ->
        {:error, {:point_mismatch, point_id, sample.point_id}}

      true ->
        :ok
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
    {realm, data_source_id, binding_id} = SourceFilters.sample_key(sample)

    {
      sample.mission_id,
      spacecraft_scope_id(sample.spacecraft_id),
      sample.point_id,
      realm,
      data_source_id,
      binding_id
    }
  end

  defp latest_sample(%Sample{} = sample, %Sample{} = existing_sample) do
    if sample_newer?(sample, existing_sample), do: sample, else: existing_sample
  end

  defp sample_newer?(%Sample{} = sample, %TelemetryLatestValueRow{} = latest_value_row) do
    LatestProjectionOrder.newer?(sample, latest_value_row, :sample_id)
  end

  defp sample_newer?(%Sample{} = sample, %Sample{} = existing_sample) do
    LatestProjectionOrder.newer?(sample, existing_sample, :sample_id)
  end
end
