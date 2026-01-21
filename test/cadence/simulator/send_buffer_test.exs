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
end
