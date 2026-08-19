defmodule Cadence.Telemetry.CurrentValueStore.ETS do
  @moduledoc """
  ETS-backed current value table for low-latency mission reads.
  """

  use GenServer

  @behaviour Cadence.Telemetry.CurrentValueStore

  alias Cadence.Telemetry.{LatestProjectionOrder, SelectionPolicy, SourceFilters}
  alias Cadence.Telemetry.Sample

  @mission_scope_key "__mission__"
  @table_name :cadence_telemetry_current_values

  @impl true
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :child_id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def hot_path_safe?, do: true

  @impl true
  def hot_path_safe?(_backend_opts), do: true

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, @table_name)

    _table =
      :ets.new(table_name, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, table_name}
  end

  @impl true
  def record_samples(samples) when is_list(samples), do: record_samples(samples, [])

  @impl true
  def record_samples(samples, backend_opts) when is_list(samples) and is_list(backend_opts) do
    table = ensure_table!(backend_opts)

    samples
    |> SelectionPolicy.selected_samples([])
    |> latest_per_key()
    |> Enum.each(fn {key, sample} ->
      maybe_store_sample(table, key, sample)
    end)

    :ok
  end

  @impl true
  def replace_value(mission_id, point_id, sample_or_nil, opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) do
    replace_value(mission_id, point_id, sample_or_nil, opts, [])
  end

  @impl true
  def replace_value(mission_id, point_id, nil, opts, backend_opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) and
             is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    table
    |> keys_for_point(mission_id, spacecraft_scope_id, point_id, opts)
    |> Enum.each(&:ets.delete(table, &1))

    :ok
  end

  def replace_value(mission_id, point_id, %Sample{} = sample, opts, backend_opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) and
             is_list(backend_opts) do
    with :ok <- validate_replacement_scope(mission_id, point_id, sample) do
      table = ensure_table!(backend_opts)
      true = :ets.insert(table, {key(sample), sample})
      :ok
    end
  end

  @impl true
  def replace_values_for_scope(mission_id, samples, opts),
    do: replace_values_for_scope(mission_id, samples, opts, [])

  @impl true
  def replace_values_for_scope(mission_id, samples, opts, backend_opts)
      when is_binary(mission_id) and is_list(samples) and is_list(opts) and
             is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    spacecraft_filter = Keyword.get(opts, :spacecraft_id)

    :ets.foldl(
      fn
        {{^mission_id, stored_scope_id, _point_id, _realm, _data_source_id, _binding_id} = key,
         %Sample{} = sample},
        :ok ->
          if (is_nil(spacecraft_filter) or
                stored_scope_id == spacecraft_scope_id(spacecraft_filter)) and
               SourceFilters.sample_matches?(sample, opts) do
            true = :ets.delete(table, key)
          end

          :ok

        _entry, :ok ->
          :ok
      end,
      :ok,
      table
    )

    Enum.each(samples, fn %Sample{} = sample ->
      true = :ets.insert(table, {key(sample), sample})
    end)

    :ok
  end

  @impl true
  def latest_value(mission_id, point_id, opts), do: latest_value(mission_id, point_id, opts, [])

  @impl true
  def latest_value(mission_id, point_id, opts, backend_opts)
      when is_binary(mission_id) and is_binary(point_id) and is_list(opts) and
             is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    spacecraft_scope_id = spacecraft_scope_id(Keyword.get(opts, :spacecraft_id))

    table
    |> samples_for_point(mission_id, spacecraft_scope_id, point_id, opts)
    |> Enum.reduce(nil, fn
      %Sample{} = sample, nil -> sample
      %Sample{} = sample, %Sample{} = latest_sample -> latest_sample(sample, latest_sample)
    end)
  end

  @impl true
  def latest_values_for_mission(mission_id, opts),
    do: latest_values_for_mission(mission_id, opts, [])

  @impl true
  def latest_values_for_mission(mission_id, opts, backend_opts)
      when is_binary(mission_id) and is_list(opts) and is_list(backend_opts) do
    spacecraft_filter = Keyword.get(opts, :spacecraft_id)
    table = ensure_table!(backend_opts)

    :ets.foldl(
      fn
        {{^mission_id, stored_scope_id, _point_id, _realm, _data_source_id, _binding_id},
         %Sample{} = sample},
        acc ->
          if (is_nil(spacecraft_filter) or
                stored_scope_id == spacecraft_scope_id(spacecraft_filter)) and
               SourceFilters.sample_matches?(sample, opts) and
               SelectionPolicy.selected_sample?(sample, opts) do
            [sample | acc]
          else
            acc
          end

        _entry, acc ->
          acc
      end,
      [],
      table
    )
    |> Enum.sort_by(& &1.point_name)
  end

  @impl true
  def reset, do: reset(:all, [])

  @impl true
  def reset(mission_id) when is_binary(mission_id), do: reset(mission_id, [])

  @impl true
  def reset(:all, backend_opts) when is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    true = :ets.delete_all_objects(table)
    :ok
  end

  def reset(mission_id, backend_opts) when is_binary(mission_id) and is_list(backend_opts) do
    table = ensure_table!(backend_opts)
    true = :ets.match_delete(table, {{mission_id, :_, :_, :_, :_, :_}, :_})
    :ok
  end

  defp ensure_table!(backend_opts) do
    table_name = Keyword.get(backend_opts, :table_name, @table_name)

    case :ets.whereis(table_name) do
      :undefined -> raise "#{inspect(__MODULE__)} is not started"
      table -> table
    end
  end

  defp latest_per_key(samples) do
    Enum.reduce(samples, %{}, fn %Sample{} = sample, acc ->
      key = key(sample)

      Map.update(acc, key, sample, &latest_sample(sample, &1))
    end)
  end

  defp maybe_store_sample(table, key, %Sample{} = sample) do
    case :ets.lookup(table, key) do
      [{^key, existing_sample}] ->
        maybe_insert_newer_sample(table, key, sample, existing_sample)

      [] ->
        true = :ets.insert(table, {key, sample})
    end
  end

  defp maybe_insert_newer_sample(table, key, %Sample{} = sample, %Sample{} = existing_sample) do
    if sample_newer?(sample, existing_sample) do
      true = :ets.insert(table, {key, sample})
    end
  end

  defp latest_sample(%Sample{} = sample, %Sample{} = existing_sample) do
    if sample_newer?(sample, existing_sample), do: sample, else: existing_sample
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

  defp keys_for_point(table, mission_id, spacecraft_scope_id, point_id, opts) do
    table
    |> samples_for_point(mission_id, spacecraft_scope_id, point_id, opts)
    |> Enum.map(&key/1)
  end

  defp samples_for_point(table, mission_id, spacecraft_scope_id, point_id, opts) do
    :ets.foldl(
      fn
        {{^mission_id, ^spacecraft_scope_id, ^point_id, _realm, _data_source_id, _binding_id},
         %Sample{} = sample},
        acc ->
          if SourceFilters.sample_matches?(sample, opts) and
               SelectionPolicy.selected_sample?(sample, opts) do
            [sample | acc]
          else
            acc
          end

        _entry, acc ->
          acc
      end,
      [],
      table
    )
  end

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id

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

  defp sample_newer?(%Sample{} = sample, %Sample{} = existing_sample) do
    LatestProjectionOrder.newer?(sample, existing_sample, :sample_id)
  end
end
