defmodule Cadence.Simulator.SendBufferTest do
  use Cadence.PureCase, async: true

  alias Cadence.Simulator.SendBuffer

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
      if Process.alive?(pid), do: SendBuffer.stop(pid)
      :gen_tcp.close(client)
      :gen_tcp.close(server)
    end)

    SendBuffer.attach_socket(pid, server)
    SendBuffer.send_packet(pid, "abc")
    :ok = SendBuffer.flush(pid)

    assert {:ok, "abc"} == :gen_tcp.recv(client, 3, 1_000)
  end

  test "sends packet batches through an attached socket in listen mode" do
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
      if Process.alive?(pid), do: SendBuffer.stop(pid)
      :gen_tcp.close(client)
      :gen_tcp.close(server)
    end)

    SendBuffer.attach_socket(pid, server)
    SendBuffer.send_packets(pid, ["ab", "cd", "ef"], 6)
    :ok = SendBuffer.flush(pid)

    assert {:ok, "abcdef"} == :gen_tcp.recv(client, 6, 1_000)
  end

  test "buffers packet batches synchronously and reports backlog" do
    {:ok, pid} =
      SendBuffer.start_link(
        output: nil,
        batch_timeout: 1_000,
        batch_size: 1_024
      )

    on_exit(fn ->
      if Process.alive?(pid), do: SendBuffer.stop(pid)
    end)

    status = SendBuffer.buffer_packets(pid, ["ab", "cd"], 4)
    stats = SendBuffer.stats(pid)

    assert status.packets_buffered == 2
    assert status.buffer_bytes == 4
    assert stats.packets_buffered == 2
    assert stats.buffer_bytes == 4
  end

  test "arms the flush timer only while packets are buffered" do
    {:ok, pid} =
      SendBuffer.start_link(
        output: nil,
        batch_timeout: 1_000,
        batch_size: 1_024
      )

    on_exit(fn ->
      if Process.alive?(pid), do: SendBuffer.stop(pid)
    end)

    assert :sys.get_state(pid).timer_ref == nil

    _status = SendBuffer.buffer_packets(pid, ["ab"], 2)
    assert :sys.get_state(pid).timer_ref != nil

    :ok = SendBuffer.flush(pid)
    assert :sys.get_state(pid).timer_ref == nil
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
      if Process.alive?(pid), do: SendBuffer.stop(pid)
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
end
