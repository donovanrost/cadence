defmodule Cadence.Runtime.Transport.COP1.FOPTest do
  use Cadence.PureCase

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Harness.Time
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Links.{Binding, LinkController}
  alias Cadence.Runtime.Links.ProtocolConfig
  alias Cadence.Runtime.Transport.COP1.{Context, FOP, Report, Stream, StreamSupervisor}
  alias Cadence.Runtime.Uplink.FrameBuilder
  alias Cadence.Runtime.Uplink.FramingContext
  alias Cadence.Transport.TCStreamId

  setup_mission_registry()
  setup_virtual_time()

  test "ignores protocol_config interface_id for interface selection" do
    mission_id = Cadence.PureCase.random_id()
    channel_id = ChannelId.new(10, 0)

    protocol_config = %{
      cop1: %{mode: :fop},
      sdlp: {:ok, %{opts: [uplink_frame_size: 16]}},
      cop1_report_apids: [],
      interface_id: Cadence.PureCase.random_id()
    }

    {:ok, _pid} =
      start_supervised(
        {FOP,
         mission_id: mission_id,
         channel_id: channel_id,
         protocol_config: protocol_config,
         release_fun: fn _ -> :ok end}
      )

    assert {:error, :no_active_interface} =
             FOP.send_frames(mission_id, channel_id, [%{bytes: <<0>>}])
  end

  test "acks frames when CLCW report value advances" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)

    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, fop_pid} = start_fop(mission_id, interface, 10, send_fun, link_defaults: link_defaults)

    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 10)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(fop_pid)

    assert :ok ==
             send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    assert_receive {:sent, bytes}

    {:ok, [frame], _rest} = TransferFrame.decode(bytes, frame_size: frame_size)
    assert frame.frame_seq == 0

    stats = FOP.stats(fop_pid)
    assert stats.in_flight_count == 1

    ingest_report(tc_stream_id, frame.frame_seq)
    _ = FOP.stats(fop_pid)

    stats = FOP.stats(fop_pid)
    assert stats.in_flight_count == 0
  end

  test "retransmits on timeout" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)

    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, 11, send_fun, link_defaults: link_defaults)

    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 11)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(pid)

    assert :ok ==
             send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    assert_receive {:sent, bytes}

    {:ok, [_frame], _rest} = TransferFrame.decode(bytes, frame_size: frame_size)

    :ok = Time.advance(50)
    _ = FOP.stats(pid)
    assert_receive {:sent, ^bytes}

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 1
  end

  test "bypass frames are sent without COP-1 tracking" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, 12, send_fun, link_defaults: link_defaults)

    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 12, bypass_flag: 1)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(pid)

    assert :ok ==
             send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    assert_receive {:sent, _bytes}

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 0
    assert stats.pending_count == 0
  end

  test "unlock control command is allowed during lockout" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, 10, send_fun, link_defaults: link_defaults)

    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 10)

    lockout = %CLCW{lockout: 1, vcid: 0, report_value: 0}
    ingest_report(tc_stream_id, 0, clcw: lockout)
    _ = FOP.stats(pid)

    assert {:error, :lockout} ==
             send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    framing_context = FramingContext.new(%{scid: 10, vcid: 0, stream_id: tc_stream_id})
    cop1_context = Context.new(%{vcid: 0, cop1_control: :unlock, stream_id: tc_stream_id})

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    assert_receive {:sent, _bytes}

    stats = FOP.stats(pid)
    assert stats.lockout == true
    assert stats.unlock_pending == true
    assert stats.in_flight_count == 0
  end

  test "rejects out-of-window report values" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, 10, send_fun, link_defaults: link_defaults)

    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 10)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(pid)

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    assert_receive {:sent, bytes}
    {:ok, [frame], _rest} = TransferFrame.decode(bytes, frame_size: frame_size)

    bad_report_value = rem(frame.frame_seq + 1, 256)
    ingest_report(tc_stream_id, bad_report_value)
    _ = FOP.stats(pid)

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 1
    assert stats.last_report_value == 0
  end

  test "window full defers pending frames until report advances" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} =
      build_interface(mission_id, interface_id, frame_size, cop1: %{"window_size" => 1})

    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, 10, send_fun, link_defaults: link_defaults)
    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 10)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(pid)

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)
    assert_receive {:sent, first_bytes}

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)
    refute_receive {:sent, _bytes}, 0

    {:ok, [frame], _rest} = TransferFrame.decode(first_bytes, frame_size: frame_size)
    ingest_report(tc_stream_id, frame.frame_seq)
    _ = FOP.stats(pid)

    assert_receive {:sent, _second_bytes}
  end

  test "timeout retransmits and locks out after max retransmit" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} =
      build_interface(mission_id, interface_id, frame_size,
        cop1: %{"timeout_ms" => 10, "max_retransmit" => 1, "window_size" => 1}
      )

    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, 10, send_fun, link_defaults: link_defaults)
    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 10)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(pid)

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)
    assert_receive {:sent, bytes}

    :ok = Time.advance(10)
    _ = FOP.stats(pid)
    assert_receive {:sent, ^bytes}

    :ok = Time.advance(10)
    _ = FOP.stats(pid)
    stats = FOP.stats(pid)
    assert stats.lockout == true
    assert stats.in_flight_count == 0
  end

  test "reject report removes command from in-flight and emits rejection" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    event_fun = fn event ->
      send(test_pid, {:cop1_event, event})
      :ok
    end

    {:ok, pid} =
      start_fop(mission_id, interface, 10, send_fun,
        link_defaults: link_defaults,
        event_fun: event_fun
      )

    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 10, correlation_id: :corr)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(pid)

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)
    assert_receive {:sent, bytes}

    {:ok, [frame], _rest} = TransferFrame.decode(bytes, frame_size: frame_size)

    ingest_report(tc_stream_id, frame.frame_seq, status: :reject)
    _ = FOP.stats(pid)

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 0

    assert_receive {:cop1_event, %{status: :rejected, seq: seq}}
    assert seq == frame.frame_seq
  end

  test "stream restart holds until resynced" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, 10, send_fun, link_defaults: link_defaults)
    pdu = build_pdu()

    {framing_context, cop1_context, tc_stream_id} =
      cop1_contexts(mission_id, interface_id, 10)

    assert {:defer, :hold_pending_resync} ==
             send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    ingest_report(tc_stream_id, 0)
    _ = FOP.stats(pid)

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    {:ok, stream_pid} =
      StreamSupervisor.lookup_stream(mission_id, tc_stream_id)

    :ok = GenServer.stop(stream_pid)

    assert {:defer, :hold_pending_resync} ==
             send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)

    :ok = Stream.resync(tc_stream_id)
    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context)
  end

  test "distinct tc stream ids create distinct stream processes" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    frame_size = 32

    {interface, link_defaults} = build_interface(mission_id, interface_id, frame_size)
    send_fun = fn _bytes -> :ok end

    {:ok, _pid} = start_fop(mission_id, interface, 10, send_fun, link_defaults: link_defaults)
    {:ok, _pid} = start_fop(mission_id, interface, 11, send_fun, link_defaults: link_defaults)
    pdu = build_pdu()

    {framing_a, cop1_a, tc_stream_a} = cop1_contexts(mission_id, interface_id, 10, vcid: 0)
    {framing_b, cop1_b, tc_stream_b} = cop1_contexts(mission_id, interface_id, 11, vcid: 0)

    ingest_report(tc_stream_a, 0)
    ingest_report(tc_stream_b, 0)

    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_a, cop1_a)
    assert :ok == send_frames(mission_id, link_defaults, pdu, framing_b, cop1_b)

    {:ok, pid_a} = StreamSupervisor.lookup_stream(mission_id, tc_stream_a)
    {:ok, pid_b} = StreamSupervisor.lookup_stream(mission_id, tc_stream_b)

    assert pid_a != pid_b
  end

  defp build_interface(mission_id, interface_id, frame_size, opts \\ []) do
    cop1_overrides = Keyword.get(opts, :cop1, %{})

    link_defaults = %{
      "framing" => "sdlp",
      "sdlp" => %{
        "profile" => "tm",
        "uplink_profile" => "tc",
        "frame_size" => frame_size,
        "uplink_vcid" => 0,
        "sdu_mapping" => [
          %{
            "scid" => 0,
            "vcid" => 0,
            "direction" => "uplink",
            "type" => "space_packet"
          }
        ],
        "default_sdu_type" => "space_packet"
      },
      "cop1" =>
        Map.merge(
          %{
            "mode" => "fop",
            "window_size" => 1,
            "timeout_ms" => 50,
            "max_retransmit" => 2
          },
          cop1_overrides
        )
    }

    interface = %Interface{
      id: interface_id,
      mission_id: mission_id,
      name: "cop1-test",
      connection_type: :tcp_server,
      bind_address: "127.0.0.1",
      bind_port: 0,
      target_ids: [],
      config: %{}
    }

    {interface, link_defaults}
  end

  defp build_pdu do
    packet = %SpacePacket{
      apid: 1,
      sequence_flags: 3,
      sequence_count: 0,
      secondary_header_flag: 1,
      user_data: <<1, 2, 3>>
    }

    %PDU{
      type: :space_packet,
      value: packet,
      quality: :good,
      timestamp: nil,
      meta: %{}
    }
  end

  defp send_frames(mission_id, link_defaults, pdu, framing_context, cop1_context) do
    {:ok, frames} = build_frames(pdu, framing_context, link_defaults)

    channel_id =
      ChannelId.new(
        cop1_context.stream_id.scid,
        cop1_context.stream_id.vcid,
        cop1_context.stream_id.map_id
      )

    FOP.send_frames(mission_id, channel_id, frames, cop1_context)
  end

  defp ingest_report(%TCStreamId{} = tc_stream_id, report_value, opts \\ []) do
    status = Keyword.get(opts, :status, :accept)

    clcw =
      case Keyword.get(opts, :clcw) do
        %CLCW{} = clcw -> clcw
        _ -> %CLCW{vcid: tc_stream_id.vcid, report_value: report_value}
      end

    report = %Report{
      tc_stream_id: tc_stream_id,
      seq: report_value,
      status: status,
      raw: clcw
    }

    FOP.ingest_report(report)
    report
  end

  defp cop1_contexts(mission_id, interface_id, scid, opts \\ []) do
    vcid = Keyword.get(opts, :vcid, 0)
    tc_stream_id = TCStreamId.new!(mission_id, interface_id, scid, vcid)

    # Note: bypass_flag/control_command_flag/segment_header_flag are TC frame header bits
    # and are derived from segmentation config, not set on Context.
    # Use :bypass option for per-issuance emergency bypass mode.
    framing_attrs = %{
      scid: scid,
      vcid: vcid,
      stream_id: tc_stream_id,
      bypass_flag: Keyword.get(opts, :bypass_flag),
      control_command_flag: Keyword.get(opts, :control_command_flag),
      segment_header_flag: Keyword.get(opts, :segment_header_flag),
      initial_seq: Keyword.get(opts, :initial_seq)
    }

    # Convert bypass_flag to bypass boolean for COP1.Context
    bypass =
      case Keyword.get(opts, :bypass) do
        nil ->
          # Backward compat: if bypass_flag was set, treat as bypass mode
          Keyword.get(opts, :bypass_flag) == 1

        value ->
          value
      end

    cop1_attrs = %{
      stream_id: tc_stream_id,
      vcid: vcid,
      cop1_control: Keyword.get(opts, :cop1_control),
      bypass: bypass,
      correlation_id: Keyword.get(opts, :correlation_id)
    }

    {FramingContext.new(framing_attrs), Context.new(cop1_attrs), tc_stream_id}
  end

  defp start_fop(mission_id, interface, scid, send_fun, opts) do
    _ = ensure_started({StreamSupervisor, mission_id: mission_id})

    channel_id = ChannelId.new(scid, Keyword.get(opts, :vcid, 0))
    link_defaults = Keyword.fetch!(opts, :link_defaults)
    protocol_config = ProtocolConfig.effective_config(link_defaults, %{})

    release_fun = fn release -> send_fun.(release.bytes) end

    fop_opts =
      case Keyword.get(opts, :event_fun) do
        nil ->
          [
            mission_id: mission_id,
            channel_id: channel_id,
            protocol_config: protocol_config,
            release_fun: release_fun
          ]

        event_fun ->
          [
            mission_id: mission_id,
            channel_id: channel_id,
            protocol_config: protocol_config,
            release_fun: release_fun,
            event_fun: event_fun
          ]
      end

    _ =
      ensure_started(
        Supervisor.child_spec(
          {FOP, fop_opts},
          id: {:cop1_fop, mission_id, ChannelId.key(channel_id)}
        )
      )

    ensure_active_interface(mission_id, channel_id, interface.id)

    {:ok, pid} = fetch_fop_pid(mission_id, channel_id)
    {:ok, pid}
  end

  defp fetch_fop_pid(mission_id, %ChannelId{} = channel_id) do
    case Registry.lookup(
           Cadence.MissionRegistry,
           {:cop1_fop, mission_id, ChannelId.key(channel_id)}
         ) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp ensure_active_interface(mission_id, %ChannelId{} = channel_id, interface_id) do
    _ =
      ensure_started(
        Supervisor.child_spec(
          {LinkController, mission_id: mission_id, scid: channel_id.scid},
          id: {:link_controller, mission_id, channel_id.scid}
        )
      )

    binding = %Binding{
      mission_id: mission_id,
      channel_id: channel_id,
      interface_id: interface_id,
      direction: :uplink,
      role: :primary,
      priority: 0,
      desired_state: :active,
      observed_state: :active
    }

    :ok = LinkController.set_binding(binding)
    :ok = LinkController.interface_state(mission_id, channel_id.scid, interface_id, :up)
  end

  defp build_frames(%PDU{} = pdu, %FramingContext{} = context, link_defaults) do
    {:ok, %{opts: opts}} = SDLPConfig.fetch(link_defaults)
    context = FramingContext.with_defaults(context, opts)
    {ctx, stream_id} = build_frame_context(context, opts)
    seg_state = get_seg_state(stream_id, context)

    case FrameBuilder.build_frames(pdu, ctx, seg_state) do
      {:ok, frames, next_seg} ->
        put_seg_state(stream_id, next_seg)
        {:ok, frames}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_frame_context(%FramingContext{} = context, opts) do
    segmentation = opts[:segmentation] || %{}

    ctx =
      context
      |> framing_defaults(opts)
      |> Map.merge(framing_flags(context, segmentation))

    {ctx, context.stream_id || :default}
  end

  defp framing_defaults(%FramingContext{} = context, opts) do
    %{
      frame_size: context.frame_size || opts[:uplink_frame_size] || opts[:frame_size],
      scid: context.scid || opts[:uplink_scid],
      vcid: context.vcid || opts[:uplink_vcid],
      map_id: context.map_id || opts[:uplink_map_id]
    }
  end

  defp framing_flags(%FramingContext{} = context, segmentation) do
    %{
      bypass_flag: FramingContext.normalize_flag(context.bypass_flag, 0),
      control_command_flag: FramingContext.normalize_flag(context.control_command_flag, 0),
      segment_header_flag: context.segment_header_flag || segmentation[:segment_header_flag] || 1
    }
  end

  defp get_seg_state(stream_id, %FramingContext{} = context) do
    key = {:seg_state, stream_id}

    case Process.get(key) do
      nil ->
        {:ok, seg_state} = FrameBuilder.init_segmentation(frame_seq: context.initial_seq || 0)
        Process.put(key, seg_state)
        seg_state

      seg_state ->
        seg_state
    end
  end

  defp put_seg_state(stream_id, seg_state) do
    Process.put({:seg_state, stream_id}, seg_state)
  end

  defp ensure_started(child) do
    case start_supervised(child) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end
end
