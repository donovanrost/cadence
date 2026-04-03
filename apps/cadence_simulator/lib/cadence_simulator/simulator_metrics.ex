defmodule CadenceSimulator.SimulatorMetrics do
  @moduledoc """
  Lock-free simulator metrics backed by Erlang `:counters`.
  """

  @table :cadence_simulator_metrics

  @slots %{
    tx_packets: 1,
    tx_bytes: 2,
    latency_sum_generation: 3,
    latency_count_generation: 4,
    latency_sum_framing: 5,
    latency_count_framing: 6,
    latency_sum_sending: 7,
    latency_count_sending: 8
  }

  @slot_count 8
  @timing_stages [:generation, :framing, :sending]

  @spec init(term()) :: :ok
  def init(scope) do
    ensure_table()
    counters = :counters.new(@slot_count, [:write_concurrency])
    true = :ets.insert(@table, {scope, counters})
    :ok
  end

  @spec cleanup(term()) :: :ok
  def cleanup(scope) do
    ensure_table()
    :ets.delete(@table, scope)
    :ok
  end

  @spec inc(term(), atom(), non_neg_integer()) :: :ok
  def inc(scope, metric, amount \\ 1) when is_integer(amount) and amount >= 0 do
    ensure_table()

    case lookup(scope) do
      nil -> :ok
      counters -> :counters.add(counters, Map.fetch!(@slots, metric), amount)
    end
  end

  @spec record_timing(term(), :generation | :framing | :sending, integer()) :: :ok
  def record_timing(scope, stage, duration_us)
      when stage in @timing_stages and is_integer(duration_us) and duration_us >= 0 do
    ensure_table()

    case lookup(scope) do
      nil ->
        :ok

      counters ->
        :counters.add(counters, Map.fetch!(@slots, :"latency_sum_#{stage}"), duration_us)
        :counters.add(counters, Map.fetch!(@slots, :"latency_count_#{stage}"), 1)
    end
  end

  @spec record_timing_sampled(
          term(),
          :generation | :framing | :sending,
          integer(),
          non_neg_integer() | nil,
          integer()
        ) :: :ok
  def record_timing_sampled(scope, stage, duration_us, sample_rate, sample_ordinal)
      when stage in @timing_stages and is_integer(duration_us) and duration_us >= 0 and
             is_integer(sample_ordinal) do
    if sample_timing?(sample_rate, sample_ordinal) do
      record_timing(scope, stage, duration_us)
    else
      :ok
    end
  end

  @spec sample_timing?(non_neg_integer() | nil, integer()) :: boolean()
  def sample_timing?(sample_rate, _ordinal) when sample_rate in [nil, 1], do: true
  def sample_timing?(0, _ordinal), do: false

  def sample_timing?(sample_rate, ordinal)
      when is_integer(sample_rate) and sample_rate > 1 and is_integer(ordinal) do
    rem(max(ordinal, 0), sample_rate) == 0
  end

  def sample_timing?(_sample_rate, _ordinal), do: true

  @spec snapshot(term()) :: map()
  def snapshot(scope) do
    ensure_table()

    case lookup(scope) do
      nil ->
        %{
          tx_packets: 0,
          tx_bytes: 0,
          timing: %{}
        }

      counters ->
        %{
          tx_packets: :counters.get(counters, @slots.tx_packets),
          tx_bytes: :counters.get(counters, @slots.tx_bytes),
          timing:
            Map.new(@timing_stages, fn stage ->
              sum_slot = Map.fetch!(@slots, :"latency_sum_#{stage}")
              count_slot = Map.fetch!(@slots, :"latency_count_#{stage}")
              total_us = :counters.get(counters, sum_slot)
              count = :counters.get(counters, count_slot)
              avg_us = if count > 0, do: total_us / count, else: 0.0

              {stage, %{total_us: total_us, count: count, avg_us: avg_us}}
            end)
        }
    end
  end

  defp lookup(scope) do
    case :ets.lookup(@table, scope) do
      [{^scope, counters}] -> counters
      [] -> nil
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
