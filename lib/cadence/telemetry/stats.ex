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
    # Limits evaluation timing
    :limits,
    # End-to-end latency (packet arrival to CVT write)
    :end_to_end
  ]

  # Stages we track for percentile sampling
  # NOTE: Percentile sampling is expensive (reservoir sampling with ETS updates).
  # Only add stages here if percentile data is critical. Basic timing (avg/min/max)
  # is still tracked via @timing_stages without this overhead.
  @percentile_stages [:end_to_end]

  # Stages we track for per-stage errors
  @error_stages [:identify, :decom, :convert, :derive]

  # Maximum samples to keep for percentile calculation (reservoir sampling)
  @default_sample_limit 10_000

  # Warmup period - first N samples may be slow due to JIT, cache warmup, etc.
  @warmup_sample_count 10

  # Spike detection threshold (samples > this many standard deviations are "spikes")
  @spike_threshold_sigma 3.0

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

    # Initialize warmup samples storage: list of first N samples
    Enum.each(@percentile_stages, fn stage ->
      key = {mission_id, :warmup_samples, stage}
      :ets.insert(@table_name, {key, []})
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
    ensure_table()
    key = {mission_id, counter}

    case :ets.lookup(@table_name, key) do
      [{^key, _}] ->
        :ets.update_counter(@table_name, key, {2, amount})

      [] ->
        # Key doesn't exist - initialize mission stats first
        init(mission_id)
        :ets.update_counter(@table_name, key, {2, amount})
    end
  end

  @doc """
  Records a timing measurement for a pipeline stage.

  `duration_us` is the duration in microseconds.

  Also records samples for percentile-tracked stages (warmup/spike analysis).
  """
  def record_timing(mission_id, stage, duration_us) when is_integer(duration_us) do
    ensure_table()
    key = {mission_id, :timing, stage}

    case :ets.lookup(@table_name, key) do
      [{^key, {sum, count, min, max}}] ->
        new_min = if min == nil, do: duration_us, else: min(min, duration_us)
        new_max = if max == nil, do: duration_us, else: max(max, duration_us)
        :ets.insert(@table_name, {key, {sum + duration_us, count + 1, new_min, new_max}})

      [] ->
        :ets.insert(@table_name, {key, {duration_us, 1, duration_us, duration_us}})
    end

    # Also record sample for percentile/warmup/spike analysis
    if stage in @percentile_stages do
      record_timing_sample(mission_id, stage, duration_us)
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

  Also tracks the first N samples separately for warmup analysis.
  """
  def record_timing_sample(mission_id, stage, duration_us) when is_integer(duration_us) do
    ensure_table()
    key = {mission_id, :timing_samples, stage}

    case :ets.lookup(@table_name, key) do
      [{^key, {samples_map, sample_count, total_count}}] when is_map(samples_map) ->
        new_total = total_count + 1

        # Track warmup samples (first N)
        maybe_record_warmup_sample(mission_id, stage, duration_us, new_total)

        {new_samples, new_sample_count} =
          update_samples(samples_map, sample_count, new_total, duration_us)

        :ets.insert(@table_name, {key, {new_samples, new_sample_count, new_total}})

      # Handle legacy format or empty
      [{^key, {[], 0}}] ->
        record_first_sample(key, mission_id, stage, duration_us)

      [] ->
        record_first_sample(key, mission_id, stage, duration_us)
    end
  end

  defp update_samples(samples_map, sample_count, new_total, duration_us) do
    if sample_count < @default_sample_limit do
      {Map.put(samples_map, sample_count, duration_us), sample_count + 1}
    else
      maybe_replace_sample(samples_map, sample_count, new_total, duration_us)
    end
  end

  defp maybe_replace_sample(samples_map, sample_count, new_total, duration_us) do
    if :rand.uniform(new_total) <= @default_sample_limit do
      replace_idx = :rand.uniform(@default_sample_limit) - 1
      {Map.put(samples_map, replace_idx, duration_us), sample_count}
    else
      {samples_map, sample_count}
    end
  end

  defp record_first_sample(key, mission_id, stage, duration_us) do
    maybe_record_warmup_sample(mission_id, stage, duration_us, 1)
    :ets.insert(@table_name, {key, {%{0 => duration_us}, 1, 1}})
  end

  # Record warmup samples (first N) for analysis
  defp maybe_record_warmup_sample(mission_id, stage, duration_us, sample_number)
       when sample_number <= @warmup_sample_count do
    key = {mission_id, :warmup_samples, stage}

    case :ets.lookup(@table_name, key) do
      [{^key, samples}] when is_list(samples) and length(samples) < @warmup_sample_count ->
        :ets.insert(@table_name, {key, samples ++ [duration_us]})

      [] ->
        :ets.insert(@table_name, {key, [duration_us]})

      _ ->
        :ok
    end
  end

  defp maybe_record_warmup_sample(_mission_id, _stage, _duration_us, _sample_number), do: :ok

  @doc """
  Gets percentile timings for a specific stage.

  Returns `%{p50: value, p95: value, p99: value}` in microseconds,
  or `%{p50: 0, p95: 0, p99: 0}` if no samples exist.
  """
  def get_percentiles(mission_id, stage) do
    ensure_table()
    key = {mission_id, :timing_samples, stage}

    case :ets.lookup(@table_name, key) do
      [{^key, {samples_map, sample_count, _total_count}}]
      when is_map(samples_map) and sample_count > 0 ->
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
    index = round(percentile / 100 * (count - 1))
    index = max(0, min(index, count - 1))
    Enum.at(sorted, index, 0)
  end

  @doc """
  Gets detailed timing analysis for a stage, including warmup detection.

  Returns a map with:
  - `avg_us` - Standard average
  - `median_us` - Median value (P50)
  - `trimmed_avg_us` - Average excluding top/bottom 5% (robust to outliers)
  - `steady_state_avg_us` - Average excluding warmup samples
  - `spike_count` - Count of samples > 3σ from mean (likely GC pauses)
  - `warmup_samples` - First N samples (to visualize warmup effect)
  - `warmup_avg_us` - Average of warmup samples
  - `sample_count` - Total samples
  """
  def get_timing_analysis(mission_id, stage) do
    ensure_table()

    samples_key = {mission_id, :timing_samples, stage}
    warmup_key = {mission_id, :warmup_samples, stage}

    # Get all samples
    samples =
      case :ets.lookup(@table_name, samples_key) do
        [{^samples_key, {samples_map, _count, _total}}] when is_map(samples_map) ->
          Map.values(samples_map)

        [{^samples_key, {samples_list, _total}}] when is_list(samples_list) ->
          samples_list

        _ ->
          []
      end

    # Get warmup samples
    warmup_samples =
      case :ets.lookup(@table_name, warmup_key) do
        [{^warmup_key, ws}] when is_list(ws) -> ws
        _ -> []
      end

    if samples == [] do
      %{
        avg_us: 0,
        median_us: 0,
        trimmed_avg_us: 0,
        steady_state_avg_us: 0,
        spike_count: 0,
        warmup_samples: [],
        warmup_avg_us: 0,
        sample_count: 0
      }
    else
      sorted = Enum.sort(samples)
      count = length(sorted)

      # Standard average
      avg = Enum.sum(samples) / count

      # Median
      median = percentile_at(sorted, count, 50)

      # Trimmed mean (exclude top/bottom 5%)
      trimmed_avg = calculate_trimmed_mean(sorted, count, 0.05)

      # Spike detection (> 3σ from mean)
      {spike_count, std_dev} = count_spikes(samples, avg)

      # Warmup analysis
      warmup_avg =
        if length(warmup_samples) > 0 do
          Enum.sum(warmup_samples) / length(warmup_samples)
        else
          0
        end

      # Steady state average (excluding warmup period)
      # We use samples after the warmup count
      steady_state_avg =
        if count > @warmup_sample_count do
          # Since reservoir sampling doesn't preserve order, use trimmed mean as proxy
          # for steady-state behavior (removes outliers including early warmup spikes)
          trimmed_avg
        else
          avg
        end

      %{
        avg_us: Float.round(avg, 1),
        median_us: median,
        trimmed_avg_us: Float.round(trimmed_avg, 1),
        steady_state_avg_us: Float.round(steady_state_avg, 1),
        spike_count: spike_count,
        spike_threshold_us: Float.round(avg + @spike_threshold_sigma * std_dev, 1),
        warmup_samples: warmup_samples,
        warmup_avg_us: Float.round(warmup_avg, 1),
        sample_count: count,
        std_dev_us: Float.round(std_dev, 1)
      }
    end
  end

  @doc """
  Gets timing analysis for all percentile-tracked stages.
  """
  def get_all_timing_analysis(mission_id) do
    Enum.reduce(@percentile_stages, %{}, fn stage, acc ->
      Map.put(acc, stage, get_timing_analysis(mission_id, stage))
    end)
  end

  # Calculate trimmed mean (exclude top/bottom trim_percent of samples)
  defp calculate_trimmed_mean(sorted, count, trim_percent) do
    trim_count = round(count * trim_percent)

    if count - 2 * trim_count > 0 do
      trimmed = sorted |> Enum.drop(trim_count) |> Enum.take(count - 2 * trim_count)
      Enum.sum(trimmed) / length(trimmed)
    else
      Enum.sum(sorted) / count
    end
  end

  # Count samples that are > threshold sigma from mean (likely GC pauses)
  defp count_spikes(samples, avg) do
    count = length(samples)

    if count < 2 do
      {0, 0.0}
    else
      # Calculate standard deviation
      variance = Enum.reduce(samples, 0, fn x, acc -> acc + (x - avg) * (x - avg) end) / count
      std_dev = :math.sqrt(variance)

      threshold = avg + @spike_threshold_sigma * std_dev
      spike_count = Enum.count(samples, fn x -> x > threshold end)

      {spike_count, std_dev}
    end
  end

  @doc """
  Increments the error counter for a specific pipeline stage.

  Also increments the aggregate :stage_errors counter for backward compatibility.
  """
  def increment_stage_error(mission_id, stage) when stage in @error_stages do
    # Increment aggregate counter for backward compatibility
    increment(mission_id, :stage_errors)

    # Increment per-stage counter
    ensure_table()
    key = {mission_id, :stage_error, stage}

    case :ets.lookup(@table_name, key) do
      [{^key, _}] ->
        :ets.update_counter(@table_name, key, {2, 1})

      [] ->
        init(mission_id)
        :ets.update_counter(@table_name, key, {2, 1})
    end
  end

  def increment_stage_error(mission_id, _stage) do
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
        if(duration_ms > 0,
          do: Float.round(stats.packets_processed / (duration_ms / 1000), 1),
          else: 0.0
        ),
      items_per_sec:
        if(duration_ms > 0,
          do: Float.round(stats.items_processed / (duration_ms / 1000), 1),
          else: 0.0
        ),
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
    ensure_table()

    # Reset counters
    Enum.each(@counters, fn counter ->
      safe_ets_insert({mission_id, counter}, 0)
    end)

    # Reset timing stats
    Enum.each(@timing_stages, fn stage ->
      safe_ets_insert({mission_id, :timing, stage}, {0, 0, nil, nil})
    end)

    # Reset timing samples
    Enum.each(@percentile_stages, fn stage ->
      safe_ets_insert({mission_id, :timing_samples, stage}, {%{}, 0, 0})
    end)

    # Reset warmup samples
    Enum.each(@percentile_stages, fn stage ->
      safe_ets_insert({mission_id, :warmup_samples, stage}, [])
    end)

    # Reset per-stage error counters
    Enum.each(@error_stages, fn stage ->
      safe_ets_insert({mission_id, :stage_error, stage}, 0)
    end)

    safe_ets_insert({mission_id, :started_at}, System.monotonic_time(:millisecond))
    :ok
  end

  @doc """
  Cleans up stats for a mission.
  """
  def cleanup(mission_id) do
    ensure_table()

    # Clean up counters
    Enum.each(@counters ++ [:started_at], fn counter ->
      safe_ets_delete({mission_id, counter})
    end)

    # Clean up timing stats
    Enum.each(@timing_stages, fn stage ->
      safe_ets_delete({mission_id, :timing, stage})
    end)

    # Clean up timing samples
    Enum.each(@percentile_stages, fn stage ->
      safe_ets_delete({mission_id, :timing_samples, stage})
    end)

    # Clean up warmup samples
    Enum.each(@percentile_stages, fn stage ->
      safe_ets_delete({mission_id, :warmup_samples, stage})
    end)

    # Clean up per-stage error counters
    Enum.each(@error_stages, fn stage ->
      safe_ets_delete({mission_id, :stage_error, stage})
    end)

    :ok
  end

  # Private helpers for safe ETS operations without try/rescue

  defp safe_ets_insert(key, value) do
    :ets.insert(@table_name, {key, value})
    :ok
  end

  defp safe_ets_delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end
end
