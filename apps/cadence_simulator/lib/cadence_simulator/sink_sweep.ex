defmodule CadenceSimulator.SinkSweep do
  @moduledoc """
  Helpers for simulator-only throughput sweeps against a dumb TCP drain sink.
  """

  alias CadenceSimulator.ProfileSweep

  @type summary :: %{
          rate_hz: float(),
          simulator_tx_per_sec: float(),
          simulator_mbps: float(),
          simulator_queue_depth: non_neg_integer(),
          simulator_flushes_per_sec: float(),
          simulator_kb_per_flush: float(),
          simulator_generation_ms: float(),
          simulator_framing_ms: float(),
          simulator_send_ms: float(),
          sink_mbps: float(),
          sink_chunks_per_sec: float(),
          sink_accepted_connections: non_neg_integer(),
          sink_open_connections: non_neg_integer()
        }

  @spec build_summary(float(), pos_integer(), map() | nil, map() | nil, map() | nil, map() | nil) ::
          summary()
  def build_summary(
        rate_hz,
        duration_seconds,
        simulator_before,
        simulator_after,
        sink_before,
        sink_after
      )
      when is_number(rate_hz) and is_integer(duration_seconds) and duration_seconds > 0 do
    simulator =
      ProfileSweep.build_simulator_summary(simulator_before, simulator_after, duration_seconds)

    sink_before = sink_before || %{}
    sink_after = sink_after || %{}

    bytes_received =
      non_negative_delta(
        Map.get(sink_after, :bytes_received, 0),
        Map.get(sink_before, :bytes_received, 0)
      )

    chunks_received =
      non_negative_delta(
        Map.get(sink_after, :chunks_received, 0),
        Map.get(sink_before, :chunks_received, 0)
      )

    accepted_connections =
      non_negative_delta(
        Map.get(sink_after, :accepted_connections, 0),
        Map.get(sink_before, :accepted_connections, 0)
      )

    %{
      rate_hz: rate_hz * 1.0,
      simulator_tx_per_sec: simulator.tx_per_sec,
      simulator_mbps: simulator.mbps,
      simulator_queue_depth: simulator.queue_depth,
      simulator_flushes_per_sec: simulator.flushes_per_sec,
      simulator_kb_per_flush: simulator.kb_per_flush,
      simulator_generation_ms: simulator.generation_ms,
      simulator_framing_ms: simulator.framing_ms,
      simulator_send_ms: simulator.send_ms,
      sink_mbps: bytes_received * 8 / duration_seconds / 1_000_000,
      sink_chunks_per_sec: chunks_received / duration_seconds,
      sink_accepted_connections: accepted_connections,
      sink_open_connections: Map.get(sink_after, :open_connections, 0)
    }
  end

  defp non_negative_delta(after_value, before_value)
       when is_integer(after_value) and is_integer(before_value) do
    max(after_value - before_value, 0)
  end
end
