defmodule Cadence.Platform.DrainTest do
  use ExUnit.Case, async: false

  alias Cadence.Control.Missions
  alias Cadence.Platform.Drain
  alias Cadence.Runtime.ProcessNamespace
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  setup do
    Drain.reset(__MODULE__)
    on_exit(fn -> Drain.reset(__MODULE__) end)
    :ok
  end

  test "stops admission immediately, settles once, and shares the result with concurrent callers" do
    test = self()

    start_supervised!(
      {Drain,
       name: __MODULE__,
       callback: fn ->
         send(test, {:drain_entered, self()})

         receive do
           :finish -> {:ok, %{journals: 3}}
         end
       end}
    )

    first = Task.async(fn -> Drain.run(__MODULE__, timeout_ms: 1_000) end)
    assert_receive {:drain_entered, worker}
    assert Drain.draining?(__MODULE__)
    assert %{status: :draining} = Drain.snapshot(__MODULE__)
    second = Task.async(fn -> Drain.run(__MODULE__, timeout_ms: 1) end)
    send(worker, :finish)
    assert {:ok, %{journals: 3}} = Task.await(first)
    assert {:ok, %{journals: 3}} = Task.await(second)
    assert {:ok, %{journals: 3}} = Drain.run(__MODULE__, [])
    refute_receive {:drain_entered, _}
    assert %{status: :drained, duration_ms: duration} = Drain.snapshot(__MODULE__)
    assert duration >= 0
  end

  test "timeout cancels work, remains unready, and cannot become success later" do
    test = self()

    start_supervised!(
      {Drain,
       name: __MODULE__,
       callback: fn ->
         send(test, {:drain_entered, self()})
         Process.sleep(:infinity)
       end}
    )

    call = Task.async(fn -> Drain.run(__MODULE__, timeout_ms: 100) end)
    assert_receive {:drain_entered, worker}
    monitor = Process.monitor(worker)
    assert {:error, :drain_timeout} = Task.await(call)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert Drain.draining?(__MODULE__)
    assert {:error, :drain_timeout} = Drain.run(__MODULE__, [])
  end

  test "callback failure and worker restart cannot reopen admission" do
    start_supervised!(
      {Drain, name: __MODULE__, callback: fn -> {:error, :archive_unavailable} end}
    )

    assert {:error, :archive_unavailable} = Drain.run(__MODULE__, [])
    assert :ok = stop_supervised(Drain)
    start_supervised!({Drain, name: __MODULE__, callback: fn -> flunk("must not run") end})
    assert Drain.draining?(__MODULE__)
    assert {:error, :drain_worker_restarted} = Drain.run(__MODULE__, [])
  end

  test "invalid deadlines do not start draining" do
    start_supervised!({Drain, name: __MODULE__, callback: fn -> flunk("must not run") end})

    assert {:error, :invalid_drain_deadline} =
             Drain.run(__MODULE__, timeout_ms: 10, settle_ms: 10)

    refute Drain.draining?(__MODULE__)
  end

  test "new mission and contact admission is rejected during process drain" do
    :persistent_term.put({Drain, Drain}, true)
    on_exit(fn -> Drain.reset() end)

    namespace = %{ProcessNamespace.default() | mission_supervisor: :absent_during_drain}

    {:ok, _} =
      Registry.register(namespace.registry, {:mission_runtime, "existing-during-drain"}, nil)

    assert {:ok, pid} = Cadence.Runtime.ensure_mission_started(namespace, "existing-during-drain")
    assert pid == self()

    assert {:error, :cadence_draining} =
             Cadence.Runtime.ensure_mission_started("new-during-drain")

    assert {:error, :cadence_draining} =
             Missions.ensure_started("new-during-drain")

    {:ok, contact} =
      RealizedContactRuntimeSpec.new(%{
        mission_id: "new-during-drain",
        realized_contact_id: "new-contact",
        paths: [%{path_id: "downlink", direction: :downlink}]
      })

    assert {:error, :cadence_draining} = Cadence.Runtime.start_realized_contact(contact)
  end
end
