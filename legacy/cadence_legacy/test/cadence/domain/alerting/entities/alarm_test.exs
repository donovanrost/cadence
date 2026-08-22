defmodule Cadence.Domain.Alerting.Entities.AlarmTest do
  @moduledoc """
  Pure unit tests for the Alarm domain entity.

  These tests run without database access, demonstrating that
  the domain logic is independent of persistence.
  """
  use Cadence.PureCase

  alias Cadence.Domain.Alerting.Entities.Alarm

  # ===========================================================================
  # Test Helpers
  # ===========================================================================

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: random_id(),
        organization_id: random_id(),
        mission_id: random_id(),
        alarm_type: "telemetry_limit",
        severity: :warning,
        source_type: "telemetry_item",
        source_id: "HEALTH.cpu_temp",
        triggered_at: now()
      },
      overrides
    )
  end

  defp create_alarm(overrides \\ %{}) do
    {:ok, alarm} = Alarm.new(valid_attrs(overrides))
    alarm
  end

  # ===========================================================================
  # Construction Tests
  # ===========================================================================

  describe "new/1" do
    test "creates an alarm with valid attributes" do
      attrs = valid_attrs()

      assert {:ok, alarm} = Alarm.new(attrs)
      assert alarm.organization_id == attrs.organization_id
      assert alarm.mission_id == attrs.mission_id
      assert alarm.alarm_type == "telemetry_limit"
      assert alarm.severity == :warning
      assert alarm.status == :active
      assert alarm.source_type == "telemetry_item"
      assert alarm.source_id == "HEALTH.cpu_temp"
    end

    test "sets initial status to :active" do
      {:ok, alarm} = Alarm.new(valid_attrs())
      assert alarm.status == :active
    end

    test "defaults source_origin to :rule" do
      {:ok, alarm} = Alarm.new(valid_attrs())
      assert alarm.source_origin == :rule
    end

    test "defaults metadata to empty map" do
      {:ok, alarm} = Alarm.new(valid_attrs())
      assert alarm.metadata == %{}
    end

    test "fails with missing required fields" do
      assert {:error, {:missing_required, missing}} = Alarm.new(%{})
      assert :organization_id in missing
      assert :mission_id in missing
      assert :alarm_type in missing
      assert :severity in missing
    end

    test "fails with invalid severity" do
      attrs = valid_attrs(%{severity: :extreme})
      assert {:error, :invalid_severity} = Alarm.new(attrs)
    end

    test "fails with invalid source_origin" do
      attrs = valid_attrs(%{source_origin: :unknown})
      assert {:error, {:invalid_source_origin, :unknown}} = Alarm.new(attrs)
    end

    test "accepts optional fields" do
      attrs =
        valid_attrs(%{
          target_id: random_id(),
          alarm_rule_id: random_id(),
          message: "CPU temp exceeded threshold",
          current_value: 85.5,
          limit_state: :yellow,
          metadata: %{"threshold" => 80}
        })

      {:ok, alarm} = Alarm.new(attrs)
      assert alarm.target_id == attrs.target_id
      assert alarm.message == "CPU temp exceeded threshold"
      assert alarm.current_value == 85.5
      assert alarm.limit_state == :yellow
      assert alarm.metadata == %{"threshold" => 80}
    end
  end

  # ===========================================================================
  # State Transition Tests
  # ===========================================================================

  describe "acknowledge/3" do
    test "transitions from active to acknowledged" do
      alarm = create_alarm()
      user_id = random_id()

      assert {:ok, acked} = Alarm.acknowledge(alarm, user_id, "Investigating")
      assert acked.status == :acknowledged
      assert acked.acknowledged_by_id == user_id
      assert acked.acknowledgment_note == "Investigating"
      assert acked.acknowledged_at != nil
    end

    test "allows system acknowledgment with nil user_id" do
      alarm = create_alarm()

      assert {:ok, acked} = Alarm.acknowledge(alarm, nil)
      assert acked.status == :acknowledged
      assert acked.acknowledged_by_id == nil
    end

    test "fails when already cleared" do
      alarm = create_alarm()
      {:ok, cleared} = Alarm.clear(alarm)

      assert {:error, {:invalid_transition, :cleared, :acknowledged}} =
               Alarm.acknowledge(cleared, random_id())
    end
  end

  describe "shelve/4" do
    test "transitions from active to shelved" do
      alarm = create_alarm()
      user_id = random_id()

      assert {:ok, shelved} = Alarm.shelve(alarm, user_id, 30, "Known transient")
      assert shelved.status == :shelved
      assert shelved.shelved_by_id == user_id
      assert shelved.shelve_reason == "Known transient"
      assert shelved.shelved_at != nil
      assert shelved.shelved_until != nil
    end

    test "transitions from acknowledged to shelved" do
      alarm = create_alarm()
      {:ok, acked} = Alarm.acknowledge(alarm, random_id())

      assert {:ok, shelved} = Alarm.shelve(acked, random_id(), 60)
      assert shelved.status == :shelved
    end

    test "calculates shelved_until correctly" do
      alarm = create_alarm()
      before = DateTime.utc_now()

      {:ok, shelved} = Alarm.shelve(alarm, random_id(), 30)

      after_time = DateTime.utc_now()
      expected_min = DateTime.add(before, 30 * 60, :second)
      expected_max = DateTime.add(after_time, 30 * 60, :second)

      assert DateTime.compare(shelved.shelved_until, expected_min) in [:eq, :gt]
      assert DateTime.compare(shelved.shelved_until, expected_max) in [:eq, :lt]
    end

    test "fails with invalid duration" do
      alarm = create_alarm()

      assert {:error, :invalid_duration} = Alarm.shelve(alarm, random_id(), 0)
      assert {:error, :invalid_duration} = Alarm.shelve(alarm, random_id(), -10)
    end

    test "fails when already cleared" do
      alarm = create_alarm()
      {:ok, cleared} = Alarm.clear(alarm)

      assert {:error, {:invalid_transition, :cleared, :shelved}} =
               Alarm.shelve(cleared, random_id(), 30)
    end
  end

  describe "unshelve/2" do
    test "returns to active if never acknowledged" do
      alarm = create_alarm()
      {:ok, shelved} = Alarm.shelve(alarm, random_id(), 30)

      assert {:ok, unshelved} = Alarm.unshelve(shelved)
      assert unshelved.status == :active
      assert unshelved.shelved_at == nil
      assert unshelved.shelved_until == nil
    end

    test "returns to acknowledged if previously acknowledged" do
      alarm = create_alarm()
      {:ok, acked} = Alarm.acknowledge(alarm, random_id())
      {:ok, shelved} = Alarm.shelve(acked, random_id(), 30)

      assert {:ok, unshelved} = Alarm.unshelve(shelved)
      assert unshelved.status == :acknowledged
    end

    test "allows explicit target status" do
      alarm = create_alarm()
      {:ok, shelved} = Alarm.shelve(alarm, random_id(), 30)

      assert {:ok, unshelved} = Alarm.unshelve(shelved, :acknowledged)
      assert unshelved.status == :acknowledged
    end

    test "fails when not shelved" do
      alarm = create_alarm()

      assert {:error, {:not_shelved, :active}} = Alarm.unshelve(alarm)
    end
  end

  describe "clear/1" do
    test "transitions from active to cleared" do
      alarm = create_alarm()

      assert {:ok, cleared} = Alarm.clear(alarm)
      assert cleared.status == :cleared
      assert cleared.cleared_at != nil
    end

    test "transitions from acknowledged to cleared" do
      alarm = create_alarm()
      {:ok, acked} = Alarm.acknowledge(alarm, random_id())

      assert {:ok, cleared} = Alarm.clear(acked)
      assert cleared.status == :cleared
    end

    test "transitions from shelved to cleared" do
      alarm = create_alarm()
      {:ok, shelved} = Alarm.shelve(alarm, random_id(), 30)

      assert {:ok, cleared} = Alarm.clear(shelved)
      assert cleared.status == :cleared
    end

    test "fails when already cleared (idempotent check)" do
      alarm = create_alarm()
      {:ok, cleared} = Alarm.clear(alarm)

      assert {:error, {:invalid_transition, :cleared, :cleared}} = Alarm.clear(cleared)
    end
  end

  # ===========================================================================
  # Value Update Tests
  # ===========================================================================

  describe "update_value/3" do
    test "updates current value" do
      alarm = create_alarm(%{current_value: 80.0})

      assert {:ok, updated} = Alarm.update_value(alarm, 85.5)
      assert updated.current_value == 85.5
      assert updated.last_value_at != nil
    end

    test "optionally updates severity" do
      alarm = create_alarm(%{severity: :warning})

      assert {:ok, updated} = Alarm.update_value(alarm, 95.0, severity: :critical)
      assert updated.severity == :critical
    end

    test "optionally updates limit_state" do
      alarm = create_alarm(%{limit_state: :yellow})

      assert {:ok, updated} = Alarm.update_value(alarm, 95.0, limit_state: :red)
      assert updated.limit_state == :red
    end
  end

  describe "escalate/2" do
    test "escalates from info to warning" do
      alarm = create_alarm(%{severity: :info})

      assert {:ok, escalated} = Alarm.escalate(alarm, :warning)
      assert escalated.severity == :warning
    end

    test "escalates from warning to critical" do
      alarm = create_alarm(%{severity: :warning})

      assert {:ok, escalated} = Alarm.escalate(alarm, :critical)
      assert escalated.severity == :critical
    end

    test "fails to de-escalate" do
      alarm = create_alarm(%{severity: :critical})

      assert {:error, :cannot_deescalate} = Alarm.escalate(alarm, :warning)
    end

    test "fails to escalate to same level" do
      alarm = create_alarm(%{severity: :warning})

      assert {:error, :cannot_deescalate} = Alarm.escalate(alarm, :warning)
    end
  end

  # ===========================================================================
  # Query Tests
  # ===========================================================================

  describe "active?/1" do
    test "returns true for active alarm" do
      alarm = create_alarm()
      assert Alarm.active?(alarm) == true
    end

    test "returns true for acknowledged alarm" do
      alarm = create_alarm()
      {:ok, acked} = Alarm.acknowledge(alarm, random_id())
      assert Alarm.active?(acked) == true
    end

    test "returns true for shelved alarm" do
      alarm = create_alarm()
      {:ok, shelved} = Alarm.shelve(alarm, random_id(), 30)
      assert Alarm.active?(shelved) == true
    end

    test "returns false for cleared alarm" do
      alarm = create_alarm()
      {:ok, cleared} = Alarm.clear(alarm)
      assert Alarm.active?(cleared) == false
    end
  end

  describe "shelve_expired?/1" do
    test "returns false when not shelved" do
      alarm = create_alarm()
      assert Alarm.shelve_expired?(alarm) == false
    end

    test "returns false when shelve period not expired" do
      alarm = create_alarm()
      {:ok, shelved} = Alarm.shelve(alarm, random_id(), 30)
      assert Alarm.shelve_expired?(shelved) == false
    end

    test "returns true when shelve period has expired" do
      alarm = create_alarm()
      # Create a shelved alarm with shelved_until in the past
      shelved = %{
        alarm
        | status: :shelved,
          shelved_at: ago(2, :hours),
          shelved_until: ago(1, :hour)
      }

      assert Alarm.shelve_expired?(shelved) == true
    end
  end

  describe "source_key/1" do
    test "returns tuple of source_type and source_id" do
      alarm = create_alarm(%{source_type: "telemetry_item", source_id: "HEALTH.temp"})

      assert Alarm.source_key(alarm) == {"telemetry_item", "HEALTH.temp"}
    end
  end

  describe "duration/1" do
    test "returns seconds since triggered" do
      alarm = create_alarm(%{triggered_at: ago(5, :minutes)})

      duration = Alarm.duration(alarm)
      # Allow some tolerance for test execution time
      assert duration >= 299
      assert duration <= 301
    end
  end
end
