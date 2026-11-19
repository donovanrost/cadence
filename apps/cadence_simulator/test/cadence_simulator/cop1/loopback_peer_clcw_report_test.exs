defmodule CadenceSimulator.COP1.LoopbackPeerCLCWReportTest do
  @moduledoc """
  #38 / DECISIONS #59 follow-up: the peer reports its CLCW periodically, as a spacecraft does in
  every downlink frame, so one lost report can't strand the ground's FOP.
  """
  use CadenceSimulator.Case, async: false

  alias CCSDS.Transport.COP1.CLCW

  test "the peer reports its CLCW on connect and then every interval, on each connection" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, packet: 0])
    {:ok, {_address, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    {:ok, peer} =
      CadenceSimulator.start_cop1_loopback_peer(
        host: "127.0.0.1",
        port: port,
        tc_frame_size: 16,
        clcw_report_interval_ms: 50,
        reconnect_interval_ms: 20
      )

    on_exit(fn -> if Process.alive?(peer), do: CadenceSimulator.stop_simulator(peer) end)

    {:ok, socket} = :gen_tcp.accept(listener, 2_000)
    assert [%CLCW{} | _] = clcws(socket, 3)

    # A dropped connection stops the reports; the next connection starts them again.
    :gen_tcp.close(socket)
    {:ok, socket} = :gen_tcp.accept(listener, 2_000)
    assert length(clcws(socket, 2)) == 2
  end

  # Reads `count` 4-byte CLCWs (each arrives within a few intervals).
  defp clcws(socket, count) do
    for _ <- 1..count do
      {:ok, <<word::binary-size(4)>>} = :gen_tcp.recv(socket, 4, 1_000)
      {:ok, clcw} = CLCW.decode(word)
      clcw
    end
  end
end
