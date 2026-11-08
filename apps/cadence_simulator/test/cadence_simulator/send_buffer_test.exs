defmodule CadenceSimulator.SendBufferTest do
  use CadenceSimulator.Case, async: true

  import ExUnit.CaptureLog

  alias CadenceSimulator.SendBuffer
  alias CadenceSimulator.TestSupport.FakeRuntimeResolver

  test "sends data through an attached socket in listen mode" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener)
    :gen_tcp.close(listener)

    {:ok, pid} =
      SendBuffer.start_link(
        output: {:tcp, "127.0.0.1", port},
        mode: :listen,
        batch_timeout: 1_000,
        batch_size: 1_024
      )

    on_exit(fn ->
      stop_buffer(pid)
      :gen_tcp.close(client)
      :gen_tcp.close(server)
    end)

    SendBuffer.attach_socket(pid, server)
    SendBuffer.send_packet(pid, "abc")
    :ok = SendBuffer.flush(pid)

    assert {:ok, "abc"} == :gen_tcp.recv(client, 3, 1_000)
  end

  test "grows batch size after a full size-triggered flush" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener)
    :gen_tcp.close(listener)

    {:ok, pid} =
      SendBuffer.start_link(
        output: {:tcp, "127.0.0.1", port},
        mode: :listen,
        batch_timeout: 1_000,
        batch_size: 4
      )

    on_exit(fn ->
      stop_buffer(pid)
      :gen_tcp.close(client)
      :gen_tcp.close(server)
    end)

    SendBuffer.attach_socket(pid, server)

    status = SendBuffer.buffer_packets(pid, ["ab", "cd"], 4)
    stats = SendBuffer.stats(pid)

    assert status.packets_buffered == 0
    assert status.buffer_bytes == 0
    assert {:ok, "abcd"} == :gen_tcp.recv(client, 4, 1_000)
    assert stats.flushes == 1
    assert stats.batch_size == 8
    assert stats.base_batch_size == 4
    assert stats.max_batch_size == 16
  end

  test "publishes sent counters to the coordinator after a size-triggered flush" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener)
    :gen_tcp.close(listener)

    {:ok, pid} =
      SendBuffer.start_link(
        output: {:tcp, "127.0.0.1", port},
        mode: :listen,
        coordinator_pid: self(),
        batch_timeout: 1_000,
        batch_size: 4
      )

    on_exit(fn ->
      stop_buffer(pid)
      :gen_tcp.close(client)
      :gen_tcp.close(server)
    end)

    SendBuffer.attach_socket(pid, server)

    status = SendBuffer.buffer_packets(pid, ["ab", "cd"], 4)

    assert status.packets_buffered == 0
    assert status.buffer_bytes == 0
    assert status.packets_sent == 2
    assert status.bytes_sent == 4
    assert status.flushes == 1

    assert_receive {:send_buffer_status, published_status}, 1_000
    assert published_status.packets_buffered == 0
    assert published_status.buffer_bytes == 0
    assert published_status.packets_sent == 2
    assert published_status.bytes_sent == 4
    assert published_status.flushes == 1

    assert {:ok, "abcd"} == :gen_tcp.recv(client, 4, 1_000)
  end

  test "refreshes runtime output before reconnecting to a stale TCP port" do
    log =
      capture_log(fn ->
        {:ok, stale_listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
        {:ok, stale_port} = :inet.port(stale_listener)
        :gen_tcp.close(stale_listener)

        {:ok, first_live_listener} =
          :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])

        {:ok, first_live_port} = :inet.port(first_live_listener)

        {:ok, second_live_listener} =
          :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])

        {:ok, second_live_port} = :inet.port(second_live_listener)

        {:ok, resolver} =
          Agent.start_link(fn ->
            [
              {:ok, [output: {:tcp, "127.0.0.1", first_live_port}]},
              {:ok, [output: {:tcp, "127.0.0.1", second_live_port}]}
            ]
          end)

        {:ok, pid} =
          SendBuffer.start_link(
            output: {:tcp, "127.0.0.1", stale_port},
            runtime_resolver: {FakeRuntimeResolver, :next, [resolver]},
            batch_timeout: 1_000,
            batch_size: 1_024
          )

        on_exit(fn ->
          stop_buffer(pid)
          if Process.alive?(resolver), do: Agent.stop(resolver)
          :gen_tcp.close(first_live_listener)
          :gen_tcp.close(second_live_listener)
        end)

        assert {:ok, first_socket} = :gen_tcp.accept(first_live_listener, 1_000)

        on_exit(fn ->
          if Port.info(first_socket) != nil, do: :gen_tcp.close(first_socket)
        end)

        SendBuffer.send_packet(pid, "first")
        :ok = SendBuffer.flush(pid)
        assert {:ok, "first"} == :gen_tcp.recv(first_socket, byte_size("first"), 1_000)

        assert :ok = :inet.setopts(first_socket, linger: {true, 0})
        :gen_tcp.close(first_socket)

        # Reconnect must happen without sacrificing the next generated packet.
        assert {:ok, second_socket} = :gen_tcp.accept(second_live_listener, 1_000)

        SendBuffer.send_packet(pid, "rotating")
        :ok = SendBuffer.flush(pid)

        assert SendBuffer.stats(pid).packets_dropped == 0
        assert {:ok, "rotating"} == :gen_tcp.recv(second_socket, 8, 1_000)

        on_exit(fn ->
          if Port.info(second_socket) != nil, do: :gen_tcp.close(second_socket)
        end)

        SendBuffer.send_packet(pid, "recovered")
        :ok = SendBuffer.flush(pid)

        assert {:ok, "recovered"} ==
                 :gen_tcp.recv(second_socket, byte_size("recovered"), 1_000)

        assert SendBuffer.stats(pid).output == "tcp:127.0.0.1:#{second_live_port}"
        assert SendBuffer.stats(pid).disconnects == 1
      end)

    assert log =~ "SendBuffer failed to connect to TCP"
    refute log =~ "dropping"
  end

  test "reconnects on a peer FIN without waiting for another packet or send failure" do
    {listener, port} = listen()
    pid = start_buffer(port)
    {:ok, first} = :gen_tcp.accept(listener, 1_000)

    # Keep the peer's read side open: this previously left the sender in
    # CLOSE_WAIT, happily accepting writes into its local socket buffers.
    :ok = :gen_tcp.shutdown(first, :write)
    assert {:ok, second} = :gen_tcp.accept(listener, 1_000)
    assert {:error, :closed} = :gen_tcp.recv(first, 0, 1_000)

    SendBuffer.send_packet(pid, "after-fin")
    :ok = SendBuffer.flush(pid)
    assert {:ok, "after-fin"} = :gen_tcp.recv(second, 9, 1_000)
    assert %{connections: 2, disconnects: 1, packets_dropped: 0} = SendBuffer.stats(pid)
  end

  test "continues observing closure after receiving peer data" do
    {listener, port} = listen()
    pid = start_buffer(port)
    {:ok, first} = :gen_tcp.accept(listener, 1_000)

    :ok = :gen_tcp.send(first, "peer response")
    :ok = :gen_tcp.shutdown(first, :write)
    assert {:ok, second} = :gen_tcp.accept(listener, 1_000)

    SendBuffer.send_packet(pid, "rearmed")
    :ok = SendBuffer.flush(pid)
    assert {:ok, "rearmed"} = :gen_tcp.recv(second, 7, 1_000)
  end

  @tag :capture_log
  test "retries an initially unavailable endpoint without traffic and drains retained packets" do
    {listener, port} = listen()
    :ok = :gen_tcp.close(listener)
    pid = start_buffer(port, batch_size: 2)

    SendBuffer.buffer_packets(pid, ["a", "b"])
    SendBuffer.buffer_packets(pid, ["c"])
    :ok = SendBuffer.flush(pid)
    await(fn -> SendBuffer.stats(pid).connection_attempts >= 3 end)
    assert %{packets_buffered: 3, packets_dropped: 0, packets_sent: 0} = SendBuffer.stats(pid)

    {listener, ^port} = listen(port)
    assert {:ok, socket} = :gen_tcp.accept(listener, 1_000)
    assert {:ok, "abc"} = :gen_tcp.recv(socket, 3, 1_000)

    assert %{packets_buffered: 0, packets_sent: 3, reconnect_pending?: false} =
             SendBuffer.stats(pid)
  end

  @tag :capture_log
  test "buffers across a sustained disconnect and reports overflow without evicting older packets" do
    {listener, port} = listen()
    pid = start_buffer(port, max_buffer_bytes: 5, coordinator_pid: self())
    {:ok, first} = :gen_tcp.accept(listener, 1_000)
    :ok = :gen_tcp.close(listener)
    :ok = :gen_tcp.close(first)
    await(fn -> SendBuffer.stats(pid).connection_attempts >= 3 end)

    assert %{packets_buffered: 1, buffer_bytes: 3} = SendBuffer.buffer_packets(pid, ["abc"])
    assert %{packets_dropped: 1, buffer_bytes: 3} = SendBuffer.buffer_packets(pid, ["def"])
    assert_receive {:send_buffer_status, %{packets_dropped: 1}}, 1_000
    SendBuffer.buffer_packets(pid, ["g", "h"])
    :ok = SendBuffer.flush(pid)
    assert %{packets_buffered: 3, buffer_bytes: 5, packets_dropped: 1} = SendBuffer.stats(pid)

    {listener, ^port} = listen(port)
    assert {:ok, second} = :gen_tcp.accept(listener, 1_000)
    assert {:ok, "abcgh"} = :gen_tcp.recv(second, 5, 1_000)
    assert %{packets_sent: 3, packets_dropped: 1, buffer_bytes: 0} = SendBuffer.stats(pid)
  end

  test "ignores stale socket and reconnect notifications after replacement" do
    {listener, port} = listen()
    pid = start_buffer(port)
    {:ok, first} = :gen_tcp.accept(listener, 1_000)
    old_socket = :sys.get_state(pid).socket
    :ok = :gen_tcp.close(first)
    assert {:ok, second} = :gen_tcp.accept(listener, 1_000)

    send(pid, {:tcp_closed, old_socket})
    send(pid, {:tcp_error, old_socket, :econnreset})
    send(pid, {:tcp, old_socket, "late"})
    send(pid, {:timeout, make_ref(), :reconnect})
    SendBuffer.send_packet(pid, "still-connected")
    :ok = SendBuffer.flush(pid)

    assert {:ok, "still-connected"} = :gen_tcp.recv(second, 15, 1_000)
    assert %{connections: 2, disconnects: 1, reconnect_pending?: false} = SendBuffer.stats(pid)
  end

  @tag :capture_log
  test "counts a failed attached-socket send without reconnecting or replaying an ambiguous batch" do
    {listener, port} = listen()
    {:ok, client} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(listener, 1_000)
    pid = start_buffer(port, mode: :listen)
    SendBuffer.attach_socket(pid, server)
    :ok = :gen_tcp.close(server)

    SendBuffer.buffer_packets(pid, ["uncertain"])
    :ok = SendBuffer.flush(pid)

    assert %{packets_dropped: 1, packets_sent: 0, reconnect_pending?: false} =
             SendBuffer.stats(pid)

    # The next caller-owned socket can drain only the unsent, retained batch.
    SendBuffer.buffer_packets(pid, ["retained"])
    {:ok, replacement} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    {:ok, accepted} = :gen_tcp.accept(listener, 1_000)
    SendBuffer.attach_socket(pid, accepted)
    :ok = SendBuffer.flush(pid)
    assert {:ok, "retained"} = :gen_tcp.recv(replacement, 8, 1_000)

    SendBuffer.detach_socket(pid)
    :ok = SendBuffer.flush(pid)
    :ok = :gen_tcp.send(accepted, "owned-by-caller")
    assert {:ok, "owned-by-caller"} = :gen_tcp.recv(replacement, 15, 1_000)
    :gen_tcp.close(client)
  end

  defp listen(port \\ 0) do
    {:ok, listener} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)
    {listener, port}
  end

  defp start_buffer(port, opts \\ []) do
    start_supervised!(
      {SendBuffer,
       Keyword.merge(
         [output: {:tcp, "127.0.0.1", port}, reconnect_interval: 25, batch_timeout: 10],
         opts
       )}
    )
  end

  defp await(condition, attempts \\ 100)
  defp await(condition, 0), do: assert(condition.())

  defp await(condition, attempts) do
    unless condition.() do
      Process.sleep(10)
      await(condition, attempts - 1)
    end
  end

  defp stop_buffer(pid) do
    SendBuffer.stop(pid)
  catch
    :exit, {:noproc, _call} -> :ok
  end
end
