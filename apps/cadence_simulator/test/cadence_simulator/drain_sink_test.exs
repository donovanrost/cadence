defmodule CadenceSimulator.DrainSinkTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.DrainSink

  test "accepts tcp input and reports byte and chunk counters" do
    port = unique_tcp_port()
    {:ok, sink} = DrainSink.start_link(host: "127.0.0.1", port: port)

    {:ok, socket} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw, nodelay: true])

    :ok = :gen_tcp.send(socket, "hello")
    :ok = :gen_tcp.send(socket, "world")

    assert_eventually(fn ->
      stats = DrainSink.stats(sink)

      stats.bytes_received >= 10 and
        stats.chunks_received >= 1 and
        stats.accepted_connections == 1 and
        stats.open_connections == 1
    end)

    :ok = :gen_tcp.close(socket)

    assert_eventually(fn ->
      stats = DrainSink.stats(sink)
      stats.closed_connections == 1 and stats.open_connections == 0
    end)
  end

  defp unique_tcp_port do
    45_000 + rem(System.unique_integer([:positive]), 10_000)
  end

  defp assert_eventually(fun, attempts \\ 30)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      assert true
    else
      Process.sleep(20)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition did not become true")
end
