defmodule CadenceSimulator.SinkSweepTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.SinkSweep

  test "build_summary derives simulator and sink throughput values" do
    simulator_before = %{
      send_buffer_stats: %{
        packets_sent: 100,
        bytes_sent: 1_000,
        packets_buffered: 1,
        flushes: 10
      },
      simulator_metrics: %{
        timing: %{
          generation: %{total_us: 1_000, count: 2},
          framing: %{total_us: 2_000, count: 4},
          sending: %{total_us: 3_000, count: 5}
        }
      }
    }

    simulator_after = %{
      send_buffer_stats: %{
        packets_sent: 180,
        bytes_sent: 17_000,
        packets_buffered: 3,
        flushes: 18
      },
      simulator_metrics: %{
        timing: %{
          generation: %{total_us: 2_200, count: 8},
          framing: %{total_us: 4_400, count: 12},
          sending: %{total_us: 5_800, count: 12}
        }
      }
    }

    sink_before = %{
      bytes_received: 1_000,
      chunks_received: 50,
      accepted_connections: 1,
      open_connections: 1
    }

    sink_after = %{
      bytes_received: 17_000,
      chunks_received: 82,
      accepted_connections: 2,
      open_connections: 1
    }

    summary =
      SinkSweep.build_summary(
        400.0,
        8,
        simulator_before,
        simulator_after,
        sink_before,
        sink_after
      )

    assert summary.rate_hz == 400.0
    assert summary.simulator_tx_per_sec == 10.0
    assert summary.simulator_mbps == 0.016
    assert summary.simulator_queue_depth == 3
    assert summary.simulator_flushes_per_sec == 1.0
    assert summary.simulator_kb_per_flush == 1.953125
    assert summary.simulator_generation_ms == 0.2
    assert summary.simulator_framing_ms == 0.3
    assert summary.simulator_send_ms == 0.4
    assert summary.sink_mbps == 0.016
    assert summary.sink_chunks_per_sec == 4.0
    assert summary.sink_accepted_connections == 1
    assert summary.sink_open_connections == 1
  end
end
