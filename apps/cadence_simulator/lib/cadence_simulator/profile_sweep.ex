defmodule CadenceSimulator.ProfileSweep do
  @moduledoc """
  Helpers for stepped downlink profiling sweeps against a running Cadence node.
  """

  @type summary :: %{
          rate_hz: float(),
          ingress_per_sec: float(),
          packets_per_sec: float(),
          samples_per_sec: float(),
          resolve_ms: float(),
          runtime_ms: float(),
          persist_ms: float(),
          e2e_ms: float(),
          db_queries_per_ingress: float(),
          db_ms_per_ingress: float(),
          archive_queue_depth: non_neg_integer(),
          archive_oldest_buffered_age_ms: non_neg_integer(),
          archive_avg_flush_ms: float(),
          archive_avg_segment_kb: float(),
          archive_flush_failures: non_neg_integer(),
          simulator_tx_per_sec: float(),
          simulator_mbps: float(),
          simulator_queue_depth: non_neg_integer(),
          simulator_flushes_per_sec: float(),
          simulator_kb_per_flush: float(),
          simulator_generation_ms: float(),
          simulator_framing_ms: float(),
          simulator_send_ms: float()
        }

  @spec parse_rates(binary()) :: {:ok, [float()]} | {:error, String.t()}
  def parse_rates(value) when is_binary(value) do
    rates =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&parse_rate/1)

    with true <- rates != [] || {:error, "--rates requires at least one value"},
         :ok <- validate_rates(rates) do
      {:ok, Enum.map(rates, fn {:ok, rate} -> rate end)}
    end
  end

  @spec build_summary(float(), map(), pos_integer(), map() | nil, map() | nil) :: summary()
  def build_summary(rate_hz, snapshot, duration_seconds, simulator_before \\ nil, simulator_after \\ nil)
      when is_number(rate_hz) and is_map(snapshot) and is_integer(duration_seconds) and
             duration_seconds > 0 do
    archive = get_in(snapshot, [:archive, :combined]) || %{}
    simulator = simulator_summary(simulator_before, simulator_after, duration_seconds)

    %{
      rate_hz: rate_hz * 1.0,
      ingress_per_sec: get_in(snapshot, [:ingress_count]) / duration_seconds,
      packets_per_sec: get_in(snapshot, [:packets, :packet_count]) / duration_seconds,
      samples_per_sec: get_in(snapshot, [:dispatch, :sample_count]) / duration_seconds,
      resolve_ms: us_to_ms(get_in(snapshot, [:stages, :resolve, :avg_us])),
      runtime_ms: us_to_ms(get_in(snapshot, [:stages, :runtime, :avg_us])),
      persist_ms: us_to_ms(get_in(snapshot, [:stages, :persistence, :avg_us])),
      e2e_ms: us_to_ms(get_in(snapshot, [:stages, :end_to_end, :avg_us])),
      db_queries_per_ingress: get_in(snapshot, [:db, :queries_per_ingress]) * 1.0,
      db_ms_per_ingress: us_to_ms(get_in(snapshot, [:db, :query_time_per_ingress_us])),
      archive_queue_depth: archive[:queue_depth] || 0,
      archive_oldest_buffered_age_ms: archive[:oldest_buffered_age_ms] || 0,
      archive_avg_flush_ms: us_to_ms(archive[:avg_flush_us] || 0.0),
      archive_avg_segment_kb: (archive[:avg_segment_bytes] || 0.0) / 1024.0,
      archive_flush_failures: archive[:flush_failure_count] || 0,
      simulator_tx_per_sec: simulator.tx_per_sec,
      simulator_mbps: simulator.mbps,
      simulator_queue_depth: simulator.queue_depth,
      simulator_flushes_per_sec: simulator.flushes_per_sec,
      simulator_kb_per_flush: simulator.kb_per_flush,
      simulator_generation_ms: simulator.generation_ms,
      simulator_framing_ms: simulator.framing_ms,
      simulator_send_ms: simulator.send_ms
    }
  end

  defp parse_rate(value) do
    case Float.parse(value) do
      {rate, ""} when rate > 0.0 -> {:ok, rate}
      _other -> {:error, value}
    end
  end

  defp validate_rates(rates) do
    invalid =
      Enum.flat_map(rates, fn
        {:ok, _rate} -> []
        {:error, value} -> [value]
      end)

    case invalid do
      [] -> :ok
      values -> {:error, "invalid rate values: #{Enum.join(values, ", ")}"}
    end
  end

  defp simulator_summary(nil, _after, _duration_seconds),
    do: %{tx_per_sec: 0.0, mbps: 0.0, queue_depth: 0, flushes_per_sec: 0.0, kb_per_flush: 0.0}

  defp simulator_summary(_before, nil, _duration_seconds),
    do: %{tx_per_sec: 0.0, mbps: 0.0, queue_depth: 0, flushes_per_sec: 0.0, kb_per_flush: 0.0}

  defp simulator_summary(before_stats, after_stats, duration_seconds) do
    before_send_buffer = Map.get(before_stats, :send_buffer_stats, %{})
    after_send_buffer = Map.get(after_stats, :send_buffer_stats, %{})
    before_metrics = get_in(before_stats, [:simulator_metrics, :timing]) || %{}
    after_metrics = get_in(after_stats, [:simulator_metrics, :timing]) || %{}

    packets_sent =
      non_negative_delta(
        Map.get(after_send_buffer, :packets_sent, 0),
        Map.get(before_send_buffer, :packets_sent, 0)
      )

    bytes_sent =
      non_negative_delta(
        Map.get(after_send_buffer, :bytes_sent, 0),
        Map.get(before_send_buffer, :bytes_sent, 0)
      )

    flushes =
      non_negative_delta(
        Map.get(after_send_buffer, :flushes, 0),
        Map.get(before_send_buffer, :flushes, 0)
      )

    %{
      tx_per_sec: packets_sent / duration_seconds,
      mbps: bytes_sent * 8 / duration_seconds / 1_000_000,
      queue_depth: Map.get(after_send_buffer, :packets_buffered, 0),
      flushes_per_sec: flushes / duration_seconds,
      kb_per_flush: if(flushes > 0, do: bytes_sent / flushes / 1024.0, else: 0.0),
      generation_ms: timing_delta_ms(before_metrics, after_metrics, :generation),
      framing_ms: timing_delta_ms(before_metrics, after_metrics, :framing),
      send_ms: timing_delta_ms(before_metrics, after_metrics, :sending)
    }
  end

  defp non_negative_delta(after_value, before_value)
       when is_integer(after_value) and is_integer(before_value) do
    max(after_value - before_value, 0)
  end

  defp timing_delta_ms(before_metrics, after_metrics, stage) do
    before_stage = Map.get(before_metrics, stage, %{})
    after_stage = Map.get(after_metrics, stage, %{})
    total_us = non_negative_delta(Map.get(after_stage, :total_us, 0), Map.get(before_stage, :total_us, 0))
    count = non_negative_delta(Map.get(after_stage, :count, 0), Map.get(before_stage, :count, 0))

    if count > 0 do
      total_us / count / 1000.0
    else
      0.0
    end
  end

  defp us_to_ms(value) when is_number(value), do: value / 1000.0
  defp us_to_ms(_value), do: 0.0
end
