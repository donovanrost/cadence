defmodule CadenceSimulator.ProfileSweepTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.ProfileSweep

  test "parse_rates parses comma-separated positive float values" do
    assert {:ok, [5.0, 10.5, 25.0]} = ProfileSweep.parse_rates("5, 10.5,25")
  end

  test "parse_rates rejects invalid values" do
    assert {:error, message} = ProfileSweep.parse_rates("5, nope, 0")
    assert message =~ "invalid rate values"
    assert message =~ "nope"
  end

  test "build_summary derives throughput, stage, db, archive, and simulator values" do
    snapshot = %{
      ingress_count: 40,
      packets: %{packet_count: 60},
      dispatch: %{sample_count: 420},
      stages: %{
        resolve: %{avg_us: 250.0},
        runtime: %{avg_us: 125.0},
        persistence: %{avg_us: 875.0},
        end_to_end: %{avg_us: 1_400.0}
      },
      db: %{
        queries_per_ingress: 3.75,
        query_time_per_ingress_us: 950.0
      },
      archive: %{
        combined: %{
          queue_depth: 2,
          oldest_buffered_age_ms: 150,
          avg_flush_us: 4_500.0,
          avg_segment_bytes: 3_072.0,
          flush_failure_count: 1
        }
      }
    }

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

    summary = ProfileSweep.build_summary(25.0, snapshot, 8, simulator_before, simulator_after)

    assert summary.rate_hz == 25.0
    assert summary.ingress_per_sec == 5.0
    assert summary.packets_per_sec == 7.5
    assert summary.samples_per_sec == 52.5
    assert summary.resolve_ms == 0.25
    assert summary.runtime_ms == 0.125
    assert summary.persist_ms == 0.875
    assert summary.e2e_ms == 1.4
    assert summary.db_queries_per_ingress == 3.75
    assert summary.db_ms_per_ingress == 0.95
    assert summary.archive_queue_depth == 2
    assert summary.archive_oldest_buffered_age_ms == 150
    assert summary.archive_avg_flush_ms == 4.5
    assert summary.archive_avg_segment_kb == 3.0
    assert summary.archive_flush_failures == 1
    assert summary.simulator_tx_per_sec == 10.0
    assert summary.simulator_mbps == 0.016
    assert summary.simulator_queue_depth == 3
    assert summary.simulator_flushes_per_sec == 1.0
    assert summary.simulator_kb_per_flush == 1.953125
    assert summary.simulator_generation_ms == 0.2
    assert summary.simulator_framing_ms == 0.3
    assert summary.simulator_send_ms == 0.4
  end
end
