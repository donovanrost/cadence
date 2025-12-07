defmodule Cadence.AlarmsHelpers do
  @moduledoc """
  Test helpers for Alarms feature testing.

  Provides utilities for:
  - Async condition waiting (assert_eventually)
  - PubSub subscription and message collection for alarms
  - Alarm event waiting helpers
  - AlarmManager interaction helpers

  ## Usage

      import Cadence.AlarmsHelpers

      test "alarm is triggered on violation" do
        subscribe_to_mission_alarms(mission.id)

        send_limit_event(mission.id, "HEALTH.cpu_temp", :red, value: 105.0)

        {:ok, alarm} = await_alarm_triggered()
        assert alarm.severity == :critical
      end
  """

  import ExUnit.Assertions

  alias Cadence.Alarms.Engine.AlarmManager
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

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
        Alarms.get_alarm!(id).status == :acknowledged
      end, timeout: 5000)
  """
  def assert_eventually(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 10)
    message = Keyword.get(opts, :message, "Condition not met within #{timeout}ms")
    deadline = System.monotonic_time(:millisecond) + timeout

    do_assert_eventually(fun, deadline, interval, message)
  end

  defp do_assert_eventually(fun, deadline, interval, message) do
    try do
      if fun.() do
        :ok
      else
        maybe_retry_eventually(fun, deadline, interval, message)
      end
    rescue
      _ -> maybe_retry_eventually(fun, deadline, interval, message)
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

  @doc """
  Waits for a condition to become true, returning the result.
  Returns `:ok` or `{:error, :timeout}`.

  Unlike `assert_eventually/2`, this doesn't fail - use when you need
  to handle the timeout case gracefully.
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
  # PubSub Subscription Helpers
  # ============================================================================

  @doc """
  Subscribes the test process to a mission's alarms PubSub topic.

  ## Examples

      subscribe_to_mission_alarms(mission.id)
      # Now receive messages like {:alarm_triggered, alarm}
  """
  def subscribe_to_mission_alarms(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
  end

  @doc """
  Subscribes the test process to the global alarm rules changed topic.
  """
  def subscribe_to_alarm_rules do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "alarm_rules:changed")
  end

  @doc """
  Subscribes to a mission's alarm rules topic.
  """
  def subscribe_to_mission_alarm_rules(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarm_rules")
  end

  @doc """
  Subscribes to mission events (where TelemetryLimitEvents are published).
  """
  def subscribe_to_mission_events(mission_id) do
    Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:events")
  end

  # ============================================================================
  # Message Collection Helpers
  # ============================================================================

  @doc """
  Collects all messages received within a timeout period.
  Useful for verifying a sequence of broadcasts.

  ## Examples

      subscribe_to_mission_alarms(mission.id)
      # ... trigger events ...
      messages = collect_messages(500)
      assert {:alarm_triggered, _} in messages
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

      alarm_messages = collect_matching(500, fn
        {:alarm_triggered, _} -> true
        {:alarm_cleared, _} -> true
        _ -> false
      end)
  """
  def collect_matching(timeout, match_fun) do
    collect_messages(timeout)
    |> Enum.filter(match_fun)
  end

  @doc """
  Collects all alarm-related messages.
  """
  def collect_alarm_messages(timeout \\ 500) do
    collect_matching(timeout, fn
      {:alarm_triggered, _} -> true
      {:alarm_updated, _} -> true
      {:alarm_acknowledged, _} -> true
      {:alarm_shelved, _} -> true
      {:alarm_unshelved, _} -> true
      {:alarm_cleared, _} -> true
      _ -> false
    end)
  end

  # ============================================================================
  # Alarm Event Waiting Helpers
  # ============================================================================

  @doc """
  Waits for an alarm_triggered message.

  ## Examples

      subscribe_to_mission_alarms(mission.id)
      {:ok, alarm} = await_alarm_triggered()
  """
  def await_alarm_triggered(timeout \\ 5000) do
    receive do
      {:alarm_triggered, alarm} ->
        {:ok, alarm}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for an alarm_updated message.
  """
  def await_alarm_updated(timeout \\ 5000) do
    receive do
      {:alarm_updated, alarm} ->
        {:ok, alarm}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for an alarm_acknowledged message.
  """
  def await_alarm_acknowledged(timeout \\ 5000) do
    receive do
      {:alarm_acknowledged, alarm} ->
        {:ok, alarm}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for an alarm_shelved message.
  """
  def await_alarm_shelved(timeout \\ 5000) do
    receive do
      {:alarm_shelved, alarm} ->
        {:ok, alarm}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for an alarm_unshelved message.
  """
  def await_alarm_unshelved(timeout \\ 5000) do
    receive do
      {:alarm_unshelved, alarm} ->
        {:ok, alarm}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for an alarm_cleared message.
  """
  def await_alarm_cleared(timeout \\ 5000) do
    receive do
      {:alarm_cleared, alarm} ->
        {:ok, alarm}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for any alarm event message.

  Returns `{:ok, event_type, alarm}` or `{:error, :timeout}`.
  """
  def await_any_alarm_event(timeout \\ 5000) do
    receive do
      {:alarm_triggered, alarm} -> {:ok, :triggered, alarm}
      {:alarm_updated, alarm} -> {:ok, :updated, alarm}
      {:alarm_acknowledged, alarm} -> {:ok, :acknowledged, alarm}
      {:alarm_shelved, alarm} -> {:ok, :shelved, alarm}
      {:alarm_unshelved, alarm} -> {:ok, :unshelved, alarm}
      {:alarm_cleared, alarm} -> {:ok, :cleared, alarm}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for a specific alarm by ID.

  ## Examples

      {:ok, :cleared, alarm} = await_alarm_by_id(alarm.id)
  """
  def await_alarm_by_id(alarm_id, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_alarm_by_id(alarm_id, deadline)
  end

  defp do_await_alarm_by_id(alarm_id, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {event_type, %{id: ^alarm_id} = alarm} when event_type in [
        :alarm_triggered,
        :alarm_updated,
        :alarm_acknowledged,
        :alarm_shelved,
        :alarm_unshelved,
        :alarm_cleared
      ] ->
        {:ok, event_type, alarm}

      {_event_type, %{id: _other_id}} ->
        # Different alarm, keep waiting
        do_await_alarm_by_id(alarm_id, deadline)
    after
      remaining ->
        {:error, :timeout}
    end
  end

  # ============================================================================
  # AlarmManager Helpers
  # ============================================================================

  @doc """
  Waits for the AlarmManager to process all pending messages.

  This is useful when you need to ensure events have been fully processed
  before making assertions about state.

  ## Examples

      send_limit_event(mission_id, "HEALTH.temp", :red)
      wait_for_alarm_manager(mission_id)
      assert length(AlarmManager.get_active_alarms(mission_id)) == 1
  """
  def wait_for_alarm_manager(mission_id, timeout \\ 5000) do
    case AlarmManager.whereis(mission_id) do
      nil ->
        {:error, :not_running}

      pid ->
        try do
          # sys:get_state is synchronous - when it returns, all prior messages
          # in the mailbox have been processed
          :sys.get_state(pid, timeout)
          :ok
        catch
          :exit, {:timeout, _} -> {:error, :timeout}
        end
    end
  end

  @doc """
  Sends a TelemetryLimitEvent to the AlarmManager for a mission.

  This is a convenience function for tests that need to trigger alarm
  processing without going through the full telemetry pipeline.

  ## Options

  - `:target_id` - Target identifier (default: generates UUID)
  - `:value` - Telemetry value (default: 100.0)
  - `:previous_state` - Previous limit state (default: :green)
  - `:limit_set` - Limit set name (default: "NOMINAL")
  - `:timestamp` - Event timestamp (default: now)

  ## Examples

      send_limit_event(mission_id, "HEALTH.cpu_temp", :red)
      send_limit_event(mission_id, "POWER.voltage", :yellow, value: 3.2)
  """
  def send_limit_event(mission_id, item_name, new_state, opts \\ []) do
    event = TelemetryLimitEvent.new(%{
      mission_id: mission_id,
      target_id: Keyword.get(opts, :target_id, Ecto.UUID.generate()),
      item_name: item_name,
      previous_state: Keyword.get(opts, :previous_state, :green),
      new_state: new_state,
      value: Keyword.get(opts, :value, 100.0),
      limit_set: Keyword.get(opts, :limit_set, "NOMINAL"),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    })

    case AlarmManager.whereis(mission_id) do
      nil ->
        {:error, :alarm_manager_not_running}

      pid ->
        send(pid, {:limit_event, event})
        {:ok, event}
    end
  end

  @doc """
  Sends a recovery event (transition to green) to the AlarmManager.

  ## Examples

      send_recovery_event(mission_id, "HEALTH.cpu_temp", :red)
  """
  def send_recovery_event(mission_id, item_name, previous_state, opts \\ []) do
    send_limit_event(
      mission_id,
      item_name,
      :green,
      Keyword.merge(opts, previous_state: previous_state, value: 75.0)
    )
  end

  @doc """
  Sends an escalation event (yellow -> red) to the AlarmManager.
  """
  def send_escalation_event(mission_id, item_name, opts \\ []) do
    send_limit_event(
      mission_id,
      item_name,
      :red,
      Keyword.merge(opts, previous_state: :yellow, value: 105.0)
    )
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
        flunk("Process exited with #{inspect(actual_reason)}, expected #{inspect(expected_reason)}")
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
  # Alarm Lifecycle Helpers
  # ============================================================================

  @doc """
  Sends a violation event and waits for the alarm to be triggered.

  Combines common test pattern.

  ## Examples

      {:ok, alarm, event} = trigger_alarm(mission_id, "HEALTH.cpu_temp", :red)
  """
  def trigger_alarm(mission_id, item_name, new_state \\ :red, opts \\ []) do
    subscribe_to_mission_alarms(mission_id)

    case send_limit_event(mission_id, item_name, new_state, opts) do
      {:ok, event} ->
        case await_alarm_triggered() do
          {:ok, alarm} -> {:ok, alarm, event}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a recovery event and waits for the alarm to be cleared.

  ## Examples

      {:ok, cleared_alarm} = clear_alarm_via_recovery(mission_id, "HEALTH.cpu_temp", :red)
  """
  def clear_alarm_via_recovery(mission_id, item_name, previous_state, opts \\ []) do
    subscribe_to_mission_alarms(mission_id)

    case send_recovery_event(mission_id, item_name, previous_state, opts) do
      {:ok, _event} ->
        await_alarm_cleared()

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Assertion Helpers
  # ============================================================================

  @doc """
  Asserts that the ETS cache matches the database for a mission.

  Use this after concurrent operations to verify cache consistency.
  """
  def assert_cache_consistent(mission_id) do
    cached = AlarmManager.get_active_alarms(mission_id)
    db_alarms = Cadence.Alarms.list_active_alarms(mission_id)

    cached_ids = cached |> Enum.map(& &1.id) |> Enum.sort()
    db_ids = db_alarms |> Enum.map(& &1.id) |> Enum.sort()

    assert cached_ids == db_ids,
           "Cache mismatch. Cache: #{inspect(cached_ids)}, DB: #{inspect(db_ids)}"
  end

  @doc """
  Asserts that only one active alarm exists for a given source.

  Use this to verify the deduplication invariant.
  """
  def assert_single_active_alarm(mission_id, source_type, source_id, target_id \\ nil) do
    alarms =
      Cadence.Alarms.list_alarms(mission_id,
        status: [:active, :acknowledged, :shelved],
        source_id: source_id
      )
      |> Enum.filter(fn a ->
        a.source_type == source_type and a.target_id == target_id
      end)

    assert length(alarms) <= 1,
           "Expected at most 1 active alarm for #{source_type}:#{source_id}, found #{length(alarms)}"
  end
end
