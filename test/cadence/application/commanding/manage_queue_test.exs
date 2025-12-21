defmodule Cadence.Application.Commanding.ManageQueueTest do
  @moduledoc """
  Use case tests for ManageQueue.

  Tests command queue lifecycle operations (claim, complete, fail, retry, cancel).
  """
  use Cadence.PureCase, async: false

  alias Cadence.Application.Commanding.ManageQueue
  alias Cadence.Domain.Commanding.Entities.QueuedCommand
  alias Cadence.Test.Adapters.InMemoryQueueRepository
  alias Cadence.Test.Adapters.FakeEventPublisher
  alias Cadence.Test.Adapters.InMemoryEventRecorder

  setup do
    # Start fake adapters
    {:ok, _} = InMemoryQueueRepository.start_link()
    {:ok, _} = FakeEventPublisher.start_link()
    {:ok, _} = InMemoryEventRecorder.start_link()

    # Configure DI
    Application.put_env(:cadence, :queue_repository, InMemoryQueueRepository)
    Application.put_env(:cadence, :event_publisher, FakeEventPublisher)
    Application.put_env(:cadence, :event_recorder, InMemoryEventRecorder)

    on_exit(fn ->
      Application.delete_env(:cadence, :queue_repository)
      Application.delete_env(:cadence, :event_publisher)
      Application.delete_env(:cadence, :event_recorder)
      InMemoryQueueRepository.stop()
      FakeEventPublisher.stop()
      InMemoryEventRecorder.stop()
    end)

    :ok
  end

  describe "claim_next/1" do
    test "claims the highest priority pending command" do
      target_id = random_id()
      _low = insert_pending_command(target_id: target_id, priority: 3)
      high = insert_pending_command(target_id: target_id, priority: 1)

      {:ok, claimed} = ManageQueue.claim_next(target_id)

      assert claimed.id == high.id
      assert claimed.status == :executing
    end

    test "claims by sequence number when priorities are equal" do
      target_id = random_id()
      first = insert_pending_command(target_id: target_id, priority: 2)
      _second = insert_pending_command(target_id: target_id, priority: 2)

      {:ok, claimed} = ManageQueue.claim_next(target_id)

      assert claimed.id == first.id
    end

    test "skips future-scheduled commands" do
      target_id = random_id()
      _scheduled = insert_pending_command(target_id: target_id, scheduled_at: from_now(1, :hour))
      ready = insert_pending_command(target_id: target_id)

      {:ok, claimed} = ManageQueue.claim_next(target_id)

      assert claimed.id == ready.id
    end

    test "skips expired commands" do
      target_id = random_id()
      _expired = insert_pending_command(target_id: target_id, expires_at: ago(1, :hour))
      valid = insert_pending_command(target_id: target_id)

      {:ok, claimed} = ManageQueue.claim_next(target_id)

      assert claimed.id == valid.id
    end

    test "returns error when queue is empty" do
      result = ManageQueue.claim_next(random_id())

      assert {:error, :queue_empty} = result
    end

    test "broadcasts claimed event" do
      target_id = random_id()
      _cmd = insert_pending_command(target_id: target_id)

      {:ok, _claimed} = ManageQueue.claim_next(target_id)

      events = FakeEventPublisher.list_events()
      assert length(events) >= 1
    end
  end

  describe "complete/2" do
    test "marks executing command as completed" do
      cmd = insert_executing_command()

      {:ok, completed} = ManageQueue.complete(cmd.id, "log-123")

      assert completed.status == :completed
      assert completed.command_log_id == "log-123"
    end

    test "records dequeue event" do
      cmd = insert_executing_command()

      {:ok, _completed} = ManageQueue.complete(cmd.id, nil)

      assert InMemoryEventRecorder.recorded?(:command_dequeued)
    end

    test "returns error for non-executing command" do
      cmd = insert_pending_command()

      result = ManageQueue.complete(cmd.id, nil)

      assert {:error, {:invalid_transition, :pending, :completed}} = result
    end
  end

  describe "fail/2" do
    test "marks executing command as failed" do
      cmd = insert_executing_command()

      {:ok, failed} = ManageQueue.fail(cmd.id, "Connection timeout")

      assert failed.status == :failed
      assert failed.last_error == "Connection timeout"
      # Note: attempts are set by claim(), not fail()
      # The executing command already has 1 attempt from being claimed
      assert failed.attempts == 1
    end

    test "preserves attempt count from claim" do
      # Command is claimed (attempts=1), then we override to 2 for this test
      cmd = insert_executing_command(attempts: 2)

      {:ok, failed} = ManageQueue.fail(cmd.id, "Error")

      # fail() does not increment attempts - only claim() does
      assert failed.attempts == 2
    end

    test "records dequeue event" do
      cmd = insert_executing_command()

      {:ok, _failed} = ManageQueue.fail(cmd.id, "Error")

      assert InMemoryEventRecorder.recorded?(:command_dequeued)
    end
  end

  describe "retry/1" do
    test "returns failed command to pending" do
      cmd = insert_failed_command(attempts: 1)

      {:ok, retried} = ManageQueue.retry(cmd.id)

      assert retried.status == :pending
    end

    test "returns error when max attempts exceeded" do
      cmd = insert_failed_command(attempts: 3, max_attempts: 3)

      result = ManageQueue.retry(cmd.id)

      assert {:error, :max_attempts_exceeded} = result
    end

    test "returns error for non-failed command" do
      cmd = insert_pending_command()

      result = ManageQueue.retry(cmd.id)

      assert {:error, {:not_retriable, :pending}} = result
    end
  end

  describe "cancel/1" do
    test "cancels a pending command" do
      cmd = insert_pending_command()

      {:ok, cancelled} = ManageQueue.cancel(cmd.id)

      assert cancelled.status == :cancelled
    end

    test "cancels a failed command" do
      cmd = insert_failed_command()

      {:ok, cancelled} = ManageQueue.cancel(cmd.id)

      assert cancelled.status == :cancelled
    end

    test "returns error for executing command" do
      cmd = insert_executing_command()

      result = ManageQueue.cancel(cmd.id)

      assert {:error, {:invalid_transition, :executing, :cancelled}} = result
    end

    test "records dequeue event" do
      cmd = insert_pending_command()

      {:ok, _cancelled} = ManageQueue.cancel(cmd.id)

      assert InMemoryEventRecorder.recorded?(:command_dequeued)
    end
  end

  describe "cancel_all_pending/1" do
    test "cancels all pending commands for target" do
      target_id = random_id()
      insert_pending_command(target_id: target_id)
      insert_pending_command(target_id: target_id)
      insert_pending_command(target_id: target_id)

      {:ok, count} = ManageQueue.cancel_all_pending(target_id)

      assert count == 3
    end

    test "does not cancel commands for other targets" do
      target_id = random_id()
      other_target = random_id()
      insert_pending_command(target_id: target_id)
      other = insert_pending_command(target_id: other_target)

      {:ok, count} = ManageQueue.cancel_all_pending(target_id)

      assert count == 1

      {:ok, found} = InMemoryQueueRepository.find(other.id)
      assert found.status == :pending
    end

    test "returns 0 when no pending commands" do
      {:ok, count} = ManageQueue.cancel_all_pending(random_id())

      assert count == 0
    end
  end

  describe "set_priority/2" do
    test "updates priority of pending command" do
      cmd = insert_pending_command(priority: 3)

      {:ok, updated} = ManageQueue.set_priority(cmd.id, 1)

      assert updated.priority == 1
    end

    test "returns error for invalid priority" do
      cmd = insert_pending_command()

      result = ManageQueue.set_priority(cmd.id, 6)

      assert {:error, :invalid_priority} = result
    end

    test "returns error for executing command" do
      cmd = insert_executing_command()

      result = ManageQueue.set_priority(cmd.id, 1)

      assert {:error, {:cannot_change_priority, :executing}} = result
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp insert_pending_command(opts \\ []) do
    {:ok, cmd} =
      QueuedCommand.new(%{
        organization_id: Keyword.get(opts, :organization_id, random_id()),
        mission_id: Keyword.get(opts, :mission_id, random_id()),
        target_id: Keyword.get(opts, :target_id, random_id()),
        command_name: Keyword.get(opts, :command_name, "TEST_CMD"),
        priority: Keyword.get(opts, :priority, 3),
        scheduled_at: Keyword.get(opts, :scheduled_at),
        expires_at: Keyword.get(opts, :expires_at),
        max_attempts: Keyword.get(opts, :max_attempts, 3)
      })

    InMemoryQueueRepository.insert(cmd)
  end

  defp insert_executing_command(opts \\ []) do
    cmd = insert_pending_command(opts)
    {:ok, executing} = QueuedCommand.claim(cmd)

    # Only override attempts if explicitly specified
    executing =
      if Keyword.has_key?(opts, :attempts) do
        %{executing | attempts: Keyword.get(opts, :attempts)}
      else
        executing
      end

    InMemoryQueueRepository.save(executing)
    executing
  end

  defp insert_failed_command(opts \\ []) do
    cmd = insert_executing_command(opts)
    {:ok, failed} = QueuedCommand.fail(cmd, "Test failure")
    failed = %{failed | attempts: Keyword.get(opts, :attempts, 1)}
    failed = %{failed | max_attempts: Keyword.get(opts, :max_attempts, 3)}
    InMemoryQueueRepository.save(failed)
    failed
  end
end
