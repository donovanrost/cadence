defmodule CadenceSimulator.CoordinatorParallelTest do
  use CadenceSimulator.Case, async: false

  alias Cadence.CCSDS.SDLP.TM.FrameCodec
  alias CadenceSimulator.Coordinator
  alias CadenceSimulator.Providers.DatabaseDynamics
  alias CadenceSimulator.TestSupport.SlowCounterProvider

  @definitions """
  version: "1.0.0"
  packets:
    - name: HK
      apid: 1
      items:
        - name: uptime_seconds
          bit_offset: 0
          bit_size: 16
          data_type: uint
          endianness: big
  """

  test "parallel mode batches generated packets into the send buffer" do
    {:ok, pid} =
      Coordinator.start_link(
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_content: @definitions,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 2,
        send_batch_timeout: 1_000
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    assert_eventually(fn ->
      stats = Coordinator.stats(pid)

      stats.parallel_mode == :parallel and stats.packet_count > 0 and
        stats.send_buffer_stats.packets_buffered > 0
    end)
  end

  test "parallel request with one generator behaves sequentially" do
    {:ok, pid} =
      Coordinator.start_link(
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_content: @definitions,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 1,
        send_batch_timeout: 1_000
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    assert_eventually(fn ->
      stats = Coordinator.stats(pid)

      stats.parallel_mode == :sequential and
        stats.packet_count > 0 and
        stats.send_buffer_stats.packets_buffered > 0 and
        not Map.has_key?(stats, :parallel_delivery_mode)
    end)
  end

  test "tm framing with one generator matches sequential output bytes" do
    frame_size = 32

    {:ok, sequential_pid} =
      Coordinator.start_link(
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_content: @definitions,
        provider: DatabaseDynamics,
        send_batch_timeout: 1_000,
        frame: %{format: :tm, frame_size: frame_size, scid: 11, vcid: 2}
      )

    {:ok, one_generator_pid} =
      Coordinator.start_link(
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_content: @definitions,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 1,
        send_batch_timeout: 1_000,
        frame: %{format: :tm, frame_size: frame_size, scid: 11, vcid: 2}
      )

    on_exit(fn ->
      if Process.alive?(sequential_pid), do: Coordinator.stop(sequential_pid)
      if Process.alive?(one_generator_pid), do: Coordinator.stop(one_generator_pid)
    end)

    assert_eventually(fn ->
      buffered_frame_count(sequential_pid) >= 4 and buffered_frame_count(one_generator_pid) >= 4
    end)

    assert first_buffered_bytes(sequential_pid, 4 * frame_size) ==
             first_buffered_bytes(one_generator_pid, 4 * frame_size)
  end

  test "tm framing keeps parallel generation and emits ordered frame sequences" do
    frame_size = 32

    {:ok, pid} =
      Coordinator.start_link(
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_content: @definitions,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 2,
        send_batch_timeout: 1_000,
        frame: %{format: :tm, frame_size: frame_size, scid: 11, vcid: 2}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    assert_eventually(fn ->
      stats = Coordinator.stats(pid)

      stats.parallel_mode == :parallel and
        stats.parallel_delivery_mode == :ordered_framer and
        stats.packet_count > 0 and
        stats.send_buffer_stats.packets_buffered >= 2
    end)

    coordinator_state = :sys.get_state(pid)
    send_buffer_state = :sys.get_state(coordinator_state.send_buffer)
    buffered_frames = send_buffer_state.buffer |> Enum.reverse() |> IO.iodata_to_binary()

    assert {:ok, frames, <<>>} =
             FrameCodec.decode(buffered_frames, frame_size: frame_size, ocf_length: 0)

    frame_seqs = Enum.map(frames, & &1.frame_seq)
    assert frame_seqs == Enum.to_list(0..(length(frame_seqs) - 1))
  end

  test "tm parallel framing plans frames in workers and preserves ordered frame sequences" do
    frame_size = 32

    {:ok, pid} =
      Coordinator.start_link(
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_content: @definitions,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        tm_parallel_framing: true,
        generator_count: 2,
        send_batch_timeout: 1_000,
        frame: %{format: :tm, frame_size: frame_size, scid: 11, vcid: 2}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    assert_eventually(fn ->
      stats = Coordinator.stats(pid)

      stats.parallel_mode == :parallel and
        stats.parallel_delivery_mode == :ordered_frame_plan and
        stats.packet_count > 0 and
        stats.send_buffer_stats.packets_buffered >= 2
    end)

    coordinator_state = :sys.get_state(pid)
    send_buffer_state = :sys.get_state(coordinator_state.send_buffer)
    buffered_frames = send_buffer_state.buffer |> Enum.reverse() |> IO.iodata_to_binary()

    assert {:ok, frames, <<>>} =
             FrameCodec.decode(buffered_frames, frame_size: frame_size, ocf_length: 0)

    frame_seqs = Enum.map(frames, & &1.frame_seq)
    assert frame_seqs == Enum.to_list(0..(length(frame_seqs) - 1))
  end

  test "high-rate parallel dispatch engages multiple workers" do
    {:ok, pid} =
      Coordinator.start_link(
        target_id: "SIM-1",
        rate_hz: 100_000.0,
        output: nil,
        definitions_content: @definitions,
        provider: SlowCounterProvider,
        provider_config: %{sleep_ms: 25},
        parallel_mode: :parallel,
        generator_count: 4,
        send_batch_timeout: 1_000
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    assert_eventually(fn ->
      state = :sys.get_state(pid)

      state.parallel_mode == :parallel and
        state.in_flight_steps > 0 and
        length(state.idle_workers) <= 1
    end)
  end

  defp buffered_frame_count(pid) do
    coordinator_state = :sys.get_state(pid)
    send_buffer_state = :sys.get_state(coordinator_state.send_buffer)
    div(IO.iodata_length(Enum.reverse(send_buffer_state.buffer)), 32)
  end

  defp first_buffered_bytes(pid, byte_count) do
    coordinator_state = :sys.get_state(pid)
    send_buffer_state = :sys.get_state(coordinator_state.send_buffer)
    buffered = send_buffer_state.buffer |> Enum.reverse() |> IO.iodata_to_binary()
    binary_part(buffered, 0, byte_count)
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
end
