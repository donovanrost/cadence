defmodule Cadence.Runtime.Protocol.ChannelServiceIngressMetricsTest do
  use Cadence.PureCase, async: false

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SDLP.Metrics, as: SDLPMetrics
  alias Cadence.CCSDS.SDLP.TM.FrameCodec, as: TMFrameCodec
  alias Cadence.CCSDS.SDU.Mapping
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Protocol.ChannelService
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor
  alias Cadence.Telemetry.{MetricsConfig, PacketEnvelope, PipelineMetrics}
  alias Cadence.Time, as: CadenceTime

  setup_mission_registry()

  setup do
    case Process.whereis(Cadence.PubSub) do
      nil -> start_supervised!({Phoenix.PubSub, name: Cadence.PubSub})
      _pid -> :ok
    end

    previous = Application.get_env(:cadence, MetricsConfig, [])

    Application.put_env(:cadence, MetricsConfig,
      enable_pipeline_timings?: true,
      timing_sample_rate: 1.0
    )

    MetricsConfig.refresh()

    on_exit(fn ->
      Application.put_env(:cadence, MetricsConfig, previous)
      MetricsConfig.refresh()
    end)

    :ok
  end

  test "records ingress timings and envelopes for TM downlink" do
    mission_id = random_id()
    channel_id = ChannelId.new(1, 2, nil)

    start_supervised!({ProtocolSupervisor, mission_id: mission_id})

    lanes = [%{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}]
    :ok = PipelineMetrics.init_lanes(mission_id, lanes)

    :ok = ProtocolSupervisor.ensure_channel(mission_id, channel_id)

    mapping = Mapping.new(%{{1, 2, nil, :downlink} => :space_packet}, :space_packet)

    packet = build_space_packet(10, 1)
    frame_size = 6 + byte_size(packet)
    frame = build_tm_frame(packet, frame_size, 1, 2)

    protocol_config = %{sdlp: {:ok, %{mapping: mapping, opts: [frame_size: frame_size]}}}

    ChannelService.apply_config(mission_id, channel_id, %{
      protocol_config: protocol_config,
      config_version: 1
    })

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:telemetry:raw")

    ChannelService.handle_downlink(mission_id, channel_id, frame, %{
      received_at: CadenceTime.now()
    })

    assert_receive {:packet_envelope, %PacketEnvelope{}}, 1_000

    assert_eventually(fn ->
      sdlp = SDLPMetrics.get_stats(mission_id)

      ingress =
        PipelineMetrics.get_partition_stats(mission_id, PipelineMetrics.ingress_partition())

      decode_total = get_in(sdlp, [:tm, :frame_decode, :total]) || 0
      sdu_emitted = get_in(sdlp, [:tm, :reassembly, :sdu_emitted]) || 0
      envelopes = get_in(ingress, [:counters, :envelopes_emitted]) || 0

      decode_timing = get_in(ingress, [:timing, :sdlp_decode, :count]) || 0
      reassembly_timing = get_in(ingress, [:timing, :sdlp_reassembly, :count]) || 0
      envelope_timing = get_in(ingress, [:timing, :envelope_build, :count]) || 0

      decode_total > 0 and sdu_emitted > 0 and envelopes > 0 and decode_timing > 0 and
        reassembly_timing > 0 and envelope_timing > 0
    end)
  end

  test "caches dispatcher readiness after first TM downlink" do
    mission_id = random_id()
    channel_id = ChannelId.new(1, 2, nil)

    start_supervised!({ProtocolSupervisor, mission_id: mission_id})

    lanes = [%{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}]
    :ok = PipelineMetrics.init_lanes(mission_id, lanes)
    :ok = ProtocolSupervisor.ensure_channel(mission_id, channel_id)

    mapping = Mapping.new(%{{1, 2, nil, :downlink} => :space_packet}, :space_packet)

    packet = build_space_packet(10, 1)
    frame_size = 6 + byte_size(packet)
    frame = build_tm_frame(packet, frame_size, 1, 2)

    ChannelService.apply_config(mission_id, channel_id, %{
      protocol_config: %{sdlp: {:ok, %{mapping: mapping, opts: [frame_size: frame_size]}}},
      config_version: 1
    })

    ChannelService.handle_downlink(mission_id, channel_id, frame, %{
      received_at: CadenceTime.now()
    })

    service_pid =
      case Registry.lookup(Cadence.MissionRegistry, {:channel_service, mission_id, {1, 2, nil}}) do
        [{pid, _}] -> pid
        [] -> flunk("expected channel service registration")
      end

    assert_eventually(
      fn ->
        state = :sys.get_state(service_pid)
        state.pdu_dispatcher_ready? == true
      end,
      timeout: 1_000
    )
  end

  test "caches fallback protocol config after first TM downlink" do
    mission_id = random_id()
    channel_id = ChannelId.new(1, 2, nil)

    start_supervised!({ProtocolSupervisor, mission_id: mission_id})
    start_supervised!({LinkController, mission_id: mission_id, scid: 1})

    lanes = [%{name: :primary, shard_count: 1, virtual_shards: 1, selectors: %{}}]
    :ok = PipelineMetrics.init_lanes(mission_id, lanes)
    :ok = ProtocolSupervisor.ensure_channel(mission_id, channel_id)

    mapping = Mapping.new(%{{1, 2, nil, :downlink} => :space_packet}, :space_packet)

    packet = build_space_packet(10, 1)
    frame_size = 6 + byte_size(packet)
    frame = build_tm_frame(packet, frame_size, 1, 2)

    protocol_config = %{sdlp: {:ok, %{mapping: mapping, opts: [frame_size: frame_size]}}}

    :ok =
      LinkController.apply_config(mission_id, 1, %{
        config_version: 1,
        link_defaults: protocol_config,
        effective_protocols: %{ChannelId.key(channel_id) => protocol_config}
      })

    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:telemetry:raw")

    ChannelService.handle_downlink(mission_id, channel_id, frame, %{
      received_at: CadenceTime.now()
    })

    assert_receive {:packet_envelope, %PacketEnvelope{}}, 1_000

    service_pid =
      case Registry.lookup(Cadence.MissionRegistry, {:channel_service, mission_id, {1, 2, nil}}) do
        [{pid, _}] -> pid
        [] -> flunk("expected channel service registration")
      end

    assert_eventually(
      fn ->
        state = :sys.get_state(service_pid)
        state.protocol_config == protocol_config
      end,
      timeout: 1_000
    )
  end

  defp build_space_packet(apid, seq) do
    user_data = <<0xAB>>
    secondary_header = <<0::48, 0::16>>
    packet_length = byte_size(secondary_header <> user_data) - 1

    <<
      0::3,
      0::1,
      1::1,
      apid::11,
      3::2,
      seq::14,
      packet_length::16,
      secondary_header::binary,
      user_data::binary
    >>
  end

  defp build_tm_frame(packet, frame_size, scid, vcid) do
    frame = %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      payload_octets: packet,
      quality: :good,
      meta: %{fhp: 0}
    }

    {:ok, encoded} = TMFrameCodec.encode(frame, frame_size: frame_size)
    encoded
  end
end
