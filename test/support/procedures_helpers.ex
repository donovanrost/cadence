defmodule Cadence.ProceduresHelpers do
  @moduledoc """
  Test helpers for Procedures feature testing.

  Provides utilities for:
  - Async condition waiting (assert_eventually)
  - PubSub subscription and message collection
  - Execution status waiting
  """

  import ExUnit.Assertions

  # ============================================================================
  # Async Condition Helpers
  # ============================================================================

  @doc """
  Waits for a condition to become true, polling at intervals.
  Fails if condition not met within timeout.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 1000)
  - `:interval` - Polling interval in milliseconds (default: 10)
  - `:message` - Custom failure message

  ## Examples

      assert_eventually(fn -> Process.alive?(pid) end)

      assert_eventually(fn ->
        Repo.get(Execution, id).status == :completed
      end, timeout: 5000)

      assert_eventually(
        fn -> length(messages) > 0 end,
        message: "Expected messages to arrive"
      )
  """
  def assert_eventually(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 10)
    message = Keyword.get(opts, :message, "Condition not met within #{timeout}ms")
    deadline = System.monotonic_time(:millisecond) + timeout

    do_assert_eventually(fun, deadline, interval, message)
  end

  defp do_assert_eventually(fun, deadline, interval, message) do
    if safe_condition?(fun) do
      :ok
    else
      maybe_retry_eventually(fun, deadline, interval, message)
    end
  end

  defp maybe_retry_eventually(fun, deadline, interval, message) do
    if System.monotonic_time(:millisecond) >= deadline do
      flunk(message)
    else
      Process.sleep(interval)
      do_assert_eventually(fun, deadline, interval, message)
    end
  end

  defp safe_condition?(fun) do
    fun.()
  rescue
    _ -> false
  end

  @doc """
  Waits for a condition to become true, returning the result.
  Returns `{:ok, result}` or `{:error, :timeout}`.

  Unlike `assert_eventually/2`, this doesn't fail - use when you need
  to handle the timeout case gracefully.

  ## Examples

      case wait_until(fn -> get_status(id) == :completed end) do
        :ok -> # condition met
        {:error, :timeout} -> # handle timeout
      end
  """
  def wait_until(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 10)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_until(fun, deadline, interval)
  end

  defp do_wait_until(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        {:error, :timeout}
      else
        Process.sleep(interval)
        do_wait_until(fun, deadline, interval)
      end
    end
  end

  # ============================================================================
  # PubSub Helpers
  # ============================================================================

  @doc """
  Subscribes the test process to a procedure execution's PubSub topic.

  ## Examples

      subscribe_to_execution(execution.id)
      # Now receive messages like {:status_changed, :running, execution}
  """
  def subscribe_to_execution(execution_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "procedure:#{execution_id}")
  end

  @doc """
  Subscribes to a mission's procedure events topic.
  """
  def subscribe_to_mission_procedures(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:procedures")
  end

  @doc """
  Collects all messages received within a timeout period.
  Useful for verifying a sequence of broadcasts.

  ## Examples

      subscribe_to_execution(execution.id)
      # ... trigger execution ...
      messages = collect_messages(500)
      assert {:status_changed, :running, _} in messages
  """
  def collect_messages(timeout \\ 100) do
    collect_messages_loop([], timeout)
  end

  defp collect_messages_loop(acc, timeout) do
    receive do
      msg -> collect_messages_loop([msg | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  @doc """
  Collects messages matching a pattern within a timeout.

  ## Examples

      status_messages = collect_matching(500, fn
        {:status_changed, _, _} -> true
        _ -> false
      end)
  """
  def collect_matching(timeout, match_fun) do
    collect_messages(timeout)
    |> Enum.filter(match_fun)
  end

  # ============================================================================
  # Execution Status Helpers
  # ============================================================================

  @doc """
  Waits for a specific execution status change message.

  ## Examples

      subscribe_to_execution(execution.id)
      {:ok, execution} = await_status(:running)
      {:ok, execution} = await_status(:completed, 10_000)
  """
  def await_status(expected_status, timeout \\ 5000) do
    receive do
      {:status_changed, ^expected_status, execution} ->
        {:ok, execution}

      {:status_changed, other_status, _execution} ->
        {:error, {:unexpected_status, other_status, expected: expected_status}}
    after
      timeout ->
        {:error, {:timeout, expected: expected_status}}
    end
  end

  @doc """
  Waits for execution to reach any terminal state (completed, failed, cancelled).

  ## Examples

      subscribe_to_execution(execution.id)
      {:ok, :completed, execution} = await_completion()
      {:ok, :failed, execution} = await_completion(10_000)
  """
  def await_completion(timeout \\ 5000) do
    await_any_status([:completed, :failed, :cancelled], timeout)
  end

  @doc """
  Waits for execution to reach any of the specified statuses.

  ## Examples

      {:ok, status, execution} = await_any_status([:paused, :completed])
  """
  def await_any_status(statuses, timeout \\ 5000) when is_list(statuses) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_any_status(statuses, deadline)
  end

  defp do_await_any_status(statuses, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:status_changed, status, execution} ->
        if status in statuses do
          {:ok, status, execution}
        else
          # Keep waiting for the expected status
          do_await_any_status(statuses, deadline)
        end
    after
      remaining ->
        {:error, {:timeout, expected: statuses}}
    end
  end

  # ============================================================================
  # Step Event Helpers
  # ============================================================================

  @doc """
  Waits for a specific step to complete.

  ## Examples

      subscribe_to_execution(execution.id)
      {:ok, data} = await_step_completed("step_1")
  """
  def await_step_completed(step_name, timeout \\ 5000) do
    receive do
      {:dag_step_completed, ^step_name, data} ->
        {:ok, data}

      {:dag_step_failed, ^step_name, data} ->
        {:error, {:step_failed, data}}
    after
      timeout ->
        {:error, {:timeout, step: step_name}}
    end
  end

  @doc """
  Waits for a step to start.
  """
  def await_step_started(step_name, timeout \\ 5000) do
    receive do
      {:dag_step_started, ^step_name, data} ->
        {:ok, data}
    after
      timeout ->
        {:error, {:timeout, step: step_name}}
    end
  end

  @doc """
  Collects all step events for analysis.
  """
  def collect_step_events(timeout \\ 500) do
    collect_matching(timeout, fn
      {:dag_step_started, _, _} -> true
      {:dag_step_completed, _, _} -> true
      {:dag_step_failed, _, _} -> true
      {:dag_step_blocked, _, _} -> true
      {:dag_step_skipped, _, _} -> true
      _ -> false
    end)
  end

  # ============================================================================
  # Process Helpers
  # ============================================================================

  @doc """
  Waits for a process to terminate.

  ## Examples

      ref = Process.monitor(pid)
      assert_process_exits(ref, :normal)
  """
  def assert_process_exits(ref, expected_reason \\ :normal, timeout \\ 5000) do
    receive do
      {:DOWN, ^ref, :process, _pid, ^expected_reason} ->
        :ok

      {:DOWN, ^ref, :process, _pid, actual_reason} ->
        flunk(
          "Process exited with #{inspect(actual_reason)}, expected #{inspect(expected_reason)}"
        )
    after
      timeout ->
        flunk("Process did not exit within #{timeout}ms")
    end
  end

  @doc """
  Monitors a process and returns when it exits, with the exit reason.
  """
  def await_process_exit(pid, timeout \\ 5000) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:ok, reason}
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  end

  # ============================================================================
  # Execution Lifecycle Helpers
  # ============================================================================

  @doc """
  Starts a procedure execution and waits for it to begin running.
  Combines common setup pattern.

  ## Examples

      {:ok, execution} = start_and_await_running(coordinator, mission_id, procedure_id)
  """
  def start_and_await_running(mission_id, procedure_id, opts \\ []) do
    alias Cadence.Procedures.Engine.ExecutionCoordinator

    case ExecutionCoordinator.start_execution(mission_id, procedure_id, opts) do
      {:ok, execution} ->
        subscribe_to_execution(execution.id)

        case await_status(:running, 5000) do
          {:ok, running_execution} -> {:ok, running_execution}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Starts a procedure and waits for full completion.
  Useful for simple happy-path tests.

  ## Examples

      {:ok, :completed, execution} = start_and_await_completion(mission_id, procedure_id)
  """
  def start_and_await_completion(mission_id, procedure_id, opts \\ []) do
    alias Cadence.Procedures.Engine.ExecutionCoordinator
    timeout = Keyword.get(opts, :timeout, 10_000)
    start_opts = Keyword.drop(opts, [:timeout])

    case ExecutionCoordinator.start_execution(mission_id, procedure_id, start_opts) do
      {:ok, execution} ->
        subscribe_to_execution(execution.id)
        await_completion(timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
