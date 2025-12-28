defmodule Cadence.Simulator.SimulatorMetrics do
  @moduledoc """
  High-performance metrics for the simulator using Erlang :counters.

  Provides lock-free, atomic metric updates for tracking simulator throughput
  and timing. Uses the same pattern as `Cadence.Telemetry.PipelineMetrics`.

  ## Why :counters?

  - Atomic increment: single operation vs lookup + insert
  - Lock-free: no contention between workers
  - ~10x faster than ETS: ~20ns vs ~200ns per operation

  ## Usage

      # Initialize metrics for a coordinator
      SimulatorMetrics.init(coordinator_id)

      # Hot path - increment counters
      SimulatorMetrics.inc(coordinator_id, :packets_generated)
      SimulatorMetrics.inc(coordinator_id, :bytes_sent, 1024)

      # Record timing (sampled)
      SimulatorMetrics.record_timing(coordinator_id, :generation, duration_us)

      # Cold path - get stats
      SimulatorMetrics.get_stats(coordinator_id)
  """

  @table_name :cadence_simulator_metrics

  # Counter slot indices
  @slots %{
    # Throughput counters
    packets_generated: 1,
    packets_encoded: 2,
    packets_sent: 3,
    bytes_sent: 4,
    packets_dropped: 5,

    # Latency tracking (sum + count pairs)
    latency_sum_generation: 6,
    latency_count_generation: 7,
    latency_sum_encoding: 8,
    latency_count_encoding: 9,
    latency_sum_sending: 10,
    latency_count_sending: 11,
    latency_sum_total: 12,
    latency_count_total: 13
  }

  @slot_count 14

  # Timing stages we track
  @timing_stages [:generation, :encoding, :sending, :total]

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
  Initializes metrics for a coordinator.

  Creates a :counters reference and stores it in ETS.
  """
  def init(coordinator_id) do
    ensure_table()

    counter_ref = :counters.new(@slot_count, [:write_concurrency])
    :ets.insert(@table_name, {{coordinator_id, :counters}, counter_ref})
    :ets.insert(@table_name, {{coordinator_id, :started_at}, System.monotonic_time(:millisecond)})

    :ok
  end

  @doc """
  Atomically increments a counter.

  This is the hot path - designed for minimal overhead.
  """
  def inc(coordinator_id, counter, amount \\ 1) do
    slot = Map.fetch!(@slots, counter)

    case get_counter_ref(coordinator_id) do
      nil -> :ok
      ref -> :counters.add(ref, slot, amount)
    end
  end

  @doc """
  Records a timing sample for a stage.

  Updates sum and count for calculating averages.
  The caller is responsible for sampling (e.g., only call for 1 in 100 packets).
  """
  def record_timing(coordinator_id, stage, duration_us)
      when is_atom(stage) and is_integer(duration_us) do
    sum_slot = Map.get(@slots, :"latency_sum_#{stage}")
    count_slot = Map.get(@slots, :"latency_count_#{stage}")

    if sum_slot && count_slot do
      case get_counter_ref(coordinator_id) do
        nil ->
          :ok

        ref ->
          :counters.add(ref, sum_slot, duration_us)
          :counters.add(ref, count_slot, 1)
      end
    end
  end

  @doc """
  Gets merged stats for a coordinator.
  """
  def get_stats(coordinator_id) do
    ensure_table()

    case get_counter_ref(coordinator_id) do
      nil ->
        empty_stats()

      ref ->
        build_stats(ref, coordinator_id)
    end
  end

  defp build_stats(ref, coordinator_id) do
    started_at = get_started_at(coordinator_id)
    duration_ms = System.monotonic_time(:millisecond) - started_at
    duration_sec = max(duration_ms / 1000, 0.001)

    %{
      packets_generated: :counters.get(ref, @slots[:packets_generated]),
      packets_encoded: :counters.get(ref, @slots[:packets_encoded]),
      packets_sent: :counters.get(ref, @slots[:packets_sent]),
      bytes_sent: :counters.get(ref, @slots[:bytes_sent]),
      packets_dropped: :counters.get(ref, @slots[:packets_dropped]),
      timing: build_timing_stats(ref),
      duration_ms: duration_ms,
      duration_sec: duration_sec,
      packets_per_sec: Float.round(:counters.get(ref, @slots[:packets_sent]) / duration_sec, 1),
      bytes_per_sec: Float.round(:counters.get(ref, @slots[:bytes_sent]) / duration_sec, 1),
      mbps:
        Float.round(
          :counters.get(ref, @slots[:bytes_sent]) * 8 / duration_sec / 1_000_000,
          2
        )
    }
  end

  defp build_timing_stats(ref) do
    Enum.reduce(@timing_stages, %{}, fn stage, acc ->
      case stage_timing_stats(ref, stage) do
        nil -> acc
        stats -> Map.put(acc, stage, stats)
      end
    end)
  end

  defp stage_timing_stats(ref, stage) do
    sum_slot = Map.get(@slots, :"latency_sum_#{stage}")
    count_slot = Map.get(@slots, :"latency_count_#{stage}")

    if sum_slot && count_slot do
      sum = :counters.get(ref, sum_slot)
      count = :counters.get(ref, count_slot)
      avg = if count > 0, do: Float.round(sum / count, 1), else: 0.0
      %{avg_us: avg, count: count}
    else
      nil
    end
  end

  @doc """
  Resets all counters for a coordinator.
  """
  def reset(coordinator_id) do
    case get_counter_ref(coordinator_id) do
      nil ->
        :ok

      ref ->
        for slot <- 1..@slot_count do
          current = :counters.get(ref, slot)
          :counters.sub(ref, slot, current)
        end

        :ets.insert(
          @table_name,
          {{coordinator_id, :started_at}, System.monotonic_time(:millisecond)}
        )
    end

    :ok
  end

  @doc """
  Cleans up metrics for a coordinator.
  """
  def cleanup(coordinator_id) do
    ensure_table()
    :ets.delete(@table_name, {coordinator_id, :counters})
    :ets.delete(@table_name, {coordinator_id, :started_at})
    :ok
  end

  # Private helpers

  defp get_counter_ref(coordinator_id) do
    key = {coordinator_id, :counters}

    case :ets.lookup(@table_name, key) do
      [{^key, ref}] -> ref
      [] -> nil
    end
  end

  defp get_started_at(coordinator_id) do
    case :ets.lookup(@table_name, {coordinator_id, :started_at}) do
      [{_, time}] -> time
      [] -> System.monotonic_time(:millisecond)
    end
  end

  defp empty_stats do
    %{
      packets_generated: 0,
      packets_encoded: 0,
      packets_sent: 0,
      bytes_sent: 0,
      packets_dropped: 0,
      timing: %{},
      duration_ms: 0,
      duration_sec: 0.0,
      packets_per_sec: 0.0,
      bytes_per_sec: 0.0,
      mbps: 0.0
    }
  end
end
