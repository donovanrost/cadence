defmodule Cadence.Runtime.Telemetry.Lanes.ShardWorkerSkipLogRecordsTest do
  use Cadence.PureCase, async: false

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Telemetry.Lanes.ShardWorker
  alias Cadence.Runtime.Telemetry.PipelineEvent
  alias Cadence.Telemetry.{Evidence, PacketEnvelope, PipelineMetrics, SpacePacket}
  alias Cadence.TestSupport.{FakeLaneRouter, FakeLogSink}

  test "processes decom packets without appending when log records are skipped" do
    mission_id = random_id()

    :ok =
      PipelineMetrics.init_lanes(mission_id, [
        %{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}
      ])

    :ok = ConfigBundle.store(build_bundle(mission_id))

    router_pid = start_supervised!({FakeLaneRouter, queue_depths: %{}})

    {:ok, worker_pid} =
      start_supervised(
        {ShardWorker,
         mission_id: mission_id,
         lane: :primary,
         shard_id: 0,
         router: router_pid,
         sink: FakeLogSink,
         sink_opts: [notify: self(), skip_log_records: true],
         max_batch_size: 1,
         max_batch_delay_ms: 60_000,
         max_inflight: 10}
      )

    GenServer.cast(worker_pid, {:telemetry_event, build_event(mission_id)})

    assert_eventually(
      fn ->
        counters = PipelineMetrics.get_counters(mission_id, {:primary, 0})

        Map.get(counters, :packets_processed) == 1 and
          Map.get(counters, :packets_decom_processed) == 1 and
          Map.get(counters, :items_processed) == 1
      end,
      timeout: 1000
    )

    refute_received {:fake_log_sink_append, _, _}
  end

  defp build_bundle(mission_id) do
    target = %{id: "target-1", scid: 42, definition_set_id: "def-set-1"}

    packet_def = %{
      id: "packet-1",
      name: "PKT",
      items: [
        %{name: "temp", bit_offset: 0, bit_size: 8, data_type: "uint"}
      ]
    }

    %ConfigBundle{
      mission_id: mission_id,
      config_version: 0,
      targets: [target],
      targets_by_identifier: %{target.id => target},
      target_ids_by_scid: %{target.scid => target.id},
      packet_catalog: %{by_apid: %{{"def-set-1", 100} => packet_def}}
    }
  end

  defp build_event(mission_id) do
    envelope =
      PacketEnvelope.new(mission_id, <<1>>, config_version_seen: 0)
      |> PacketEnvelope.add_evidence(Evidence.scid(42, :frame, :high))

    packet = %SpacePacket{
      primary: %{
        version: 0,
        type: 0,
        sec_hdr_flag: 1,
        apid: 100,
        seq_flags: 3,
        seq_count: 1,
        length: 0
      },
      sec_header: nil,
      user_data: <<17>>,
      raw_ref: nil
    }

    %PipelineEvent{
      packet_id: envelope.packet_id,
      mission_id: mission_id,
      lane: :primary,
      shard_id: 0,
      router_version: 1,
      config_version: 0,
      envelope: envelope,
      parsed_unit: {:space_packet, packet},
      parse_error: nil,
      resolved_unit: nil,
      ingest_monotonic_ns: envelope.ingest_monotonic_ns
    }
  end
end
