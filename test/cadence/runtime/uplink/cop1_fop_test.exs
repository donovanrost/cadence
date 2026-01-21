defmodule Cadence.Runtime.Transport.COP1.FOPTest do
  use Cadence.PureCase

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Telemetry.UplinkPipeline
  alias Cadence.Runtime.Transport.COP1.{Context, FOP, StreamSupervisor}
  alias Cadence.Runtime.Uplink.{FramingContext, TCFraming}

  setup_mission_registry()

  test "acks frames when CLCW report value advances" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    target_id = Cadence.PureCase.random_id()
    frame_size = 32

    interface = build_interface(mission_id, interface_id, frame_size)

    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, send_fun)

    pdu = build_pdu()

    {framing_context, cop1_context} = cop1_contexts(target_id, interface_id, 10)

    assert :ok ==
             send_frames(mission_id, interface_id, pdu, framing_context, cop1_context)

    assert_receive {:sent, bytes}

    {:ok, [frame], _rest} = TransferFrame.decode(bytes, frame_size: frame_size)
    assert frame.frame_seq == 0

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 1

    clcw = %CLCW{report_value: frame.frame_seq, vcid: frame.vcid}
    :ok = FOP.ingest_clcw(mission_id, interface_id, clcw)
    Process.sleep(10)

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 0
  end

  test "retransmits on timeout" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    target_id = Cadence.PureCase.random_id()
    frame_size = 32

    interface = build_interface(mission_id, interface_id, frame_size)

    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, send_fun)

    pdu = build_pdu()

    {framing_context, cop1_context} = cop1_contexts(target_id, interface_id, 11)

    assert :ok ==
             send_frames(mission_id, interface_id, pdu, framing_context, cop1_context)

    assert_receive {:sent, bytes}

    {:ok, [frame], _rest} = TransferFrame.decode(bytes, frame_size: frame_size)

    send(pid, {:fop_timeout, frame.frame_seq})
    assert_receive {:sent, ^bytes}

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 1
  end

  test "bypass frames are sent without COP-1 tracking" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    target_id = Cadence.PureCase.random_id()
    frame_size = 32

    interface = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, send_fun)

    pdu = build_pdu()

    {framing_context, cop1_context} = cop1_contexts(target_id, interface_id, 12, bypass_flag: 1)

    assert :ok ==
             send_frames(mission_id, interface_id, pdu, framing_context, cop1_context)

    assert_receive {:sent, _bytes}

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 0
    assert stats.pending_count == 0
  end

  test "unlock control command is allowed during lockout" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    target_id = Cadence.PureCase.random_id()
    frame_size = 32

    interface = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, send_fun)

    lockout = %CLCW{lockout: 1, vcid: 0, report_value: 0}
    :ok = FOP.ingest_clcw(mission_id, interface_id, lockout)

    pdu = build_pdu()

    {framing_context, cop1_context} = cop1_contexts(target_id, interface_id, 10)

    assert {:error, :lockout} ==
             send_frames(mission_id, interface_id, pdu, framing_context, cop1_context)

    framing_context = FramingContext.new(%{scid: 10, vcid: 0, stream_id: target_id})
    cop1_context = Context.new(%{vcid: 0, cop1_control: :unlock, stream_id: target_id})

    assert :ok == send_frames(mission_id, interface_id, pdu, framing_context, cop1_context)

    assert_receive {:sent, _bytes}

    stats = FOP.stats(pid)
    assert stats.lockout == true
    assert stats.unlock_pending == true
    assert stats.in_flight_count == 0
  end

  test "rejects out-of-window report values" do
    mission_id = Cadence.PureCase.random_id()
    interface_id = Cadence.PureCase.random_id()
    target_id = Cadence.PureCase.random_id()
    frame_size = 32

    interface = build_interface(mission_id, interface_id, frame_size)
    test_pid = self()

    send_fun = fn bytes ->
      send(test_pid, {:sent, bytes})
      :ok
    end

    {:ok, pid} = start_fop(mission_id, interface, send_fun)

    pdu = build_pdu()

    {framing_context, cop1_context} = cop1_contexts(target_id, interface_id, 10)

    assert :ok == send_frames(mission_id, interface_id, pdu, framing_context, cop1_context)

    assert_receive {:sent, bytes}
    {:ok, [frame], _rest} = TransferFrame.decode(bytes, frame_size: frame_size)

    bad_clcw = %CLCW{report_value: rem(frame.frame_seq + 1, 256), vcid: frame.vcid}
    :ok = FOP.ingest_clcw(mission_id, interface_id, bad_clcw)
    Process.sleep(10)

    stats = FOP.stats(pid)
    assert stats.in_flight_count == 1
    assert stats.last_report_value == nil
  end

  defp build_interface(mission_id, interface_id, frame_size) do
    %Interface{
      id: interface_id,
      mission_id: mission_id,
      name: "cop1-test",
      connection_type: :tcp_server,
      bind_address: "127.0.0.1",
      bind_port: 0,
      target_ids: [],
      config: %{
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
        "cop1" => %{
          "mode" => "fop",
          "window_size" => 1,
          "timeout_ms" => 50,
          "max_retransmit" => 2
        }
      }
    }
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

  defp send_frames(mission_id, interface_id, pdu, framing_context, cop1_context) do
    {:ok, frames} = TCFraming.build_frames(mission_id, interface_id, pdu, framing_context)
    FOP.send_frames(mission_id, interface_id, frames, cop1_context)
  end

  defp cop1_contexts(target_id, _interface_id, scid, opts \\ []) do
    vcid = Keyword.get(opts, :vcid, 0)

    framing_attrs = %{
      scid: scid,
      vcid: vcid,
      stream_id: target_id,
      bypass_flag: Keyword.get(opts, :bypass_flag),
      control_command_flag: Keyword.get(opts, :control_command_flag),
      segment_header_flag: Keyword.get(opts, :segment_header_flag),
      initial_seq: Keyword.get(opts, :initial_seq)
    }

    cop1_attrs = %{
      stream_id: target_id,
      vcid: vcid,
      bypass_flag: Keyword.get(opts, :bypass_flag),
      control_command_flag: Keyword.get(opts, :control_command_flag),
      segment_header_flag: Keyword.get(opts, :segment_header_flag),
      cop1_control: Keyword.get(opts, :cop1_control),
      bypass: Keyword.get(opts, :bypass),
      correlation_id: Keyword.get(opts, :correlation_id),
      initial_seq: Keyword.get(opts, :initial_seq)
    }

    {FramingContext.new(framing_attrs), Context.new(cop1_attrs)}
  end

  defp start_fop(mission_id, interface, send_fun) do
    {:ok, _sup} =
      start_supervised({StreamSupervisor, mission_id: mission_id, interface_id: interface.id})

    {:ok, _uplink} =
      start_supervised({UplinkPipeline, interface: interface, send_fun: send_fun})

    {:ok, _framing} =
      start_supervised({TCFraming, interface: interface})

    start_supervised({FOP, interface: interface})
  end
end
