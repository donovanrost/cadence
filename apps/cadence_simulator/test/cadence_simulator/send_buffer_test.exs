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
        Process.sleep(50)

        SendBuffer.send_packet(pid, "rotating")
        :ok = SendBuffer.flush(pid)

        assert SendBuffer.stats(pid).packets_dropped == 1
        assert {:ok, second_socket} = :gen_tcp.accept(second_live_listener, 1_000)

        on_exit(fn ->
          if Port.info(second_socket) != nil, do: :gen_tcp.close(second_socket)
        end)

        SendBuffer.send_packet(pid, "recovered")
        :ok = SendBuffer.flush(pid)

        assert {:ok, "recovered"} ==
                 :gen_tcp.recv(second_socket, byte_size("recovered"), 1_000)

        assert SendBuffer.stats(pid).output == "tcp:127.0.0.1:#{second_live_port}"
      end)

    assert log =~ "SendBuffer failed to connect to TCP"
    assert log =~ "SendBuffer flush failed: :closed, dropping 1 packets"
  end

  defp stop_buffer(pid) do
    SendBuffer.stop(pid)
  catch
    :exit, {:noproc, _call} -> :ok
  end
end
