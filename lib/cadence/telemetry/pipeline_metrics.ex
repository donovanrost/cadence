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

  alias Cadence.ETS, as: CadenceETS
  alias Cadence.Time, as: CadenceTime

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
    errors_identify_missing_catalog: 27,
    errors_identify_unknown_packet: 28,

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
    latency_sum_parse: 39,
    latency_count_parse: 40,
    latency_sum_resolve: 41,
    latency_count_resolve: 42,
    latency_sum_log_append: 43,
    latency_count_log_append: 44,
    latency_sum_sdlp_decode: 45,
    latency_count_sdlp_decode: 46,
    latency_sum_sdlp_reassembly: 47,
    latency_count_sdlp_reassembly: 48,
    latency_sum_envelope_build: 49,
    latency_count_envelope_build: 50,

    # Bitrate tracking
    bytes_received: 26,

    # V2 pipeline counters
    packets_parsed_ok: 29,
    packets_malformed: 30,
    packets_resolved_ok: 31,
    packets_unresolved: 32,
    packets_ambiguous: 33,
    packets_schema_ok: 34,
    packets_unknown_apid: 35,
    packets_uncataloged_target: 36,
    packets_unsupported_format: 37,
    packets_decom_processed: 38,
    envelopes_emitted: 51
  }

  @slot_count 51

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
    max_end_to_end: 16,
    min_parse: 17,
    max_parse: 18,
    min_resolve: 19,
    max_resolve: 20,
    min_log_append: 21,
    max_log_append: 22,
    min_sdlp_decode: 23,
    max_sdlp_decode: 24,
    min_sdlp_reassembly: 25,
    max_sdlp_reassembly: 26,
    min_envelope_build: 27,
    max_envelope_build: 28
  }

  @minmax_slot_count 28

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
    :parse,
    :resolve,
    :log_append,
    :end_to_end,
    :sdlp_decode,
    :sdlp_reassembly,
    :envelope_build
  ]

  @histogram_stages [:parse, :resolve, :decom, :log_append, :end_to_end]
  @histogram_bucket_count 32

  @histogram_stage_offsets Enum.into(Enum.with_index(@histogram_stages), %{}, fn {stage, idx} ->
                             {stage, idx * @histogram_bucket_count + 1}
                           end)

  @histogram_slot_count map_size(@histogram_stage_offsets) * @histogram_bucket_count

  # Error stages we track
  @error_stages [
    :identify,
    :decom,
    :convert,
    :derive,
    :batcher,
    :identify_missing_catalog,
    :identify_unknown_packet
  ]

  @doc """
  Ensures the metrics ETS table exists.
  """
  def ensure_table do
    CadenceETS.ensure_named_table(@table_name, [
      :set,
      :named_table,
      :public,
      write_concurrency: true,
      read_concurrency: true
    ])
  end

  @doc """
  Returns the partition key for pre-lanes ingress metrics.
  """
  def ingress_partition, do: {:ingress, 0}

  @doc """
  Initializes metrics for a mission with the given partition count.

  Creates a :counters reference for each partition and stores them in ETS.
  Also creates :atomics for min/max tracking.
  Also stores metadata like partition_count and start_time.
  """
  def init(mission_id, partition_count) do
    partitions =
      if partition_count > 0 do
        Enum.to_list(0..(partition_count - 1))
      else
        []
      end

    init_partitions(mission_id, partitions)
  end

  @doc """
  Initializes metrics for a mission with lane/shard partitions.
  """
  def init_lanes(mission_id, lanes) when is_list(lanes) do
    partitions =
      [ingress_partition()] ++
        (lanes
         |> Enum.flat_map(fn lane ->
           Enum.map(0..(lane.shard_count - 1), fn shard_id ->
             {lane.name, shard_id}
           end)
         end))

    init_partitions(mission_id, partitions)
    :ets.insert(@table_name, {{mission_id, :lane_shards}, lane_shard_map(lanes)})
    :ok
  end

  defp init_partitions(mission_id, partitions) do
    ensure_table()

    # Create counter and atomics references for each partition
    for partition <- partitions do
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

      if @histogram_slot_count > 0 do
        histogram_ref = :atomics.new(@histogram_slot_count, [])
        :ets.insert(@table_name, {{mission_id, :histogram, partition}, histogram_ref})
      end
    end

    # Store metadata
    :ets.insert(@table_name, {{mission_id, :partition_keys}, partitions})
    :ets.insert(@table_name, {{mission_id, :partition_count}, length(partitions)})
    :ets.insert(@table_name, {{mission_id, :started_at}, CadenceTime.monotonic(:millisecond)})

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
    update_histogram(mission_id, partition, stage, duration_us)
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

  defp update_histogram(_mission_id, _partition, stage, _duration_us)
       when not is_map_key(@histogram_stage_offsets, stage),
       do: :ok

  defp update_histogram(mission_id, partition, stage, duration_us) do
    case get_histogram_ref(mission_id, partition) do
      nil ->
        :ok

      ref ->
        bucket_index = histogram_bucket_index(duration_us)
        slot = histogram_slot(stage, bucket_index)
        :atomics.add(ref, slot, 1)
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
    start = CadenceTime.monotonic(:microsecond)
    result = fun.()
    duration = CadenceTime.monotonic(:microsecond) - start
    record_timing(mission_id, partition, stage, duration)
    result
  end

  @doc """
  Gets merged stats across all partitions for a mission.

  This is the cold path - called by the profiler, not the hot path.
  """
  def get_stats(mission_id) do
    ensure_table()

    partition_keys = get_partition_keys(mission_id)
    partition_count = length(partition_keys)

    if partition_count == 0 do
      empty_stats()
    else
      merged = merge_all_partitions(mission_id, partition_keys)
      minmax = merge_all_minmax(mission_id, partition_keys)
      {duration_ms, duration_sec} = get_duration(mission_id)
      histograms = merge_all_histograms(mission_id, partition_keys)
      timing_percentiles = build_timing_percentiles(histograms)
      timing = build_timing_stats(merged, minmax)
      errors = build_error_stats(merged)
      bytes_received = Map.get(merged, :bytes_received, 0)

      summary =
        build_stats_summary(
          merged,
          bytes_received,
          errors,
          timing,
          duration_ms,
          duration_sec,
          partition_count
        )

      summary
      |> Map.put(:timing_percentiles, timing_percentiles)
      |> Map.merge(build_rolling_stats(mission_id, summary))
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
  rescue
    ArgumentError -> 0
  end

  @doc """
  Returns the partition count for a specific lane.
  """
  def get_partition_count(mission_id, lane) do
    case :ets.lookup(@table_name, {mission_id, :lane_shards}) do
      [{{^mission_id, :lane_shards}, lane_map}] ->
        Map.get(lane_map, lane, 0)

      _ ->
        get_partition_count(mission_id)
    end
  rescue
    ArgumentError -> 0
  end

  @doc """
  Returns the partition keys for a mission.
  """
  def get_partition_keys(mission_id) do
    case :ets.lookup(@table_name, {mission_id, :partition_keys}) do
      [{{^mission_id, :partition_keys}, keys}] -> keys
      _ -> []
    end
  rescue
    ArgumentError -> []
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

  @doc """
  Sets a gauge value for a partition.
  """
  def set_gauge(mission_id, partition, gauge, value) when is_integer(value) do
    ensure_table()
    :ets.insert(@table_name, {{mission_id, :gauge, partition, gauge}, value})
    :ok
  end

  @doc """
  Returns all gauges for a partition.
  """
  def get_gauges(mission_id, partition) do
    ensure_table()

    match =
      :ets.match_object(
        @table_name,
        {{mission_id, :gauge, partition, :"$1"}, :"$2"}
      )

    Enum.reduce(match, %{}, fn {{^mission_id, :gauge, ^partition, gauge}, value}, acc ->
      Map.put(acc, gauge, value)
    end)
  end

  @doc """
  Returns counters and timing stats for a specific partition.
  """
  def get_partition_stats(mission_id, partition) do
    counters = get_counters(mission_id, partition)
    minmax = get_partition_minmax(mission_id, partition)
    histograms = get_partition_histograms(mission_id, partition)

    %{
      counters: counters,
      timing: build_timing_stats(counters, minmax),
      timing_percentiles: build_timing_percentiles(histograms)
    }
  rescue
    ArgumentError ->
      %{counters: %{}, timing: %{}, timing_percentiles: %{}}
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
      timing_percentiles: %{},
      duration_ms: 0,
      packets_per_sec: 0.0,
      items_per_sec: 0.0,
      bytes_per_sec: 0.0
    }
  end

  defp get_duration(mission_id) do
    started_at = get_started_at(mission_id)
    duration_ms = CadenceTime.monotonic(:millisecond) - started_at
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

  defp build_timing_percentiles(histograms) do
    Enum.reduce(@histogram_stages, %{}, fn stage, acc ->
      counts = Map.get(histograms, stage, [])

      percentiles =
        if Enum.sum(counts) > 0 do
          %{
            p50: histogram_percentile(counts, 0.50),
            p95: histogram_percentile(counts, 0.95),
            p99: histogram_percentile(counts, 0.99)
          }
        else
          %{p50: 0, p95: 0, p99: 0}
        end

      Map.put(acc, stage, percentiles)
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

  defp build_rolling_stats(mission_id, summary) do
    now_ms = CadenceTime.monotonic(:millisecond)

    {packets_processed, items_processed, bytes_received} =
      {summary.packets_processed, summary.items_processed, summary.bytes_received}

    rolling_key = {mission_id, :rolling_snapshot}

    rolling =
      case :ets.lookup(@table_name, rolling_key) do
        [{{^mission_id, :rolling_snapshot}, %{timestamp_ms: prev_ms} = prev}] ->
          duration_ms = max(now_ms - prev_ms, 0)
          duration_sec = max(duration_ms / 1000, 0.001)

          packets_diff = packets_processed - Map.get(prev, :packets_processed, 0)
          items_diff = items_processed - Map.get(prev, :items_processed, 0)
          bytes_diff = bytes_received - Map.get(prev, :bytes_received, 0)

          %{
            packets_per_sec_rolling: Float.round(packets_diff / duration_sec, 1),
            items_per_sec_rolling: Float.round(items_diff / duration_sec, 1),
            bytes_per_sec_rolling: Float.round(bytes_diff / duration_sec, 1),
            rolling_duration_ms: duration_ms
          }

        _ ->
          %{
            packets_per_sec_rolling: 0.0,
            items_per_sec_rolling: 0.0,
            bytes_per_sec_rolling: 0.0,
            rolling_duration_ms: 0
          }
      end

    :ets.insert(@table_name, {
      rolling_key,
      %{
        timestamp_ms: now_ms,
        packets_processed: packets_processed,
        items_processed: items_processed,
        bytes_received: bytes_received
      }
    })

    rolling
  end

  @doc """
  Resets all counters for a mission.
  """
  def reset(mission_id) do
    partition_keys = get_partition_keys(mission_id)

    for partition <- partition_keys do
      reset_partition_counters(mission_id, partition)
      reset_partition_atomics(mission_id, partition)
      reset_partition_histogram(mission_id, partition)
    end

    delete_gauges(mission_id)

    # Reset start time
    :ets.insert(@table_name, {{mission_id, :started_at}, CadenceTime.monotonic(:millisecond)})

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

  defp reset_partition_histogram(mission_id, partition) do
    if @histogram_slot_count > 0 do
      case get_histogram_ref(mission_id, partition) do
        nil ->
          :ok

        ref ->
          for slot <- 1..@histogram_slot_count do
            :atomics.put(ref, slot, 0)
          end
      end
    end
  end

  @doc """
  Cleans up metrics for a mission.
  """
  def cleanup(mission_id) do
    ensure_table()

    partition_keys = get_partition_keys(mission_id)

    for partition <- partition_keys do
      :ets.delete(@table_name, {mission_id, :counters, partition})
      :ets.delete(@table_name, {mission_id, :atomics, partition})
      :ets.delete(@table_name, {mission_id, :histogram, partition})
    end

    delete_gauges(mission_id)

    :ets.delete(@table_name, {mission_id, :partition_count})
    :ets.delete(@table_name, {mission_id, :partition_keys})
    :ets.delete(@table_name, {mission_id, :lane_shards})
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
  rescue
    ArgumentError -> nil
  end

  defp get_atomics_ref(mission_id, partition) do
    key = {mission_id, :atomics, partition}

    case :ets.lookup(@table_name, key) do
      [{^key, ref}] -> ref
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp get_partition_minmax(mission_id, partition) do
    case get_atomics_ref(mission_id, partition) do
      nil ->
        %{}

      ref ->
        Enum.reduce(@minmax_slots, %{}, fn {name, slot}, acc ->
          Map.put(acc, name, :atomics.get(ref, slot))
        end)
    end
  end

  defp get_partition_histograms(mission_id, partition) do
    case get_histogram_ref(mission_id, partition) do
      nil ->
        %{}

      ref ->
        Enum.reduce(@histogram_stages, %{}, fn stage, acc ->
          Map.put(acc, stage, histogram_counts(ref, stage))
        end)
    end
  end

  defp get_histogram_ref(mission_id, partition) do
    key = {mission_id, :histogram, partition}

    case :ets.lookup(@table_name, key) do
      [{^key, ref}] -> ref
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp get_started_at(mission_id) do
    case :ets.lookup(@table_name, {mission_id, :started_at}) do
      [{_, time}] -> time
      [] -> CadenceTime.monotonic(:millisecond)
    end
  end

  defp merge_all_partitions(mission_id, partition_keys) do
    # Collect values from all partitions and sum them
    Enum.reduce(partition_keys, %{}, fn partition, acc ->
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

  defp merge_all_minmax(mission_id, partition_keys) do
    # Collect min/max values from all partitions
    # For min: take minimum across partitions
    # For max: take maximum across partitions
    Enum.reduce(partition_keys, %{}, fn partition, acc ->
      merge_partition_minmax(mission_id, partition, acc)
    end)
  end

  defp merge_all_histograms(mission_id, partition_keys) do
    Enum.reduce(partition_keys, %{}, fn partition, acc ->
      merge_partition_histograms(mission_id, partition, acc)
    end)
  end

  defp merge_partition_histograms(mission_id, partition, acc) do
    case get_histogram_ref(mission_id, partition) do
      nil ->
        acc

      ref ->
        Enum.reduce(@histogram_stages, acc, fn stage, acc ->
          merge_stage_histogram(ref, stage, acc)
        end)
    end
  end

  defp merge_stage_histogram(ref, stage, acc) do
    counts = histogram_counts(ref, stage)

    Map.update(acc, stage, counts, fn existing ->
      sum_histogram_counts(existing, counts)
    end)
  end

  defp histogram_counts(ref, stage) do
    start_slot = Map.get(@histogram_stage_offsets, stage)

    if start_slot do
      for offset <- 0..(@histogram_bucket_count - 1) do
        :atomics.get(ref, start_slot + offset)
      end
    else
      []
    end
  end

  defp sum_histogram_counts(existing, counts) do
    Enum.zip_with(existing, counts, &(&1 + &2))
  end

  defp histogram_slot(stage, bucket_index) do
    start_slot = Map.fetch!(@histogram_stage_offsets, stage)
    start_slot + bucket_index
  end

  defp histogram_bucket_index(duration_us) when duration_us <= 1, do: 0

  defp histogram_bucket_index(duration_us) do
    bucket = trunc(:math.log2(duration_us))
    max(bucket, 0) |> min(@histogram_bucket_count - 1)
  end

  defp histogram_percentile(counts, percentile) when is_list(counts) do
    total = Enum.sum(counts)

    if total == 0 do
      0
    else
      target = ceil(total * percentile)
      bucket = histogram_bucket_for_target(counts, target, 0, 0)
      histogram_bucket_upper_us(bucket)
    end
  end

  defp histogram_bucket_for_target([], _target, idx, _acc), do: idx

  defp histogram_bucket_for_target([count | rest], target, idx, acc) do
    if acc + count >= target do
      idx
    else
      histogram_bucket_for_target(rest, target, idx + 1, acc + count)
    end
  end

  defp histogram_bucket_upper_us(bucket_index) do
    :erlang.trunc(:math.pow(2, bucket_index + 1))
  end

  defp delete_gauges(mission_id) do
    ensure_table()

    :ets.select_delete(@table_name, [
      {{{mission_id, :gauge, :_, :_}, :_}, [], [true]}
    ])
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

  defp lane_shard_map(lanes) do
    Enum.reduce(lanes, %{}, fn lane, acc ->
      Map.put(acc, lane.name, lane.shard_count)
    end)
  end
end
