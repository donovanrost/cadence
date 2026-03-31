defmodule CadenceSimulator.COP1.LoopbackPeerTest do
  use CadenceSimulator.Case, async: false

  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias CadenceSimulator.COP1.LoopbackPeer
  alias CadenceSimulator.TestSupport.FakeRuntimeResolver

  @tc_frame_size 16

  test "responds to TC uplink frames with matching CLCW report values" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: 0, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    on_exit(fn ->
      :gen_tcp.close(listener)
    end)

    {:ok, peer} =
      CadenceSimulator.start_cop1_loopback_peer(
        host: "127.0.0.1",
        port: port,
        tc_frame_size: @tc_frame_size
      )

    on_exit(fn ->
      if Process.alive?(peer), do: CadenceSimulator.stop_simulator(peer)
    end)

    {:ok, socket} = :gen_tcp.accept(listener)

    on_exit(fn ->
      :gen_tcp.close(socket)
    end)

    tc_seq = 7

    {:ok, tc_bytes} =
      TransferFrame.encode(
        %TransferFrame{
          version: 0,
          bypass_flag: 0,
          control_command_flag: 0,
          scid: 42,
          vcid: 3,
          frame_length: nil,
          frame_seq: tc_seq,
          segment_header_flag: 0,
          spare: 0,
          payload: :binary.copy(<<0xAA>>, @tc_frame_size - 5)
        },
        frame_size: @tc_frame_size
      )

    assert :ok = :gen_tcp.send(socket, tc_bytes)
    assert {:ok, clcw_binary} = :gen_tcp.recv(socket, 4, 1_000)
    assert {:ok, clcw} = CLCW.decode(clcw_binary)
    assert clcw.vcid == 3
    assert clcw.report_value == tc_seq

    assert_eventually(fn ->
      snapshot = LoopbackPeer.snapshot(peer)
      snapshot.tc_frame_count == 1 and snapshot.clcw_count == 1 and
        snapshot.last_tc_frame_seq == tc_seq and snapshot.last_clcw_report_value == tc_seq
    end)
  end

  test "applies scheduled CLCW overrides across successive TC frames" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, packet: 0, active: false, reuseaddr: true])
    {:ok, {_address, port}} = :inet.sockname(listener)

    on_exit(fn ->
      :gen_tcp.close(listener)
    end)

    {:ok, peer} =
      CadenceSimulator.start_cop1_loopback_peer(
        host: "127.0.0.1",
        port: port,
        tc_frame_size: @tc_frame_size,
        clcw_overrides: %{"lockout" => 1},
        clcw_schedule: [
          %{at: 0, overrides: %{"wait" => 1, "report_value" => 0}},
          %{at: 1, overrides: %{"wait" => 0, "report_value" => 8}}
        ]
      )

    on_exit(fn ->
      if Process.alive?(peer), do: CadenceSimulator.stop_simulator(peer)
    end)

    {:ok, socket} = :gen_tcp.accept(listener)

    on_exit(fn ->
      :gen_tcp.close(socket)
    end)

    assert :ok = :gen_tcp.send(socket, tc_frame_bytes(7))
    assert {:ok, clcw_binary_1} = :gen_tcp.recv(socket, 4, 1_000)
    assert {:ok, clcw_1} = CLCW.decode(clcw_binary_1)
    assert clcw_1.lockout == 1
    assert clcw_1.wait == 1
    assert clcw_1.report_value == 0

    assert :ok = :gen_tcp.send(socket, tc_frame_bytes(8))
    assert {:ok, clcw_binary_2} = :gen_tcp.recv(socket, 4, 1_000)
    assert {:ok, clcw_2} = CLCW.decode(clcw_binary_2)
    assert clcw_2.lockout == 1
    assert clcw_2.wait == 0
    assert clcw_2.report_value == 8

    assert_eventually(fn ->
      snapshot = LoopbackPeer.snapshot(peer)
      snapshot.tc_frame_count == 2 and snapshot.clcw_count == 2 and
        snapshot.last_tc_frame_seq == 8 and snapshot.last_clcw_report_value == 8
    end)
  end

  test "refreshes cadence runtime before connecting to a rotated uplink port" do
    {:ok, stale_listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_address, stale_port}} = :inet.sockname(stale_listener)
    :gen_tcp.close(stale_listener)

    {:ok, live_listener} = :gen_tcp.listen(0, [:binary, packet: 0, active: false, reuseaddr: true])
    {:ok, {_address, live_port}} = :inet.sockname(live_listener)
    {:ok, resolver} = Agent.start_link(fn -> [{:ok, [host: "127.0.0.1", port: live_port]}] end)

    on_exit(fn ->
      if Process.alive?(resolver), do: Agent.stop(resolver)
      :gen_tcp.close(live_listener)
    end)

    {:ok, peer} =
      CadenceSimulator.start_cop1_loopback_peer(
        host: "127.0.0.1",
        port: stale_port,
        tc_frame_size: @tc_frame_size,
        runtime_resolver: {FakeRuntimeResolver, :next, [resolver]}
      )

    on_exit(fn ->
      if Process.alive?(peer), do: CadenceSimulator.stop_simulator(peer)
    end)

    assert {:ok, socket} = :gen_tcp.accept(live_listener, 1_000)

    on_exit(fn ->
      :gen_tcp.close(socket)
    end)

    assert :ok = :gen_tcp.send(socket, tc_frame_bytes(9))
    assert {:ok, clcw_binary} = :gen_tcp.recv(socket, 4, 1_000)
    assert {:ok, clcw} = CLCW.decode(clcw_binary)
    assert clcw.report_value == 9

    assert_eventually(fn ->
      snapshot = LoopbackPeer.snapshot(peer)
      snapshot.connected? and snapshot.port == live_port and snapshot.tc_frame_count == 1
    end)
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(_fun, 0), do: flunk("condition was not satisfied in time")

  defp assert_eventually(fun, attempts) when is_function(fun, 0) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp tc_frame_bytes(tc_seq) do
    {:ok, tc_bytes} =
      TransferFrame.encode(
        %TransferFrame{
          version: 0,
          bypass_flag: 0,
          control_command_flag: 0,
          scid: 42,
          vcid: 3,
          frame_length: nil,
          frame_seq: tc_seq,
          segment_header_flag: 0,
          spare: 0,
          payload: :binary.copy(<<0xAA>>, @tc_frame_size - 5)
        },
        frame_size: @tc_frame_size
      )

    tc_bytes
  end
end
