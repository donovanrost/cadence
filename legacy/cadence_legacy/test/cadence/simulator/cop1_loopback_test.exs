defmodule Cadence.Simulator.COP1LoopbackTest do
  use Cadence.PureCase, async: false

  setup_mission_registry()
  setup_virtual_time()

  alias Cadence.CCSDS.SDLP.TM.FrameCodec
  alias Cadence.CCSDS.TC.TransferFrame
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Harness.Time
  alias Cadence.Simulator.Coordinator

  @tm_frame_size 256
  @tc_frame_size 16

  test "emits CLCW report value after TC uplink" do
    mission_id = random_id()
    port = find_open_port()

    {:ok, sim_pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 1.0,
        output: {:tcp, "127.0.0.1", port},
        mode: :listen,
        definitions_path: "priv/databases/example_telemetry.yaml",
        frame: %{format: :tm, scid: 42, vcid: 0, frame_size: @tm_frame_size},
        uplink_frame: %{format: :tc, frame_size: @tc_frame_size},
        clcw_enabled: true
      )

    on_exit(fn ->
      if Process.alive?(sim_pid), do: Coordinator.stop(sim_pid)
    end)

    {:ok, socket} = connect_with_retry(port, 10)
    on_exit(fn -> :gen_tcp.close(socket) end)

    tc_seq = 7

    payload = :binary.copy(<<0xAA>>, @tc_frame_size - 5)

    {:ok, tc_bytes} =
      TransferFrame.encode(
        %TransferFrame{
          version: 0,
          bypass_flag: 0,
          control_command_flag: 0,
          scid: 42,
          vcid: 0,
          frame_length: nil,
          frame_seq: tc_seq,
          segment_header_flag: 0,
          spare: 0,
          payload: payload
        },
        frame_size: @tc_frame_size
      )

    :ok = :gen_tcp.send(socket, tc_bytes)
    assert wait_for_farm(sim_pid, tc_seq)

    :ok = Time.advance(1000)

    frame_bytes = recv_exact!(socket, @tm_frame_size, 1_000)

    assert {:ok, [frame], <<>>} =
             FrameCodec.decode(frame_bytes,
               frame_size: @tm_frame_size,
               ocf_length: 4
             )

    assert {:ok, clcw} = CLCW.decode(frame.ocf)
    assert clcw.report_value == tc_seq
  end

  defp wait_for_farm(sim_pid, expected_seq) do
    wait_for(fn ->
      case :sys.get_state(sim_pid) do
        %{farm: %{report_value: ^expected_seq}} -> true
        _ -> false
      end
    end)
  end

  defp wait_for(fun, timeout_ms \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for(fun, deadline)
  end

  defp do_wait_for(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(10)
        do_wait_for(fun, deadline)
      else
        false
      end
    end
  end

  defp recv_exact!(socket, size, timeout) do
    case recv_exact(socket, size, timeout, <<>>) do
      {:ok, data} -> data
      {:error, reason} -> raise "failed to receive #{size} bytes: #{inspect(reason)}"
    end
  end

  defp recv_exact(_socket, 0, _timeout, acc), do: {:ok, acc}

  defp recv_exact(socket, remaining, timeout, acc) do
    case :gen_tcp.recv(socket, remaining, timeout) do
      {:ok, data} ->
        recv_exact(socket, remaining - byte_size(data), timeout, acc <> data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect_with_retry(port, attempts) when attempts > 0 do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false]) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, _reason} ->
        Process.sleep(25)
        connect_with_retry(port, attempts - 1)
    end
  end

  defp connect_with_retry(_port, _attempts), do: {:error, :connect_failed}

  defp find_open_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
