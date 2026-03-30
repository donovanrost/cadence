defmodule Cadence.Telemetry.CurrentValueStore.ETS do
  @moduledoc """
  ETS-backed current value table for low-latency mission reads.
  """

  use GenServer

  @behaviour Cadence.Telemetry.CurrentValueStore

  alias Cadence.Telemetry.Sample

  @mission_scope_key "__mission__"
  @table_name :cadence_telemetry_current_values

  @impl true
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]}
    }
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def hot_path_safe?, do: true

  @impl true
  def init(_opts) do
    _table =
      :ets.new(@table_name, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, @table_name}
  end

  @impl true
  def record_samples(samples) when is_list(samples) do
    table = ensure_table!()

    samples
    |> latest_per_key()
    |> Enum.each(fn {key, sample} ->
      case :ets.lookup(table, key) do
        [{^key, existing_sample}] ->
          if sample_newer?(sample, existing_sample) do
            true = :ets.insert(table, {key, sample})
          end

        [] ->
          true = :ets.insert(table, {key, sample})
      end
    end)

    :ok
  end

  @impl true
  def latest_value(mission_id, point_id, opts) do
    table = ensure_table!()
    key = {mission_id, spacecraft_scope_id(Keyword.get(opts, :spacecraft_id)), point_id}

    case :ets.lookup(table, key) do
      [{^key, %Sample{} = sample}] -> sample
      [] -> nil
    end
  end

  @impl true
  def latest_values_for_mission(mission_id, opts) do
    spacecraft_filter = Keyword.get(opts, :spacecraft_id)
    table = ensure_table!()

    :ets.foldl(
      fn
        {{^mission_id, stored_scope_id, _point_id}, %Sample{} = sample}, acc ->
          if is_nil(spacecraft_filter) or
               stored_scope_id == spacecraft_scope_id(spacecraft_filter) do
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
  def reset do
    table = ensure_table!()
    true = :ets.delete_all_objects(table)
    :ok
  end

  @impl true
  def reset(mission_id) when is_binary(mission_id) do
    table = ensure_table!()
    true = :ets.match_delete(table, {{mission_id, :_, :_}, :_})
    :ok
  end

  defp ensure_table! do
    case :ets.whereis(@table_name) do
      :undefined -> raise "#{inspect(__MODULE__)} is not started"
      table -> table
    end
  end

  defp latest_per_key(samples) do
    Enum.reduce(samples, %{}, fn %Sample{} = sample, acc ->
      key = key(sample)

      Map.update(acc, key, sample, fn existing_sample ->
        if sample_newer?(sample, existing_sample), do: sample, else: existing_sample
      end)
    end)
  end

  defp key(%Sample{} = sample) do
    {sample.mission_id, spacecraft_scope_id(sample.spacecraft_id), sample.point_id}
  end

  defp spacecraft_scope_id(nil), do: @mission_scope_key
  defp spacecraft_scope_id(spacecraft_id), do: spacecraft_id

  defp sample_newer?(%Sample{} = sample, %Sample{} = existing_sample) do
    compare_sort_keys(sample_sort_key(sample), sample_sort_key(existing_sample)) == :gt
  end

  defp sample_sort_key(%Sample{} = sample) do
    {sample.generation_time || sample.receipt_time, sample.receipt_time, sample.sample_id}
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
