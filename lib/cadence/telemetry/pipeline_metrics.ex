defmodule Cadence.Telemetry.PipelineMetrics do
  @moduledoc """
  High-performance metrics for telemetry pipeline using Erlang :counters and :atomics.

  Each partition has its own counter array for zero-contention updates.
  Metrics are merged when read by the profiler.

  ## Why :counters over ETS?

  - Atomic increment: single operation vs lookup + insert
  - Lock-free: no key-level locking contention
  - ~10x faster: ~20ns vs ~200ns per operation

  ## Min/Max Tracking

  Uses :atomics with compare-and-exchange for atomic min/max updates.
  This adds minimal overhead since timing is already sampled (1 in 100).

  ## Usage

      # Initialize metrics for a mission (called once at startup)
      PipelineMetrics.init(mission_id, partition_count)

      # Hot path - increment counters (called per packet)
      PipelineMetrics.inc(mission_id, partition, :packets_received)
      PipelineMetrics.inc(mission_id, partition, :packets_processed, count)

      # Hot path - record timing (called for sampled packets only)
      PipelineMetrics.record_timing(mission_id, partition, :identify, duration_us)

      # Cold path - get merged stats (called by profiler)
      PipelineMetrics.get_stats(mission_id)
  """

  @table_name :cadence_pipeline_metrics

  # Counter slot indices (per partition)
  # Each partition has its own :counters reference with these slots
  @slots %{
    # Throughput counters
    packets_received: 1,
    packets_processed: 2,
    items_processed: 3,
    packets_dropped: 4,

    # Error counters
    errors_identify: 5,
    errors_decom: 6,
    errors_convert: 7,
    errors_derive: 8,
    errors_batcher: 9,

    # Latency tracking (sum + count pairs for calculating avg)
    latency_sum_identify: 10,
    latency_count_identify: 11,
    latency_sum_decom: 12,
    latency_count_decom: 13,
    latency_sum_convert: 14,
    latency_count_convert: 15,
    latency_sum_derive: 16,
    latency_count_derive: 17,
    latency_sum_limits: 18,
    latency_count_limits: 19,
    latency_sum_cvt_batch: 20,
    latency_count_cvt_batch: 21,
    latency_sum_ets_write: 22,
    latency_count_ets_write: 23,
    latency_sum_end_to_end: 24,
    latency_count_end_to_end: 25,

    # Bitrate tracking
    bytes_received: 26
  }

  @slot_count 27

  # Atomics slot indices for min/max (per partition)
  # Uses :atomics for compare-and-exchange operations
  @minmax_slots %{
    min_identify: 1,
    max_identify: 2,
    min_decom: 3,
    max_decom: 4,
    min_convert: 5,
    max_convert: 6,
    min_derive: 7,
    max_derive: 8,
    min_limits: 9,
    max_limits: 10,
    min_cvt_batch: 11,
    max_cvt_batch: 12,
    min_ets_write: 13,
    max_ets_write: 14,
    min_end_to_end: 15,
    max_end_to_end: 16
  }

  @minmax_slot_count 16

  # Sentinel value for uninitialized min (max possible value)
  @min_sentinel 999_999_999

  # Timing stages we track
  @timing_stages [
    :identify,
    :decom,
    :convert,
    :derive,
    :limits,
    :cvt_batch,
    :ets_write,
    :end_to_end
  ]

  # Error stages we track
  @error_stages [:identify, :decom, :convert, :derive, :batcher]

  @doc """
  Ensures the metrics ETS table exists.
  """
  def ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set,
          :named_table,
          :public,
          read_concurrency: true
        ])

      _ref ->
        :ok
    end
  end

  @doc """
  Initializes metrics for a mission with the given partition count.

  Creates a :counters reference for each partition and stores them in ETS.
  Also creates :atomics for min/max tracking.
  Also stores metadata like partition_count and start_time.
  """
  def init(mission_id, partition_count) do
    ensure_table()

    # Create counter and atomics references for each partition
    for partition <- 0..(partition_count - 1) do
      # Counters for sum/count/throughput
      counter_ref = :counters.new(@slot_count, [:write_concurrency])
      :ets.insert(@table_name, {{mission_id, :counters, partition}, counter_ref})

      # Atomics for min/max (uses signed integers for CAS)
      atomics_ref = :atomics.new(@minmax_slot_count, signed: true)

      # Initialize min slots to sentinel value (so first value becomes min)
      for stage <- @timing_stages do
        min_slot = Map.get(@minmax_slots, :"min_#{stage}")
        if min_slot, do: :atomics.put(atomics_ref, min_slot, @min_sentinel)
      end

      :ets.insert(@table_name, {{mission_id, :atomics, partition}, atomics_ref})
    end

    # Store metadata
    :ets.insert(@table_name, {{mission_id, :partition_count}, partition_count})
    :ets.insert(@table_name, {{mission_id, :started_at}, System.monotonic_time(:millisecond)})

    :ok
  end

  @doc """
  Atomically increments a counter for a specific partition.

  This is the hot path - designed for minimal overhead.
  """
  def inc(mission_id, partition, counter, amount \\ 1) do
    slot = Map.fetch!(@slots, counter)

    case get_counter_ref(mission_id, partition) do
      # Mission not initialized, silently ignore
      nil -> :ok
      ref -> :counters.add(ref, slot, amount)
    end
  end

  @doc """
  Records a timing sample for a stage.

  Updates sum, count, min, and max for the stage.
  The caller is responsible for sampling (e.g., only call for 1 in 100 packets).
  """
  def record_timing(mission_id, partition, stage, duration_us)
      when is_atom(stage) and is_integer(duration_us) do
    sum_slot = Map.get(@slots, :"latency_sum_#{stage}")
    count_slot = Map.get(@slots, :"latency_count_#{stage}")
    min_slot = Map.get(@minmax_slots, :"min_#{stage}")
    max_slot = Map.get(@minmax_slots, :"max_#{stage}")

    update_sum_and_count(mission_id, partition, sum_slot, count_slot, duration_us)
    update_min_and_max(mission_id, partition, min_slot, max_slot, duration_us)
  end

  defp update_sum_and_count(_mission_id, _partition, nil, _count_slot, _duration_us), do: :ok
  defp update_sum_and_count(_mission_id, _partition, _sum_slot, nil, _duration_us), do: :ok

  defp update_sum_and_count(mission_id, partition, sum_slot, count_slot, duration_us) do
    case get_counter_ref(mission_id, partition) do
      nil ->
        :ok

      ref ->
        :counters.add(ref, sum_slot, duration_us)
        :counters.add(ref, count_slot, 1)
    end
  end

  # Update min/max using atomics CAS
  defp update_min_and_max(_mission_id, _partition, nil, _max_slot, _duration_us), do: :ok
  defp update_min_and_max(_mission_id, _partition, _min_slot, nil, _duration_us), do: :ok

  defp update_min_and_max(mission_id, partition, min_slot, max_slot, duration_us) do
    case get_atomics_ref(mission_id, partition) do
      nil ->
        :ok

      ref ->
        update_min(ref, min_slot, duration_us)
        update_max(ref, max_slot, duration_us)
    end
  end

  # Atomically update min using compare-and-exchange loop
  defp update_min(ref, slot, value) do
    current = :atomics.get(ref, slot)

    if value < current do
      case :atomics.compare_exchange(ref, slot, current, value) do
        :ok -> :ok
        # CAS failed, another thread updated - retry
        _current_val -> update_min(ref, slot, value)
      end
    end
  end

  # Atomically update max using compare-and-exchange loop
  defp update_max(ref, slot, value) do
    current = :atomics.get(ref, slot)

    if value > current do
      case :atomics.compare_exchange(ref, slot, current, value) do
        :ok -> :ok
        # CAS failed, another thread updated - retry
        _current_val -> update_max(ref, slot, value)
      end
    end
  end

  @doc """
  Records a stage error.
  """
  def record_error(mission_id, partition, stage) when is_atom(stage) do
    error_slot = Map.get(@slots, :"errors_#{stage}")

    if error_slot do
      case get_counter_ref(mission_id, partition) do
        nil -> :ok
        ref -> :counters.add(ref, error_slot, 1)
      end
    end
  end

  @doc """
  Helper to time a function and record the timing.

  Returns the result of the function.
  """
  def time(mission_id, partition, stage, fun) when is_function(fun, 0) do
    start = System.monotonic_time(:microsecond)
    result = fun.()
    duration = System.monotonic_time(:microsecond) - start
    record_timing(mission_id, partition, stage, duration)
    result
  end

  @doc """
  Gets merged stats across all partitions for a mission.

  This is the cold path - called by the profiler, not the hot path.
  """
  def get_stats(mission_id) do
    ensure_table()

    partition_count = get_partition_count(mission_id)

    if partition_count == 0 do
      empty_stats()
    else
      merged = merge_all_partitions(mission_id, partition_count)
      minmax = merge_all_minmax(mission_id, partition_count)
      {duration_ms, duration_sec} = get_duration(mission_id)
      timing = build_timing_stats(merged, minmax)
      errors = build_error_stats(merged)
      bytes_received = Map.get(merged, :bytes_received, 0)

      build_stats_summary(
        merged,
        bytes_received,
        errors,
        timing,
        duration_ms,
        duration_sec,
        partition_count
      )
    end
  end

  @doc """
  Returns the partition count for a mission (lanes shard count).
  """
  def get_partition_count(mission_id) do
    case :ets.lookup(@table_name, {mission_id, :partition_count}) do
      [{{^mission_id, :partition_count}, count}] -> count
      _ -> 0
    end
  end

  @doc """
  Returns raw counters for a specific partition (shard).
  """
  def get_counters(mission_id, partition) do
    case get_counter_ref(mission_id, partition) do
      nil ->
        %{}

      ref ->
        Enum.reduce(@slots, %{}, fn {name, slot}, acc ->
          Map.put(acc, name, :counters.get(ref, slot))
        end)
    end
  end

  defp empty_stats do
    %{
      packets_received: 0,
      packets_processed: 0,
      items_processed: 0,
      packets_dropped: 0,
      bytes_received: 0,
      errors: %{},
      timing: %{},
      duration_ms: 0,
      packets_per_sec: 0.0,
      items_per_sec: 0.0,
      bytes_per_sec: 0.0
    }
  end

  defp get_duration(mission_id) do
    started_at = get_started_at(mission_id)
    duration_ms = System.monotonic_time(:millisecond) - started_at
    duration_sec = max(duration_ms / 1000, 0.001)
    {duration_ms, duration_sec}
  end

  defp build_timing_stats(merged, minmax) do
    Enum.reduce(@timing_stages, %{}, fn stage, acc ->
      sum_key = :"latency_sum_#{stage}"
      count_key = :"latency_count_#{stage}"
      min_key = :"min_#{stage}"
      max_key = :"max_#{stage}"

      sum = Map.get(merged, sum_key, 0)
      count = Map.get(merged, count_key, 0)
      min_val = Map.get(minmax, min_key, @min_sentinel)
      max_val = Map.get(minmax, max_key, 0)

      avg = if count > 0, do: Float.round(sum / count, 1), else: 0.0
      min_display = if min_val == @min_sentinel, do: 0, else: min_val

      Map.put(acc, stage, %{
        avg_us: avg,
        min_us: min_display,
        max_us: max_val,
        count: count
      })
    end)
  end

  defp build_error_stats(merged) do
    Enum.reduce(@error_stages, %{}, fn stage, acc ->
      error_key = :"errors_#{stage}"
      count = Map.get(merged, error_key, 0)
      Map.put(acc, stage, count)
    end)
  end

  defp build_stats_summary(
         merged,
         bytes_received,
         errors,
         timing,
         duration_ms,
         duration_sec,
         partition_count
       ) do
    packets_processed = Map.get(merged, :packets_processed, 0)
    items_processed = Map.get(merged, :items_processed, 0)

    %{
      packets_received: Map.get(merged, :packets_received, 0),
      packets_processed: packets_processed,
      items_processed: items_processed,
      packets_dropped: Map.get(merged, :packets_dropped, 0),
      bytes_received: bytes_received,
      errors: errors,
      timing: timing,
      duration_ms: duration_ms,
      duration_sec: duration_sec,
      packets_per_sec: Float.round(packets_processed / duration_sec, 1),
      items_per_sec: Float.round(items_processed / duration_sec, 1),
      bytes_per_sec: Float.round(bytes_received / duration_sec, 1),
      partition_count: partition_count
    }
  end

  @doc """
  Gets stats for a specific partition (for debugging).
  """
  def get_partition_stats(mission_id, partition) do
    case get_counter_ref(mission_id, partition) do
      nil ->
        nil

      ref ->
        Enum.reduce(@slots, %{}, fn {name, slot}, acc ->
          Map.put(acc, name, :counters.get(ref, slot))
        end)
    end
  end

  @doc """
  Resets all counters for a mission.
  """
  def reset(mission_id) do
    partition_count = get_partition_count(mission_id)

    for partition <- 0..(partition_count - 1) do
      reset_partition_counters(mission_id, partition)
      reset_partition_atomics(mission_id, partition)
    end

    # Reset start time
    :ets.insert(@table_name, {{mission_id, :started_at}, System.monotonic_time(:millisecond)})

    :ok
  end

  defp reset_partition_counters(mission_id, partition) do
    case get_counter_ref(mission_id, partition) do
      nil ->
        :ok

      ref ->
        for slot <- 1..@slot_count do
          current = :counters.get(ref, slot)
          :counters.sub(ref, slot, current)
        end
    end
  end

  # Reset atomics (min back to sentinel, max back to 0)
  defp reset_partition_atomics(mission_id, partition) do
    case get_atomics_ref(mission_id, partition) do
      nil ->
        :ok

      ref ->
        for stage <- @timing_stages do
          min_slot = Map.get(@minmax_slots, :"min_#{stage}")
          max_slot = Map.get(@minmax_slots, :"max_#{stage}")
          if min_slot, do: :atomics.put(ref, min_slot, @min_sentinel)
          if max_slot, do: :atomics.put(ref, max_slot, 0)
        end
    end
  end

  @doc """
  Cleans up metrics for a mission.
  """
  def cleanup(mission_id) do
    ensure_table()

    partition_count = get_partition_count(mission_id)

    for partition <- 0..(partition_count - 1) do
      :ets.delete(@table_name, {mission_id, :counters, partition})
      :ets.delete(@table_name, {mission_id, :atomics, partition})
    end

    :ets.delete(@table_name, {mission_id, :partition_count})
    :ets.delete(@table_name, {mission_id, :started_at})

    :ok
  end

  # Private helpers

  defp get_counter_ref(mission_id, partition) do
    key = {mission_id, :counters, partition}

    case :ets.lookup(@table_name, key) do
      [{^key, ref}] -> ref
      [] -> nil
    end
  end

  defp get_atomics_ref(mission_id, partition) do
    key = {mission_id, :atomics, partition}

    case :ets.lookup(@table_name, key) do
      [{^key, ref}] -> ref
      [] -> nil
    end
  end

  defp get_started_at(mission_id) do
    case :ets.lookup(@table_name, {mission_id, :started_at}) do
      [{_, time}] -> time
      [] -> System.monotonic_time(:millisecond)
    end
  end

  defp merge_all_partitions(mission_id, partition_count) do
    # Collect values from all partitions and sum them
    Enum.reduce(0..(partition_count - 1), %{}, fn partition, acc ->
      case get_counter_ref(mission_id, partition) do
        nil ->
          acc

        ref ->
          merge_partition_counters(ref, acc)
      end
    end)
  end

  defp merge_partition_counters(ref, acc) do
    Enum.reduce(@slots, acc, fn {name, slot}, inner_acc ->
      value = :counters.get(ref, slot)
      Map.update(inner_acc, name, value, &(&1 + value))
    end)
  end

  defp merge_all_minmax(mission_id, partition_count) do
    # Collect min/max values from all partitions
    # For min: take minimum across partitions
    # For max: take maximum across partitions
    Enum.reduce(0..(partition_count - 1), %{}, fn partition, acc ->
      merge_partition_minmax(mission_id, partition, acc)
    end)
  end

  defp merge_partition_minmax(mission_id, partition, acc) do
    case get_atomics_ref(mission_id, partition) do
      nil ->
        acc

      ref ->
        Enum.reduce(@minmax_slots, acc, fn {name, slot}, inner_acc ->
          update_minmax_slot(inner_acc, ref, name, slot)
        end)
    end
  end

  defp update_minmax_slot(acc, ref, name, slot) do
    value = :atomics.get(ref, slot)
    is_min = String.starts_with?(Atom.to_string(name), "min_")

    Map.update(acc, name, value, fn existing ->
      if is_min, do: min(existing, value), else: max(existing, value)
    end)
  end
end
