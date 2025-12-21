defmodule Cadence.Application.Alerting.AlarmOperationsTest do
  @moduledoc """
  Use case tests for AlarmOperations.

  These tests use fake adapters (in-memory repositories, fake event publishers)
  to test the application layer without a database. This provides fast,
  isolated tests that verify the orchestration logic.
  """
  use Cadence.PureCase, async: false

  alias Cadence.Application.Alerting.AlarmOperations
  alias Cadence.Domain.Alerting.Entities.Alarm
  alias Cadence.Test.Adapters.InMemoryAlarmRepository
  alias Cadence.Test.Adapters.FakeEventPublisher
  alias Cadence.Test.Adapters.InMemoryEventRecorder

  setup do
    # Start fake adapters
    {:ok, _} = InMemoryAlarmRepository.start_link()
    {:ok, _} = FakeEventPublisher.start_link()
    {:ok, _} = InMemoryEventRecorder.start_link()

    # Configure DI to use fakes
    Application.put_env(:cadence, :alarm_repository, InMemoryAlarmRepository)
    Application.put_env(:cadence, :event_publisher, FakeEventPublisher)
    Application.put_env(:cadence, :event_recorder, InMemoryEventRecorder)

    on_exit(fn ->
      Application.delete_env(:cadence, :alarm_repository)
      Application.delete_env(:cadence, :event_publisher)
      Application.delete_env(:cadence, :event_recorder)
      InMemoryAlarmRepository.stop()
      FakeEventPublisher.stop()
      InMemoryEventRecorder.stop()
    end)

    :ok
  end

  describe "acknowledge/3" do
    test "acknowledges an active alarm" do
      alarm = insert_active_alarm()

      {:ok, acked} = AlarmOperations.acknowledge(alarm.id, "user-123", "Investigating")

      assert acked.status == :acknowledged
      assert acked.acknowledged_by_id == "user-123"
      assert acked.acknowledgment_note == "Investigating"
    end

    test "publishes alarm_changed event" do
      alarm = insert_active_alarm()

      {:ok, _acked} = AlarmOperations.acknowledge(alarm.id, "user-123", nil)

      events = FakeEventPublisher.list_events()
      assert length(events) >= 1

      event_entry = List.first(events)
      assert event_entry.topic =~ "mission:"
      assert event_entry.event.type == :alarm_changed
      assert event_entry.event.event == :acknowledged
    end

    test "records the acknowledgment event" do
      alarm = insert_active_alarm()

      {:ok, _acked} = AlarmOperations.acknowledge(alarm.id, "user-123", "Note")

      assert InMemoryEventRecorder.recorded?(:alarm_acknowledged)
    end

    test "returns error for non-existent alarm" do
      result = AlarmOperations.acknowledge(random_id(), "user-123", nil)

      assert {:error, :not_found} = result
    end

    test "returns error for already acknowledged alarm" do
      alarm = insert_acknowledged_alarm()

      result = AlarmOperations.acknowledge(alarm.id, "user-123", nil)

      assert {:error, {:invalid_transition, :acknowledged, :acknowledged}} = result
    end
  end

  describe "shelve/4" do
    test "shelves an active alarm" do
      alarm = insert_active_alarm()

      {:ok, shelved} = AlarmOperations.shelve(alarm.id, "user-123", 30, "Known issue")

      assert shelved.status == :shelved
      assert shelved.shelved_by_id == "user-123"
      assert shelved.shelve_reason == "Known issue"
      assert shelved.shelved_until != nil
    end

    test "shelves an acknowledged alarm" do
      alarm = insert_acknowledged_alarm()

      {:ok, shelved} = AlarmOperations.shelve(alarm.id, "user-123", 60, nil)

      assert shelved.status == :shelved
    end

    test "returns error for invalid duration" do
      alarm = insert_active_alarm()

      result = AlarmOperations.shelve(alarm.id, "user-123", 0, nil)

      assert {:error, :invalid_duration} = result
    end

    test "publishes event on shelve" do
      alarm = insert_active_alarm()

      {:ok, _shelved} = AlarmOperations.shelve(alarm.id, "user-123", 30, nil)

      events = FakeEventPublisher.list_events()
      assert length(events) >= 1
    end
  end

  describe "unshelve/2" do
    test "unshelves a shelved alarm back to active" do
      alarm = insert_shelved_alarm(:active)

      {:ok, unshelved} = AlarmOperations.unshelve(alarm.id, "user-123")

      assert unshelved.status == :active
      assert unshelved.shelved_at == nil
      assert unshelved.shelved_until == nil
    end

    test "unshelves back to acknowledged if that was previous state" do
      alarm = insert_shelved_alarm(:acknowledged)

      {:ok, unshelved} = AlarmOperations.unshelve(alarm.id, nil)

      assert unshelved.status == :acknowledged
    end

    test "returns error for non-shelved alarm" do
      alarm = insert_active_alarm()

      result = AlarmOperations.unshelve(alarm.id, nil)

      assert {:error, {:not_shelved, :active}} = result
    end
  end

  describe "clear/2" do
    test "clears an active alarm" do
      alarm = insert_active_alarm()

      {:ok, cleared} = AlarmOperations.clear(alarm.id, "user-123")

      assert cleared.status == :cleared
      assert cleared.cleared_at != nil
    end

    test "clears an acknowledged alarm" do
      alarm = insert_acknowledged_alarm()

      {:ok, cleared} = AlarmOperations.clear(alarm.id, nil)

      assert cleared.status == :cleared
    end

    test "clears a shelved alarm" do
      alarm = insert_shelved_alarm(:active)

      {:ok, cleared} = AlarmOperations.clear(alarm.id, nil)

      assert cleared.status == :cleared
    end

    test "returns error for already cleared alarm" do
      alarm = insert_cleared_alarm()

      result = AlarmOperations.clear(alarm.id, nil)

      assert {:error, {:invalid_transition, :cleared, :cleared}} = result
    end

    test "records clear event" do
      alarm = insert_active_alarm()

      {:ok, _cleared} = AlarmOperations.clear(alarm.id, nil)

      assert InMemoryEventRecorder.recorded?(:alarm_cleared)
    end
  end

  describe "escalate/2" do
    test "escalates from info to warning" do
      alarm = insert_active_alarm(severity: :info)

      {:ok, escalated} = AlarmOperations.escalate(alarm.id, :warning)

      assert escalated.severity == :warning
    end

    test "escalates from warning to critical" do
      alarm = insert_active_alarm(severity: :warning)

      {:ok, escalated} = AlarmOperations.escalate(alarm.id, :critical)

      assert escalated.severity == :critical
    end

    test "records escalation event" do
      alarm = insert_active_alarm(severity: :info)

      {:ok, _escalated} = AlarmOperations.escalate(alarm.id, :warning)

      assert InMemoryEventRecorder.recorded?(:alarm_escalated)
    end

    test "returns error for de-escalation attempt" do
      alarm = insert_active_alarm(severity: :critical)

      result = AlarmOperations.escalate(alarm.id, :warning)

      assert {:error, :cannot_deescalate} = result
    end
  end

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp insert_active_alarm(opts \\ []) do
    {:ok, alarm} =
      Alarm.new(%{
        organization_id: random_id(),
        mission_id: random_id(),
        target_id: Keyword.get(opts, :target_id, random_id()),
        alarm_type: "test_alarm",
        severity: Keyword.get(opts, :severity, :warning),
        source_type: "telemetry_item",
        source_id: random_id(),
        message: "Test alarm message",
        current_value: 100.0,
        triggered_at: now()
      })

    InMemoryAlarmRepository.insert(alarm)
  end

  defp insert_acknowledged_alarm(opts \\ []) do
    alarm = insert_active_alarm(opts)
    {:ok, acked} = Alarm.acknowledge(alarm, "ack-user", nil)
    InMemoryAlarmRepository.save(acked)
    acked
  end

  defp insert_shelved_alarm(previous_status, opts \\ []) do
    alarm =
      case previous_status do
        :active -> insert_active_alarm(opts)
        :acknowledged -> insert_acknowledged_alarm(opts)
      end

    {:ok, shelved} = Alarm.shelve(alarm, "shelve-user", 60, "Test shelve")
    InMemoryAlarmRepository.save(shelved)
    shelved
  end

  defp insert_cleared_alarm(opts \\ []) do
    alarm = insert_active_alarm(opts)
    {:ok, cleared} = Alarm.clear(alarm)
    InMemoryAlarmRepository.save(cleared)
    cleared
  end
end
