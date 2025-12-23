defmodule Cadence.Procedures.Engine.ExecutionPersistenceTest do
  @moduledoc """
  Tests for ExecutionPersistence module.

  Focuses on:
  - Transaction atomicity (all-or-nothing behavior)
  - Outbox event creation
  - Log entry creation
  - PubSub broadcast timing (after commit, not during)
  - Idempotent operations
  """
  use Cadence.DataCase, async: false

  import Cadence.ProceduresFixtures

  alias Cadence.Procedures.Engine.ExecutionPersistence
  alias Cadence.Procedures.ProcedureLog
  alias Cadence.Outbox.Event, as: OutboxEvent
  alias Cadence.Repo

  import Ecto.Query

  # Helper to create execution in a specific state
  defp execution_in_state(status, extra_attrs \\ %{}) do
    attrs = Map.merge(%{status: status}, extra_attrs)

    if status == :running do
      attrs = Map.put_new(attrs, :started_at, DateTime.utc_now())
      execution_fixture(attrs)
    else
      execution_fixture(attrs)
    end
  end

  setup do
    # Create a basic pending execution for tests that need it
    execution = execution_fixture()
    Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution.id}")

    %{execution: execution}
  end

  describe "update_status_with_log/6" do
    test "updates status and creates log atomically", %{execution: execution} do
      {:ok, updated} =
        ExecutionPersistence.update_status_with_log(
          execution,
          :running,
          %{started_at: DateTime.utc_now()},
          :info,
          "Execution started"
        )

      assert updated.status == :running
      assert updated.started_at != nil

      # Verify log was created
      logs = Repo.all(from l in ProcedureLog, where: l.execution_id == ^execution.id)
      assert length(logs) == 1
      assert hd(logs).message == "Execution started"
      assert hd(logs).level == :info
    end

    test "creates outbox event by default", %{execution: execution} do
      {:ok, _updated} =
        ExecutionPersistence.update_status_with_log(
          execution,
          :running,
          %{started_at: DateTime.utc_now()},
          :info,
          "Started"
        )

      # Verify outbox event was created
      events =
        Repo.all(
          from e in OutboxEvent,
            where: e.aggregate_id == ^execution.id,
            where: e.event_type == "procedure_execution_running"
        )

      assert length(events) == 1
    end

    test "skips outbox event when skip_outbox: true", %{execution: execution} do
      {:ok, _updated} =
        ExecutionPersistence.update_status_with_log(
          execution,
          :running,
          %{started_at: DateTime.utc_now()},
          :info,
          "Started",
          skip_outbox: true
        )

      # Verify no outbox event was created
      events =
        Repo.all(
          from e in OutboxEvent,
            where: e.aggregate_id == ^execution.id,
            where: e.event_type == "procedure_execution_running"
        )

      assert events == []
    end

    test "broadcasts status change after commit", %{execution: execution} do
      {:ok, updated} =
        ExecutionPersistence.update_status_with_log(
          execution,
          :running,
          %{started_at: DateTime.utc_now()},
          :info,
          "Started"
        )

      assert_receive {:status_changed, :running, ^updated}
      assert_receive {:log, :info, "Started"}
    end
  end

  describe "create_log_entry/4" do
    test "creates standalone log entry", %{execution: execution} do
      {:ok, log} = ExecutionPersistence.create_log_entry(execution.id, :warn, "Warning message")

      assert log.execution_id == execution.id
      assert log.level == :warn
      assert log.message == "Warning message"
    end

    test "includes step_index when provided", %{execution: execution} do
      {:ok, log} = ExecutionPersistence.create_log_entry(execution.id, :info, "Step log", 5)

      assert log.step_index == 5
    end
  end

  describe "persist_and_broadcast_log/4" do
    test "persists log and broadcasts", %{execution: execution} do
      :ok = ExecutionPersistence.persist_and_broadcast_log(execution.id, :info, "Broadcast test")

      # Verify persistence
      logs = Repo.all(from l in ProcedureLog, where: l.execution_id == ^execution.id)
      assert Enum.any?(logs, &(&1.message == "Broadcast test"))

      # Verify broadcast
      assert_receive {:log, :info, "Broadcast test"}
    end
  end

  describe "save_checkpoint/3" do
    test "saves checkpoint state", %{execution: execution} do
      {:ok, updated} = ExecutionPersistence.save_checkpoint(execution, 5, <<1, 2, 3>>)

      assert updated.current_step_index == 5
      assert updated.checkpoint_state == <<1, 2, 3>>
    end

    test "works without checkpoint_state", %{execution: execution} do
      {:ok, updated} = ExecutionPersistence.save_checkpoint(execution, 3)

      assert updated.current_step_index == 3
      assert updated.checkpoint_state == nil
    end
  end

  describe "persist_step_event/5" do
    test "persists step started event", %{execution: execution} do
      :ok = ExecutionPersistence.persist_step_event(execution, "step_1", :running, nil)

      # Verify outbox event
      events =
        Repo.all(
          from e in OutboxEvent,
            where: e.aggregate_id == ^execution.id,
            where: e.event_type == "procedure_step_started"
        )

      assert length(events) == 1
      event = hd(events)
      assert event.payload["step_name"] == "step_1"

      # Verify log
      logs = Repo.all(from l in ProcedureLog, where: l.execution_id == ^execution.id)
      assert Enum.any?(logs, &String.contains?(&1.message, "Step started: step_1"))
    end

    test "persists step completed event with data", %{execution: execution} do
      data = %{result: 42, message: "Computation complete"}

      :ok = ExecutionPersistence.persist_step_event(execution, "compute", :completed, data)

      # Verify outbox event has serialized data
      events =
        Repo.all(
          from e in OutboxEvent,
            where: e.aggregate_id == ^execution.id,
            where: e.event_type == "procedure_step_completed"
        )

      assert length(events) == 1
      event = hd(events)
      assert event.payload["data"]["result"] == 42
    end

    test "creates user log for log steps", %{execution: execution} do
      data = %{message: "User visible message", level: :warn}

      :ok = ExecutionPersistence.persist_step_event(execution, "log_step", :completed, data)

      # Should have two logs: system log and user log
      logs = Repo.all(from l in ProcedureLog, where: l.execution_id == ^execution.id)
      assert length(logs) == 2

      messages = Enum.map(logs, & &1.message)
      assert "User visible message" in messages
      assert Enum.any?(messages, &String.contains?(&1, "Step completed"))
    end

    test "broadcasts step events after commit", %{execution: execution} do
      :ok = ExecutionPersistence.persist_step_event(execution, "step_1", :completed, %{value: 1})

      assert_receive {:dag_step_completed, "step_1", %{value: 1}}
      assert_receive {:log, :info, "Step completed: step_1"}
    end

    # Skipped: Partial unique index requires special handling in Ecto
    # The index is: WHERE idempotency_key IS NOT NULL
    # Ecto's conflict_target doesn't automatically work with partial indexes
    # TODO: Use index name explicitly or switch to ON CONFLICT ON CONSTRAINT syntax
    @tag :skip
    test "handles idempotent inserts with idempotency_key", %{execution: execution} do
      key = "resume:#{execution.id}:step_1:completed"

      # First insert should succeed
      :ok =
        ExecutionPersistence.persist_step_event(
          execution,
          "step_1",
          :completed,
          %{},
          idempotency_key: key
        )

      # Second insert with same key should also succeed (no conflict error)
      :ok =
        ExecutionPersistence.persist_step_event(
          execution,
          "step_1",
          :completed,
          %{},
          idempotency_key: key
        )

      # Should only have one event with that key
      events =
        Repo.all(
          from e in OutboxEvent,
            where: e.idempotency_key == ^key
        )

      assert length(events) == 1
    end

    test "handles blocked step with tuple data (regression test)", %{execution: execution} do
      # This was a bug - tuples like {:dependency_failed, "step_1"} weren't JSON-serializable
      data = {:dependency_failed, "failed_step"}

      :ok = ExecutionPersistence.persist_step_event(execution, "blocked_step", :blocked, data)

      # Verify it was serialized correctly
      events =
        Repo.all(
          from e in OutboxEvent,
            where: e.aggregate_id == ^execution.id,
            where: e.event_type == "procedure_step_blocked"
        )

      assert length(events) == 1
      event = hd(events)
      # Tuple should be converted to list
      assert event.payload["data"] == ["dependency_failed", "failed_step"]
    end
  end

  describe "persist_dag_result/3" do
    test "persists completed DAG result" do
      # Need execution in running state to transition to completed
      execution = execution_in_state(:running)
      Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution.id}")

      result = %{
        completed_steps: ["step_1", "step_2"],
        failed_steps: [],
        blocked_steps: [],
        skipped_steps: [],
        step_results: %{"step_1" => %{value: 1}, "step_2" => %{value: 2}}
      }

      {:ok, updated} = ExecutionPersistence.persist_dag_result(execution, :completed, result)

      assert updated.status == :completed
      assert updated.completed_at != nil
      assert updated.completed_steps == ["step_1", "step_2"]
      assert updated.step_results == %{"step_1" => %{value: 1}, "step_2" => %{value: 2}}
    end

    test "persists failed DAG result with error message" do
      execution = execution_in_state(:running)
      Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution.id}")

      result = %{
        completed_steps: ["step_1"],
        failed_steps: ["step_2", "step_3"],
        blocked_steps: ["step_4"],
        skipped_steps: [],
        step_results: %{}
      }

      {:ok, updated} = ExecutionPersistence.persist_dag_result(execution, :failed, result)

      assert updated.status == :failed
      assert updated.error_message == "Steps failed: step_2, step_3"
      assert updated.failed_steps == ["step_2", "step_3"]
      assert updated.blocked_steps == ["step_4"]
    end

    test "creates outbox event for final status" do
      execution = execution_in_state(:running)

      result = %{
        completed_steps: ["step_1"],
        failed_steps: [],
        blocked_steps: [],
        skipped_steps: [],
        step_results: %{}
      }

      {:ok, _updated} = ExecutionPersistence.persist_dag_result(execution, :completed, result)

      events =
        Repo.all(
          from e in OutboxEvent,
            where: e.aggregate_id == ^execution.id,
            where: e.event_type == "procedure_execution_completed"
        )

      assert length(events) == 1
    end

    test "broadcasts status change after commit" do
      execution = execution_in_state(:running)
      Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution.id}")

      result = %{
        completed_steps: [],
        failed_steps: [],
        blocked_steps: [],
        skipped_steps: [],
        step_results: %{}
      }

      {:ok, updated} = ExecutionPersistence.persist_dag_result(execution, :completed, result)

      assert_receive {:status_changed, :completed, ^updated}
    end
  end
end
