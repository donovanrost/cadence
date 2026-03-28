defmodule Cadence.Telemetry.PipelineMetricsTest do
  use Cadence.PureCase, async: false

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Runtime.Telemetry.Lanes.ShardWorker
  alias Cadence.Runtime.Telemetry.PipelineEvent
  alias Cadence.Telemetry.{Evidence, MetricsConfig, PacketEnvelope, PipelineMetrics, SpacePacket}
  alias Cadence.TestSupport.FakeLaneRouter

  setup do
    case Process.whereis(Cadence.PubSub) do
      nil -> start_supervised!({Phoenix.PubSub, name: Cadence.PubSub})
      _pid -> :ok
    end

    previous = Application.get_env(:cadence, MetricsConfig, [])

    on_exit(fn ->
      Application.put_env(:cadence, MetricsConfig, previous)
      MetricsConfig.refresh()
    end)

    :ok
  end

  test "record_timing stores timing stats" do
    mission_id = random_id()
    :ok = PipelineMetrics.init(mission_id, 1)

    PipelineMetrics.record_timing(mission_id, 0, :parse, 120)

    stats = PipelineMetrics.get_stats(mission_id)
    timing = Map.get(stats.timing, :parse)

    assert timing.count == 1
    assert timing.min_us == 120
    assert timing.max_us == 120
    assert timing.avg_us == 120.0
  end

  test "cached partition refs update counters and timings" do
    mission_id = random_id()

    :ok =
      PipelineMetrics.init_lanes(mission_id, [
        %{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}
      ])

    refs = PipelineMetrics.partition_refs(mission_id, {:primary, 0})
    PipelineMetrics.inc_refs(refs, :packets_received, 3)
    PipelineMetrics.record_timing_refs(refs, :parse, 42)

    stats = PipelineMetrics.get_partition_stats(mission_id, {:primary, 0})

    assert get_in(stats, [:counters, :packets_received]) == 3
    assert get_in(stats, [:timing, :parse, :count]) == 1
    assert get_in(stats, [:timing, :parse, :min_us]) == 42
  end

  test "cached partition refs are safe when metrics are not initialized" do
    refs = PipelineMetrics.partition_refs(random_id(), {:primary, 0})

    assert :ok == PipelineMetrics.inc_refs(refs, :packets_received, 1)
    assert :ok == PipelineMetrics.record_timing_refs(refs, :parse, 10)
  end

  test "record_timing is safe when metrics are not initialized" do
    mission_id = random_id()

    assert :ok == PipelineMetrics.record_timing(mission_id, 0, :parse, 50)
  end

  test "ingress partition is initialized for lanes and accepts metrics" do
    mission_id = random_id()
    lanes = [%{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}]
    :ok = PipelineMetrics.init_lanes(mission_id, lanes)

    assert PipelineMetrics.ingress_partition() in PipelineMetrics.get_partition_keys(mission_id)

    ingress = PipelineMetrics.ingress_partition()
    PipelineMetrics.inc(mission_id, ingress, :envelopes_emitted)
    PipelineMetrics.record_timing(mission_id, ingress, :sdlp_decode, 42)

    stats = PipelineMetrics.get_partition_stats(mission_id, ingress)
    assert get_in(stats, [:counters, :envelopes_emitted]) == 1
    assert get_in(stats, [:timing, :sdlp_decode, :count]) == 1
  end

  test "ingress timing stages are safe when metrics are not initialized" do
    mission_id = random_id()
    ingress = PipelineMetrics.ingress_partition()

    assert :ok == PipelineMetrics.record_timing(mission_id, ingress, :sdlp_decode, 10)
    assert :ok == PipelineMetrics.record_timing(mission_id, ingress, :sdlp_reassembly, 10)
  end

  test "histogram percentiles are computed from timing samples" do
    mission_id = random_id()
    :ok = PipelineMetrics.init(mission_id, 1)

    Enum.each(1..100, fn _ ->
      PipelineMetrics.record_timing(mission_id, 0, :parse, 10)
    end)

    Enum.each(1..100, fn _ ->
      PipelineMetrics.record_timing(mission_id, 0, :parse, 1000)
    end)

    stats = PipelineMetrics.get_stats(mission_id)
    percentiles = Map.get(stats.timing_percentiles, :parse)

    assert percentiles.p50 == 16
    assert percentiles.p95 == 1024
    assert percentiles.p99 == 1024
  end

  test "timing sampling respects configured rates" do
    Application.put_env(:cadence, MetricsConfig,
      enable_pipeline_timings?: true,
      timing_sample_rate: 1.0
    )

    MetricsConfig.refresh()
    assert MetricsConfig.timing_sample?()

    Application.put_env(:cadence, MetricsConfig,
      enable_pipeline_timings?: true,
      timing_sample_rate: 0.0
    )

    MetricsConfig.refresh()
    refute MetricsConfig.timing_sample?()
  end

  test "end_to_end latency uses envelope ingest monotonic time" do
    Application.put_env(:cadence, MetricsConfig,
      enable_pipeline_timings?: true,
      end_to_end_sample_rate: 1.0
    )

    MetricsConfig.refresh()

    mission_id = random_id()
    lanes = [%{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}]
    :ok = PipelineMetrics.init_lanes(mission_id, lanes)

    router_pid = start_supervised!({FakeLaneRouter, queue_depths: %{}})

    {:ok, worker_pid} =
      start_supervised(
        {ShardWorker,
         mission_id: mission_id,
         lane: :primary,
         shard_id: 0,
         router: router_pid,
         max_batch_size: 1,
         max_batch_delay_ms: 1_000,
         max_inflight: 10}
      )

    ingest_ns = System.monotonic_time(:nanosecond) - 2_000_000
    envelope = PacketEnvelope.new(mission_id, <<1>>, ingest_monotonic_ns: ingest_ns)

    event = %PipelineEvent{
      packet_id: envelope.packet_id,
      mission_id: mission_id,
      lane: :primary,
      shard_id: 0,
      router_version: 1,
      config_version: 0,
      envelope: envelope,
      parsed_unit: nil,
      parse_error: :bad_packet,
      resolved_unit: nil,
      ingest_monotonic_ns: ingest_ns
    }

    GenServer.cast(worker_pid, {:telemetry_event, event})

    assert_eventually(
      fn ->
        stats = PipelineMetrics.get_stats(mission_id)
        timing = Map.get(stats.timing, :end_to_end)
        is_map(timing) && timing.count > 0
      end,
      timeout: 1000
    )

    stats = PipelineMetrics.get_stats(mission_id)
    timing = Map.get(stats.timing, :end_to_end)

    assert timing.min_us >= 2_000
  end

  test "worker post decom timing is recorded for successful decom packets" do
    Application.put_env(:cadence, MetricsConfig,
      enable_pipeline_timings?: true,
      timing_sample_rate: 1.0
    )

    MetricsConfig.refresh()

    mission_id = random_id()
    lanes = [%{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}]
    :ok = PipelineMetrics.init_lanes(mission_id, lanes)
    :ok = ConfigBundle.store(build_decom_bundle(mission_id))

    router_pid = start_supervised!({FakeLaneRouter, queue_depths: %{}})

    {:ok, worker_pid} =
      start_supervised(
        {ShardWorker,
         mission_id: mission_id,
         lane: :primary,
         shard_id: 0,
         router: router_pid,
         sink_opts: [skip_log_records: true],
         max_batch_size: 1,
         max_batch_delay_ms: 1_000,
         max_inflight: 10}
      )

    GenServer.cast(worker_pid, {:telemetry_event, build_decom_event(mission_id)})

    assert_eventually(
      fn ->
        timing = PipelineMetrics.get_partition_stats(mission_id, {:primary, 0}).timing
        get_in(timing, [:worker_post_decom, :count]) == 1
      end,
      timeout: 1000
    )
  end

  defp build_decom_bundle(mission_id) do
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

  defp build_decom_event(mission_id) do
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
