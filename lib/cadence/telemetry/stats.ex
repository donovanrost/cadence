defmodule Cadence.Telemetry.Stats do
  @moduledoc """
  ETS-based statistics tracker for telemetry pipeline performance.

  Provides atomic counters that can be updated from any process (Broadway, GenServer, etc.)
  without requiring GenServer calls.

  ## Usage

      # Initialize stats for a mission (called by MissionInstance)
      Cadence.Telemetry.Stats.init(mission_id)

      # Increment counters (called from pipeline)
      Cadence.Telemetry.Stats.increment(mission_id, :packets_received)
      Cadence.Telemetry.Stats.increment(mission_id, :packets_processed, 5)

      # Get current stats
      Cadence.Telemetry.Stats.get(mission_id)

      # Reset stats
      Cadence.Telemetry.Stats.reset(mission_id)
  """

  @table_name :cadence_telemetry_stats

  @counters [
    :packets_received,
    :packets_processed,
    :packets_failed,
    :items_processed,
    :cvt_writes,
    :pubsub_broadcasts,
    # V2 pipeline counters
    :stage_errors,
    :packets_dropped
  ]

  # Timing stages we track (in microseconds)
  @timing_stages [
    # V1 Broadway pipeline stages
    :identify,
    :decommutate,
    :convert,
    :derive,
    :cvt_batch,
    :total_process,
    # Granular CVT timing
    :ets_write,
    :pubsub_broadcast,
    # V2 GenStage pipeline stages (shorter names)
    :decom,
    # End-to-end latency (packet arrival to CVT write)
    :end_to_end
  ]

  # Stages we track for percentile sampling
  @percentile_stages [:identify, :decom, :decommutate, :convert, :derive, :cvt_batch, :end_to_end]

  # Stages we track for per-stage errors
  @error_stages [:identify, :decom, :convert, :derive]

  # Maximum samples to keep for percentile calculation (reservoir sampling)
  @default_sample_limit 10_000

  @doc """
  Ensures the stats ETS table exists. Safe to call multiple times.
  """
  def ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set,
          :named_table,
          :public,
          write_concurrency: true,
          read_concurrency: true
        ])

      _ref ->
        :ok
    end
  end

  @doc """
  Initializes stats for a mission.
  """
  def init(mission_id) do
    ensure_table()

    Enum.each(@counters, fn counter ->
      key = {mission_id, counter}
      :ets.insert(@table_name, {key, 0})
    end)

    # Initialize timing stats: {sum_microseconds, count, min, max}
    Enum.each(@timing_stages, fn stage ->
      key = {mission_id, :timing, stage}
      :ets.insert(@table_name, {key, {0, 0, nil, nil}})
    end)

    # Initialize timing samples for percentile calculation: {samples_map, sample_count, total_seen_count}
    Enum.each(@percentile_stages, fn stage ->
      key = {mission_id, :timing_samples, stage}
      :ets.insert(@table_name, {key, {%{}, 0, 0}})
    end)

    # Initialize per-stage error counters
    Enum.each(@error_stages, fn stage ->
      key = {mission_id, :stage_error, stage}
      :ets.insert(@table_name, {key, 0})
    end)

    # Store start time
    :ets.insert(@table_name, {{mission_id, :started_at}, System.monotonic_time(:millisecond)})

    :ok
  end

  @doc """
  Increments a counter for a mission.
  """
  def increment(mission_id, counter, amount \\ 1) do
    key = {mission_id, counter}

    try do
      :ets.update_counter(@table_name, key, {2, amount})
    rescue
      ArgumentError ->
        # Table or key doesn't exist, initialize and retry
        init(mission_id)
        :ets.update_counter(@table_name, key, {2, amount})
    end
  end

  @doc """
  Records a timing measurement for a pipeline stage.

  `duration_us` is the duration in microseconds.
  """
  def record_timing(mission_id, stage, duration_us) when is_integer(duration_us) do
    key = {mission_id, :timing, stage}

    try do
      case :ets.lookup(@table_name, key) do
        [{^key, {sum, count, min, max}}] ->
          new_min = if min == nil, do: duration_us, else: min(min, duration_us)
          new_max = if max == nil, do: duration_us, else: max(max, duration_us)
          :ets.insert(@table_name, {key, {sum + duration_us, count + 1, new_min, new_max}})

        [] ->
          :ets.insert(@table_name, {key, {duration_us, 1, duration_us, duration_us}})
      end
    rescue
      _ ->
        init(mission_id)
        :ets.insert(@table_name, {key, {duration_us, 1, duration_us, duration_us}})
    end
  end

  @doc """
  Helper macro/function to time a block of code and record it.
  Returns the result of the block.
  """
  def time(mission_id, stage, fun) when is_function(fun, 0) do
    start = System.monotonic_time(:microsecond)
    result = fun.()
    duration = System.monotonic_time(:microsecond) - start
    record_timing(mission_id, stage, duration)
    result
  end

  @doc """
  Records a timing sample for percentile calculation.

  Uses reservoir sampling to maintain bounded memory. When the sample limit
  is reached, randomly replaces existing samples to maintain statistical
  representativeness.

  Samples are stored as a map with integer indices for O(1) random access.
  Format: {%{0 => sample, 1 => sample, ...}, sample_count, total_seen_count}
  """
  def record_timing_sample(mission_id, stage, duration_us) when is_integer(duration_us) do
    key = {mission_id, :timing_samples, stage}

    try do
      case :ets.lookup(@table_name, key) do
        [{^key, {samples_map, sample_count, total_count}}] ->
          new_total = total_count + 1

          {new_samples, new_sample_count} =
            if sample_count < @default_sample_limit do
              # Under limit: add at next index
              {Map.put(samples_map, sample_count, duration_us), sample_count + 1}
            else
              # At limit: reservoir sampling - randomly decide whether to include
              # Probability of inclusion: sample_limit / total_count
              if :rand.uniform(new_total) <= @default_sample_limit do
                # Replace a random existing sample (O(1) map update)
                replace_idx = :rand.uniform(@default_sample_limit) - 1
                {Map.put(samples_map, replace_idx, duration_us), sample_count}
              else
                {samples_map, sample_count}
              end
            end

          :ets.insert(@table_name, {key, {new_samples, new_sample_count, new_total}})

        # Handle legacy format or empty
        [{^key, {[], 0}}] ->
          :ets.insert(@table_name, {key, {%{0 => duration_us}, 1, 1}})

        [] ->
          :ets.insert(@table_name, {key, {%{0 => duration_us}, 1, 1}})
      end
    rescue
      _ ->
        init(mission_id)
        :ets.insert(@table_name, {key, {%{0 => duration_us}, 1, 1}})
    end
  end

  @doc """
  Gets percentile timings for a specific stage.

  Returns `%{p50: value, p95: value, p99: value}` in microseconds,
  or `%{p50: 0, p95: 0, p99: 0}` if no samples exist.
  """
  def get_percentiles(mission_id, stage) do
    ensure_table()
    key = {mission_id, :timing_samples, stage}

    case :ets.lookup(@table_name, key) do
      [{^key, {samples_map, sample_count, _total_count}}] when is_map(samples_map) and sample_count > 0 ->
        # Convert map values to sorted list for percentile calculation
        sorted = samples_map |> Map.values() |> Enum.sort()
        count = length(sorted)

        %{
          p50: percentile_at(sorted, count, 50),
          p95: percentile_at(sorted, count, 95),
          p99: percentile_at(sorted, count, 99)
        }

      # Handle legacy list format
      [{^key, {samples, _total_count}}] when is_list(samples) and length(samples) > 0 ->
        sorted = Enum.sort(samples)
        count = length(sorted)

        %{
          p50: percentile_at(sorted, count, 50),
          p95: percentile_at(sorted, count, 95),
          p99: percentile_at(sorted, count, 99)
        }

      _ ->
        %{p50: 0, p95: 0, p99: 0}
    end
  end

  @doc """
  Gets percentiles for all tracked stages.

  Returns a map of stage => %{p50: value, p95: value, p99: value}.
  """
  def get_all_percentiles(mission_id) do
    ensure_table()

    Enum.reduce(@percentile_stages, %{}, fn stage, acc ->
      Map.put(acc, stage, get_percentiles(mission_id, stage))
    end)
  end

  # Calculate percentile value from sorted list
  defp percentile_at(sorted, count, percentile) do
    index = round((percentile / 100) * (count - 1))
    index = max(0, min(index, count - 1))
    Enum.at(sorted, index, 0)
  end

  @doc """
  Increments the error counter for a specific pipeline stage.

  Also increments the aggregate :stage_errors counter for backward compatibility.
  """
  def increment_stage_error(mission_id, stage) when stage in @error_stages do
    # Increment aggregate counter for backward compatibility
    increment(mission_id, :stage_errors)

    # Increment per-stage counter
    key = {mission_id, :stage_error, stage}

    try do
      :ets.update_counter(@table_name, key, {2, 1})
    rescue
      ArgumentError ->
        init(mission_id)
        :ets.update_counter(@table_name, key, {2, 1})
    end
  end

  def increment_stage_error(mission_id, stage) do
    # Unknown stage - just increment aggregate counter
    increment(mission_id, :stage_errors)
  end

  @doc """
  Gets per-stage error counts.

  Returns a map of stage => error_count.
  """
  def get_stage_errors(mission_id) do
    ensure_table()

    Enum.reduce(@error_stages, %{}, fn stage, acc ->
      key = {mission_id, :stage_error, stage}

      count =
        case :ets.lookup(@table_name, key) do
          [{^key, c}] -> c
          [] -> 0
        end

      Map.put(acc, stage, count)
    end)
  end

  @doc """
  Gets all stats for a mission.
  """
  def get(mission_id) do
    ensure_table()

    stats =
      Enum.reduce(@counters, %{}, fn counter, acc ->
        key = {mission_id, counter}

        value =
          case :ets.lookup(@table_name, key) do
            [{^key, v}] -> v
            [] -> 0
          end

        Map.put(acc, counter, value)
      end)

    # Add duration
    started_at =
      case :ets.lookup(@table_name, {mission_id, :started_at}) do
        [{_, t}] -> t
        [] -> System.monotonic_time(:millisecond)
      end

    duration_ms = System.monotonic_time(:millisecond) - started_at

    # Add timing stats
    timing = get_timing(mission_id)

    Map.merge(stats, %{
      duration_ms: duration_ms,
      duration_sec: duration_ms / 1000,
      packets_per_sec:
        if(duration_ms > 0, do: Float.round(stats.packets_processed / (duration_ms / 1000), 1), else: 0.0),
      items_per_sec:
        if(duration_ms > 0, do: Float.round(stats.items_processed / (duration_ms / 1000), 1), else: 0.0),
      timing: timing
    })
  end

  @doc """
  Gets timing statistics for all stages.
  Returns a map with avg/min/max in microseconds for each stage.
  """
  def get_timing(mission_id) do
    ensure_table()

    Enum.reduce(@timing_stages, %{}, fn stage, acc ->
      key = {mission_id, :timing, stage}

      case :ets.lookup(@table_name, key) do
        [{^key, {sum, count, min, max}}] when count > 0 ->
          avg = Float.round(sum / count, 1)
          Map.put(acc, stage, %{avg_us: avg, min_us: min, max_us: max, count: count})

        _ ->
          Map.put(acc, stage, %{avg_us: 0, min_us: 0, max_us: 0, count: 0})
      end
    end)
  end

  @doc """
  Resets stats for a mission.
  """
  def reset(mission_id) do
    Enum.each(@counters, fn counter ->
      key = {mission_id, counter}

      try do
        :ets.insert(@table_name, {key, 0})
      rescue
        _ -> :ok
      end
    end)

    # Reset timing stats
    Enum.each(@timing_stages, fn stage ->
      key = {mission_id, :timing, stage}

      try do
        :ets.insert(@table_name, {key, {0, 0, nil, nil}})
      rescue
        _ -> :ok
      end
    end)

    # Reset timing samples
    Enum.each(@percentile_stages, fn stage ->
      key = {mission_id, :timing_samples, stage}

      try do
        :ets.insert(@table_name, {key, {%{}, 0, 0}})
      rescue
        _ -> :ok
      end
    end)

    # Reset per-stage error counters
    Enum.each(@error_stages, fn stage ->
      key = {mission_id, :stage_error, stage}

      try do
        :ets.insert(@table_name, {key, 0})
      rescue
        _ -> :ok
      end
    end)

    :ets.insert(@table_name, {{mission_id, :started_at}, System.monotonic_time(:millisecond)})
    :ok
  end

  @doc """
  Cleans up stats for a mission.
  """
  def cleanup(mission_id) do
    ensure_table()

    # Clean up counters
    Enum.each(@counters ++ [:started_at], fn counter ->
      key = {mission_id, counter}

      try do
        :ets.delete(@table_name, key)
      rescue
        _ -> :ok
      end
    end)

    # Clean up timing stats
    Enum.each(@timing_stages, fn stage ->
      key = {mission_id, :timing, stage}

      try do
        :ets.delete(@table_name, key)
      rescue
        _ -> :ok
      end
    end)

    # Clean up timing samples
    Enum.each(@percentile_stages, fn stage ->
      key = {mission_id, :timing_samples, stage}

      try do
        :ets.delete(@table_name, key)
      rescue
        _ -> :ok
      end
    end)

    # Clean up per-stage error counters
    Enum.each(@error_stages, fn stage ->
      key = {mission_id, :stage_error, stage}

      try do
        :ets.delete(@table_name, key)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end
end
