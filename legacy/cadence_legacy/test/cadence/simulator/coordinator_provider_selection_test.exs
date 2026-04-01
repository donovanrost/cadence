defmodule Cadence.Simulator.CoordinatorProviderSelectionTest do
  use Cadence.PureCase, async: false

  setup_mission_registry()
  setup_virtual_time()

  alias Cadence.Harness.Time
  alias Cadence.Simulator.Coordinator
  alias Cadence.Simulator.Providers.{BasicDynamics, DatabaseDynamics, ScenarioProvider}
  alias Cadence.Simulator.SendBuffer

  @definitions_path "priv/databases/example_telemetry.yaml"
  @scenario_path "priv/scenarios/battery_low.yaml"

  test "defaults to BasicDynamics even when definitions are provided" do
    mission_id = random_id()

    {:ok, pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 1.0,
        output: nil,
        definitions_path: @definitions_path
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    state = :sys.get_state(pid)

    assert state.provider_module == BasicDynamics
    assert state.parallel_mode == :sequential
  end

  test "uses DatabaseDynamics only when explicitly requested" do
    mission_id = random_id()

    {:ok, pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 1.0,
        output: nil,
        definitions_path: @definitions_path,
        provider: DatabaseDynamics
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    state = :sys.get_state(pid)

    assert state.provider_module == DatabaseDynamics
  end

  test "falls back to sequential mode for non-parallel-safe providers" do
    mission_id = random_id()

    {:ok, pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 10.0,
        output: nil,
        definitions_path: @definitions_path,
        scenario_path: @scenario_path,
        parallel_mode: :parallel,
        generator_count: 4
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    state = :sys.get_state(pid)

    assert state.provider_module == ScenarioProvider
    assert state.parallel_mode == :sequential
  end

  test "parallel mode batches generated packets into the send buffer" do
    mission_id = random_id()

    {:ok, pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_path: @definitions_path,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 2,
        send_batch_timeout: 1_000
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    :ok = Time.advance(1)

    assert wait_for(fn ->
             state = :sys.get_state(pid)
             SendBuffer.stats(state.send_buffer).packets_buffered > 0
           end)

    stats = Coordinator.stats(pid)

    assert stats.parallel_mode == :parallel
    assert stats.packet_count == 2
    assert stats.send_buffer_stats.packets_buffered > 0
  end

  test "parallel mode caps in-flight work when workers are saturated" do
    mission_id = random_id()

    {:ok, pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 2_000.0,
        output: nil,
        definitions_path: @definitions_path,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 1,
        max_in_flight_steps: 2,
        send_batch_timeout: 1_000
      )

    state = :sys.get_state(pid)
    worker = hd(state.generator_pool)
    :ok = :sys.suspend(worker)

    on_exit(fn ->
      maybe_resume(worker)

      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    :ok = Time.advance(1)

    assert wait_for(fn ->
             coordinator_state = :sys.get_state(pid)

             coordinator_state.in_flight_steps == 2 and
               coordinator_state.next_step == 2 and
               coordinator_state.step == 0 and
               coordinator_state.idle_workers == []
           end)

    :ok = Time.advance(1)

    assert wait_for(fn ->
             coordinator_state = :sys.get_state(pid)
             coordinator_state.backpressure_events > 0
           end)
  end

  test "parallel mode throttles when the send buffer backlog is backed up" do
    mission_id = random_id()

    {:ok, pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 1_000.0,
        output: nil,
        definitions_path: @definitions_path,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 1,
        max_in_flight_steps: 10,
        max_send_buffer_queue: 1,
        send_batch_timeout: 1_000
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    :ok = Time.advance(1)

    assert wait_for(fn ->
             coordinator_state = :sys.get_state(pid)
             coordinator_state.send_buffer_queue_len >= 1 and coordinator_state.step == 1
           end)

    :ok = Time.advance(1)

    assert wait_for(fn ->
             coordinator_state = :sys.get_state(pid)

             coordinator_state.send_buffer_queue_len >= 1 and
               coordinator_state.backpressure_events > 0 and
               coordinator_state.pending_steps >= 1 and
               coordinator_state.next_step == 1
           end)
  end

  test "parallel mode prefers larger step batches before waking more workers" do
    mission_id = random_id()

    {:ok, pid} =
      Coordinator.start_link(
        mission_id: mission_id,
        target_id: "SIM-1",
        rate_hz: 10_000.0,
        output: nil,
        definitions_path: @definitions_path,
        provider: DatabaseDynamics,
        parallel_mode: :parallel,
        generator_count: 4,
        max_in_flight_steps: 32,
        send_batch_timeout: 1_000
      )

    state = :sys.get_state(pid)
    workers = state.generator_pool
    Enum.each(workers, &:sys.suspend/1)

    on_exit(fn ->
      Enum.each(workers, &maybe_resume/1)

      if Process.alive?(pid), do: Coordinator.stop(pid)
    end)

    :ok = Time.advance(1)

    assert wait_for(fn ->
             coordinator_state = :sys.get_state(pid)

             coordinator_state.in_flight_steps == 10 and
               coordinator_state.next_step == 10 and
               length(coordinator_state.idle_workers) == 1
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

  defp maybe_resume(pid) do
    if Process.alive?(pid) do
      try do
        :sys.resume(pid)
      catch
        :exit, _ -> :ok
      end
    else
      :ok
    end
  end
end
