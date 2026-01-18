defmodule Cadence.Runtime.Commands.TargetDispatcherTimerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Application.Commanding.QueueSnapshot
  alias Cadence.Domain.Commanding.Entities.QueuedCommand
  alias Cadence.Domain.Missions.Entities.Mission
  alias Cadence.Domain.Targeting.Entities.Target
  alias Cadence.Harness.Time
  alias Cadence.Runtime.Commands.{TargetDispatcher, TargetQueue}
  alias Cadence.TestSupport.FakeUplinkDispatcher
  alias Cadence.Time.Timer, as: TimeTimer

  setup_virtual_time()
  setup_mission_registry()

  test "completes executing entries on dispatch timeout after virtual time advances" do
    {mission, target} = build_mission_and_target()
    entry = build_entry(mission, target, max_attempts: 1)

    snapshot = %QueueSnapshot{
      target_id: target.id,
      pending_entries: [entry],
      sequence_counter: 1
    }

    {:ok, _queue_pid} =
      start_supervised({TargetQueue, mission: mission, target: target, queue_snapshot: snapshot})

    {:ok, dispatcher_pid} =
      start_supervised({TargetDispatcher, mission: mission, target: target})

    {:ok, _executing_entry} = TargetQueue.mark_executing(mission.id, target.id, entry.id)

    :sys.replace_state(dispatcher_pid, fn state ->
      task = Task.async(fn -> Process.sleep(:infinity) end)
      %{state | executing: true, dispatch_task: task, executing_entry_id: entry.id}
    end)

    _timer_ref = TimeTimer.send_after(dispatcher_pid, :dispatch_timeout, 1_000)

    assert TargetQueue.status(mission.id, target.id).executing == 1

    :ok = Time.advance(1_000)

    Cadence.PureCase.assert_eventually(
      fn -> TargetQueue.status(mission.id, target.id).executing == 0 end,
      timeout: 1000
    )

    assert TargetQueue.list_pending(mission.id, target.id) == []
  end

  test "schedules queue check after task completion when uplink is connected" do
    {mission, target} = build_mission_and_target()
    entry = build_entry(mission, target, max_attempts: 1)

    snapshot = %QueueSnapshot{
      target_id: target.id,
      pending_entries: [entry],
      sequence_counter: 1
    }

    {:ok, _queue_pid} =
      start_supervised({TargetQueue, mission: mission, target: target, queue_snapshot: snapshot})

    start_supervised!({FakeUplinkDispatcher, mission_id: mission.id})

    {:ok, dispatcher_pid} =
      start_supervised({TargetDispatcher, mission: mission, target: target})

    {:ok, _executing_entry} = TargetQueue.mark_executing(mission.id, target.id, entry.id)

    task_ref = assign_dispatch_task(dispatcher_pid, entry.id)

    send(dispatcher_pid, {task_ref, {:ok, %{aggregate_id: entry.command_aggregate_id}}})

    Cadence.PureCase.assert_eventually(
      fn -> :sys.get_state(dispatcher_pid).executing == false end,
      timeout: 1000
    )

    :sys.suspend(dispatcher_pid)

    try do
      :ok = Time.advance(100)

      {:messages, messages} = :erlang.process_info(dispatcher_pid, :messages)
      assert :check_queue in messages
    after
      :sys.resume(dispatcher_pid)
    end
  end

  test "schedules queue check after task crash when uplink is connected" do
    {mission, target} = build_mission_and_target()
    entry = build_entry(mission, target, max_attempts: 1)

    snapshot = %QueueSnapshot{
      target_id: target.id,
      pending_entries: [entry],
      sequence_counter: 1
    }

    {:ok, _queue_pid} =
      start_supervised({TargetQueue, mission: mission, target: target, queue_snapshot: snapshot})

    start_supervised!({FakeUplinkDispatcher, mission_id: mission.id})

    {:ok, dispatcher_pid} =
      start_supervised({TargetDispatcher, mission: mission, target: target})

    {:ok, _executing_entry} = TargetQueue.mark_executing(mission.id, target.id, entry.id)

    task_ref = assign_dispatch_task(dispatcher_pid, entry.id)

    send(dispatcher_pid, {:DOWN, task_ref, :process, self(), :crashed})

    Cadence.PureCase.assert_eventually(
      fn -> :sys.get_state(dispatcher_pid).executing == false end,
      timeout: 1000
    )

    :sys.suspend(dispatcher_pid)

    try do
      :ok = Time.advance(100)

      {:messages, messages} = :erlang.process_info(dispatcher_pid, :messages)
      assert :check_queue in messages
    after
      :sys.resume(dispatcher_pid)
    end
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
        type: :spacecraft
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

  defp assign_dispatch_task(dispatcher_pid, entry_id) do
    task_ref = make_ref()

    task =
      struct(Task, ref: task_ref, pid: self(), owner: self(), mfa: {__MODULE__, :__info__, 1})

    :sys.replace_state(dispatcher_pid, fn state ->
      %{state | executing: true, dispatch_task: task, executing_entry_id: entry_id}
    end)

    task_ref
  end
end
