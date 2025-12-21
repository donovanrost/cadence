defmodule Cadence.Domain.Commanding.Entities.QueuedCommandTest do
  @moduledoc """
  Pure unit tests for the QueuedCommand domain entity.

  These tests run without database access, demonstrating that
  the domain logic is independent of persistence.
  """
  use Cadence.PureCase

  alias Cadence.Domain.Commanding.Entities.QueuedCommand

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: random_id(),
        organization_id: random_id(),
        mission_id: random_id(),
        target_id: random_id(),
        user_id: random_id(),
        command_name: "POWER_ON",
        parameters: %{"subsystem" => "camera"}
      },
      overrides
    )
  end

  defp create_command(overrides \\ %{}) do
    {:ok, cmd} = QueuedCommand.new(valid_attrs(overrides))
    cmd
  end

  # ===========================================================================
  # Construction Tests
  # ===========================================================================

  describe "new/1" do
    test "creates a command with valid attributes" do
      attrs = valid_attrs()

      assert {:ok, cmd} = QueuedCommand.new(attrs)
      assert cmd.organization_id == attrs.organization_id
      assert cmd.mission_id == attrs.mission_id
      assert cmd.target_id == attrs.target_id
      assert cmd.command_name == "POWER_ON"
      assert cmd.parameters == %{"subsystem" => "camera"}
    end

    test "sets initial status to :pending" do
      {:ok, cmd} = QueuedCommand.new(valid_attrs())
      assert cmd.status == :pending
    end

    test "sets default priority to 3 (normal)" do
      {:ok, cmd} = QueuedCommand.new(valid_attrs())
      assert cmd.priority == 3
    end

    test "sets default max_attempts to 3" do
      {:ok, cmd} = QueuedCommand.new(valid_attrs())
      assert cmd.max_attempts == 3
    end

    test "initializes attempts to 0" do
      {:ok, cmd} = QueuedCommand.new(valid_attrs())
      assert cmd.attempts == 0
    end

    test "fails with missing required fields" do
      assert {:error, {:missing_required, missing}} = QueuedCommand.new(%{})
      assert :organization_id in missing
      assert :mission_id in missing
      assert :target_id in missing
      assert :command_name in missing
    end

    test "fails with invalid priority" do
      attrs = valid_attrs(%{priority: 10})
      assert {:error, :invalid_priority} = QueuedCommand.new(attrs)
    end

    test "fails when expires_at is before scheduled_at" do
      scheduled = from_now(1, :hour)
      expires = from_now(30, :minutes)

      attrs = valid_attrs(%{scheduled_at: scheduled, expires_at: expires})
      assert {:error, :expires_before_scheduled} = QueuedCommand.new(attrs)
    end

    test "accepts optional fields" do
      scheduled = from_now(1, :hour)
      expires = from_now(2, :hours)

      attrs =
        valid_attrs(%{
          priority: 0,
          scheduled_at: scheduled,
          expires_at: expires,
          max_attempts: 5,
          dispatch_opts: %{"confirm_hazard" => true},
          metadata: %{"source" => "procedure"}
        })

      {:ok, cmd} = QueuedCommand.new(attrs)
      assert cmd.priority == 0
      assert cmd.scheduled_at == scheduled
      assert cmd.expires_at == expires
      assert cmd.max_attempts == 5
      assert cmd.dispatch_opts == %{"confirm_hazard" => true}
    end
  end

  # ===========================================================================
  # State Transition Tests
  # ===========================================================================

  describe "claim/1" do
    test "transitions from pending to executing" do
      cmd = create_command()

      assert {:ok, claimed} = QueuedCommand.claim(cmd)
      assert claimed.status == :executing
      assert claimed.attempts == 1
      assert claimed.last_attempt_at != nil
    end

    test "increments attempt count on each claim" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "timeout")
      {:ok, pending} = QueuedCommand.retry(failed)
      {:ok, claimed_again} = QueuedCommand.claim(pending)

      assert claimed_again.attempts == 2
    end

    test "fails when command is expired" do
      cmd = create_command(%{expires_at: ago(1, :hour)})

      assert {:error, :expired} = QueuedCommand.claim(cmd)
    end

    test "fails when scheduled time has not arrived" do
      cmd = create_command(%{scheduled_at: from_now(1, :hour)})

      assert {:error, :not_scheduled_yet} = QueuedCommand.claim(cmd)
    end

    test "fails when already executing" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)

      assert {:error, {:invalid_transition, :executing, :executing}} =
               QueuedCommand.claim(executing)
    end
  end

  describe "complete/2" do
    test "transitions from executing to completed" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)

      assert {:ok, completed} = QueuedCommand.complete(executing, "log-123")
      assert completed.status == :completed
      assert completed.command_log_id == "log-123"
      assert completed.last_error == nil
    end

    test "fails when not executing" do
      cmd = create_command()

      assert {:error, {:invalid_transition, :pending, :completed}} =
               QueuedCommand.complete(cmd, nil)
    end
  end

  describe "fail/2" do
    test "transitions from executing to failed" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)

      assert {:ok, failed} = QueuedCommand.fail(executing, "Connection timeout")
      assert failed.status == :failed
      assert failed.last_error == "Connection timeout"
    end

    test "fails when not executing" do
      cmd = create_command()

      assert {:error, {:invalid_transition, :pending, :failed}} =
               QueuedCommand.fail(cmd, "error")
    end
  end

  describe "retry/1" do
    test "transitions from failed back to pending" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "error")

      assert {:ok, pending} = QueuedCommand.retry(failed)
      assert pending.status == :pending
    end

    test "fails when max attempts exceeded" do
      cmd = create_command(%{max_attempts: 1})
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "error")

      assert {:error, :max_attempts_exceeded} = QueuedCommand.retry(failed)
    end

    test "fails when not in failed status" do
      cmd = create_command()

      assert {:error, {:not_retriable, :pending}} = QueuedCommand.retry(cmd)
    end
  end

  describe "cancel/1" do
    test "cancels a pending command" do
      cmd = create_command()

      assert {:ok, cancelled} = QueuedCommand.cancel(cmd)
      assert cancelled.status == :cancelled
    end

    test "cancels a failed command" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "error")

      assert {:ok, cancelled} = QueuedCommand.cancel(failed)
      assert cancelled.status == :cancelled
    end

    test "fails when already completed" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, completed} = QueuedCommand.complete(executing)

      assert {:error, {:invalid_transition, :completed, :cancelled}} =
               QueuedCommand.cancel(completed)
    end
  end

  describe "expire/1" do
    test "transitions from pending to expired" do
      cmd = create_command()

      assert {:ok, expired} = QueuedCommand.expire(cmd)
      assert expired.status == :expired
    end

    test "fails when already completed" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, completed} = QueuedCommand.complete(executing)

      assert {:error, {:invalid_transition, :completed, :expired}} =
               QueuedCommand.expire(completed)
    end
  end

  # ===========================================================================
  # Priority Management Tests
  # ===========================================================================

  describe "set_priority/2" do
    test "updates priority of pending command" do
      cmd = create_command(%{priority: 3})

      assert {:ok, updated} = QueuedCommand.set_priority(cmd, 0)
      assert updated.priority == 0
    end

    test "fails when command is not pending" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)

      assert {:error, {:cannot_change_priority, :executing}} =
               QueuedCommand.set_priority(executing, 0)
    end

    test "fails with invalid priority" do
      cmd = create_command()

      assert {:error, :invalid_priority} = QueuedCommand.set_priority(cmd, -1)
      assert {:error, :invalid_priority} = QueuedCommand.set_priority(cmd, 6)
    end
  end

  describe "set_sequence/2" do
    test "updates sequence number" do
      cmd = create_command()

      assert {:ok, updated} = QueuedCommand.set_sequence(cmd, 42)
      assert updated.sequence_number == 42
    end
  end

  # ===========================================================================
  # Query Tests
  # ===========================================================================

  describe "ready?/1" do
    test "returns true for pending command without schedule" do
      cmd = create_command()
      assert QueuedCommand.ready?(cmd) == true
    end

    test "returns true for pending command with past schedule" do
      cmd = create_command(%{scheduled_at: ago(1, :hour)})
      assert QueuedCommand.ready?(cmd) == true
    end

    test "returns false for pending command with future schedule" do
      cmd = create_command(%{scheduled_at: from_now(1, :hour)})
      assert QueuedCommand.ready?(cmd) == false
    end

    test "returns false for expired command" do
      cmd = create_command(%{expires_at: ago(1, :hour)})
      assert QueuedCommand.ready?(cmd) == false
    end

    test "returns false for non-pending command" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      assert QueuedCommand.ready?(executing) == false
    end
  end

  describe "expired?/1" do
    test "returns false when no expiration set" do
      cmd = create_command()
      assert QueuedCommand.expired?(cmd) == false
    end

    test "returns false when expiration is in the future" do
      cmd = create_command(%{expires_at: from_now(1, :hour)})
      assert QueuedCommand.expired?(cmd) == false
    end

    test "returns true when expiration has passed" do
      cmd = create_command(%{expires_at: ago(1, :hour)})
      assert QueuedCommand.expired?(cmd) == true
    end
  end

  describe "retriable?/1" do
    test "returns true for failed command under max attempts" do
      cmd = create_command(%{max_attempts: 3})
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "error")

      assert QueuedCommand.retriable?(failed) == true
    end

    test "returns false for failed command at max attempts" do
      cmd = create_command(%{max_attempts: 1})
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "error")

      assert QueuedCommand.retriable?(failed) == false
    end

    test "returns false for non-failed command" do
      cmd = create_command()
      assert QueuedCommand.retriable?(cmd) == false
    end
  end

  describe "terminal?/1" do
    test "returns false for pending" do
      cmd = create_command()
      assert QueuedCommand.terminal?(cmd) == false
    end

    test "returns false for executing" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      assert QueuedCommand.terminal?(executing) == false
    end

    test "returns false for failed" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "error")
      assert QueuedCommand.terminal?(failed) == false
    end

    test "returns true for completed" do
      cmd = create_command()
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, completed} = QueuedCommand.complete(executing)
      assert QueuedCommand.terminal?(completed) == true
    end

    test "returns true for cancelled" do
      cmd = create_command()
      {:ok, cancelled} = QueuedCommand.cancel(cmd)
      assert QueuedCommand.terminal?(cancelled) == true
    end

    test "returns true for expired" do
      cmd = create_command()
      {:ok, expired} = QueuedCommand.expire(cmd)
      assert QueuedCommand.terminal?(expired) == true
    end
  end

  describe "emergency?/1" do
    test "returns true for priority 0" do
      cmd = create_command(%{priority: 0})
      assert QueuedCommand.emergency?(cmd) == true
    end

    test "returns false for other priorities" do
      cmd = create_command(%{priority: 3})
      assert QueuedCommand.emergency?(cmd) == false
    end
  end

  describe "remaining_attempts/1" do
    test "returns max_attempts when no attempts made" do
      cmd = create_command(%{max_attempts: 3})
      assert QueuedCommand.remaining_attempts(cmd) == 3
    end

    test "returns remaining after attempts" do
      cmd = create_command(%{max_attempts: 3})
      {:ok, executing} = QueuedCommand.claim(cmd)
      {:ok, failed} = QueuedCommand.fail(executing, "error")

      assert QueuedCommand.remaining_attempts(failed) == 2
    end
  end

  # ===========================================================================
  # Comparison Tests
  # ===========================================================================

  describe "compare/2" do
    test "orders by priority first (lower = higher priority)" do
      {:ok, high} = QueuedCommand.new(valid_attrs(%{priority: 0}))
      {:ok, low} = QueuedCommand.new(valid_attrs(%{priority: 5}))

      assert QueuedCommand.compare(high, low) == :lt
      assert QueuedCommand.compare(low, high) == :gt
    end

    test "orders by sequence number when priorities are equal" do
      {:ok, first} = QueuedCommand.new(valid_attrs(%{priority: 3, sequence_number: 1}))
      {:ok, second} = QueuedCommand.new(valid_attrs(%{priority: 3, sequence_number: 2}))

      assert QueuedCommand.compare(first, second) == :lt
      assert QueuedCommand.compare(second, first) == :gt
    end

    test "returns :eq for equal priority and sequence" do
      {:ok, cmd1} = QueuedCommand.new(valid_attrs(%{priority: 3, sequence_number: 1}))
      {:ok, cmd2} = QueuedCommand.new(valid_attrs(%{priority: 3, sequence_number: 1}))

      assert QueuedCommand.compare(cmd1, cmd2) == :eq
    end
  end
end
