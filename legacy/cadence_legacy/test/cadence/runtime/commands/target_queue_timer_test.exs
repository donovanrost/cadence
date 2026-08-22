defmodule Cadence.Runtime.Commands.TargetQueueTimerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Application.Commanding.QueueSnapshot
  alias Cadence.Domain.Commanding.Entities.QueuedCommand
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Harness.Time
  alias Cadence.Runtime.Commands.TargetQueue
  alias Cadence.TestSupport.FakeTargetDispatcher

  setup_virtual_time()
  setup_mission_registry()

  test "retries failed entries after virtual time advances" do
    {mission, target} = build_mission_and_target()
    entry = build_entry(mission, target, max_attempts: 2)

    snapshot = %QueueSnapshot{
      target_id: target.id,
      pending_entries: [entry],
      sequence_counter: 1
    }

    {:ok, _pid} =
      start_supervised({TargetQueue, mission: mission, target: target, queue_snapshot: snapshot})

    {:ok, _executing_entry} = TargetQueue.mark_executing(mission.id, target.id, entry.id)
    TargetQueue.complete(mission.id, target.id, entry.id, {:error, :dispatch_timeout})

    Cadence.PureCase.assert_eventually(
      fn -> TargetQueue.list_pending(mission.id, target.id) == [] end,
      timeout: 1000
    )

    :ok = Time.advance(1_000)

    Cadence.PureCase.assert_eventually(
      fn ->
        TargetQueue.list_pending(mission.id, target.id)
        |> Enum.any?(&(&1.id == entry.id and &1.status == :pending))
      end,
      timeout: 1000
    )
  end

  test "does not retry before the delay elapses" do
    {mission, target} = build_mission_and_target()
    entry = build_entry(mission, target, max_attempts: 2)

    snapshot = %QueueSnapshot{
      target_id: target.id,
      pending_entries: [entry],
      sequence_counter: 1
    }

    {:ok, _pid} =
      start_supervised({TargetQueue, mission: mission, target: target, queue_snapshot: snapshot})

    {:ok, _executing_entry} = TargetQueue.mark_executing(mission.id, target.id, entry.id)
    TargetQueue.complete(mission.id, target.id, entry.id, {:error, :dispatch_timeout})

    Cadence.PureCase.assert_eventually(
      fn -> TargetQueue.list_pending(mission.id, target.id) == [] end,
      timeout: 1000
    )

    :ok = Time.advance(999)

    assert TargetQueue.list_pending(mission.id, target.id) == []

    :ok = Time.advance(1)

    Cadence.PureCase.assert_eventually(
      fn ->
        TargetQueue.list_pending(mission.id, target.id)
        |> Enum.any?(&(&1.id == entry.id and &1.status == :pending))
      end,
      timeout: 1000
    )
  end

  test "does not schedule retry when max attempts is reached" do
    {mission, target} = build_mission_and_target()
    entry = build_entry(mission, target, max_attempts: 1)

    snapshot = %QueueSnapshot{
      target_id: target.id,
      pending_entries: [entry],
      sequence_counter: 1
    }

    {:ok, queue_pid} =
      start_supervised({TargetQueue, mission: mission, target: target, queue_snapshot: snapshot})

    {:ok, _executing_entry} = TargetQueue.mark_executing(mission.id, target.id, entry.id)
    TargetQueue.complete(mission.id, target.id, entry.id, {:error, :dispatch_timeout})

    Cadence.PureCase.assert_eventually(
      fn -> TargetQueue.status(mission.id, target.id).executing == 0 end,
      timeout: 1000
    )

    entry_id = entry.id

    :sys.suspend(queue_pid)

    try do
      :ok = Time.advance(1_000)

      {:messages, messages} = :erlang.process_info(queue_pid, :messages)

      refute Enum.any?(messages, &match?({:retry_command, ^entry_id}, &1))
    after
      :sys.resume(queue_pid)
    end

    assert TargetQueue.list_pending(mission.id, target.id) == []
  end

  test "triggers dispatcher check on process loop after virtual time advances" do
    {mission, target} = build_mission_and_target()
    entry = build_entry(mission, target, max_attempts: 1)

    snapshot = %QueueSnapshot{
      target_id: target.id,
      pending_entries: [entry],
      sequence_counter: 1
    }

    {:ok, _queue_pid} =
      start_supervised({TargetQueue, mission: mission, target: target, queue_snapshot: snapshot})

    dispatcher_pid =
      start_supervised!({FakeTargetDispatcher, mission_id: mission.id, target_id: target.id})

    assert FakeTargetDispatcher.count(dispatcher_pid) == 0

    :ok = Time.advance(:timer.seconds(10))

    Cadence.PureCase.assert_eventually(
      fn -> FakeTargetDispatcher.count(dispatcher_pid) > 0 end,
      timeout: 1000
    )
  end

  defp build_mission_and_target do
    mission_id = random_id()

    {:ok, mission} =
      Mission.new(%{
        id: mission_id,
        organization_id: random_id(),
        name: "Test Mission",
        slug: "test-mission-#{unique_integer()}"
      })

    {:ok, target} =
      Target.new(%{
        id: random_id(),
        mission_id: mission_id,
        definition_set_id: random_id(),
        name: "SAT-1",
        identifier: "SAT-1-#{unique_integer()}",
        type: :spacecraft,
        scid: 1
      })

    {mission, target}
  end

  defp build_entry(mission, target, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 2)

    {:ok, entry} =
      QueuedCommand.new(%{
        id: random_id(),
        organization_id: mission.organization_id,
        mission_id: mission.id,
        target_id: target.id,
        command_name: "NOOP",
        sequence_number: 1,
        priority: 3,
        max_attempts: max_attempts
      })

    entry
  end
end
