defmodule Cadence.Alarms.IntegrationTest do
  @moduledoc """
  Integration tests for the full alarm lifecycle.

  These tests verify end-to-end scenarios including:
  - Alarm creation through event processing
  - State transitions (acknowledge, shelve, clear)
  - Cache consistency throughout the lifecycle
  - PubSub event broadcasting
  """
  use Cadence.DataCase, async: false

  alias Cadence.Alarms
  alias Cadence.Recordings
  alias Cadence.Runtime.Alarms.AlarmManager
  alias Cadence.Runtime.Alarms.RuleCache
  alias Ecto.Adapters.SQL.Sandbox

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.TargetsFixtures
  import Cadence.AlarmsFixtures
  import Cadence.AccountsFixtures
  import Cadence.AlarmsHelpers
  import Cadence.AlarmsBuilders

  setup do
    # Use shared sandbox mode for GenServer database access
    Sandbox.mode(Cadence.Repo, {:shared, self()})

    org = organization_fixture()
    mission = mission_fixture(organization: org)
    target = target_fixture(organization: org, mission: mission)
    user = user_fixture(organization: org)

    # Start AlarmManager for this mission
    start_supervised!({AlarmManager, mission_id: mission.id, organization_id: org.id})

    # Create a default alarm rule
    rule =
      alarm_rule_fixture(
        organization: org,
        mission: mission,
        event_type: "telemetry_limit",
        conditions: %{"limit_state" => ["red", "yellow"]},
        enabled: true
      )

    # Ensure cache is fresh
    RuleCache.invalidate_mission(mission.id)

    %{org: org, mission: mission, target: target, user: user, rule: rule}
  end

  describe "full alarm lifecycle" do
    test "violation -> alarm -> acknowledge -> recovery -> clear", %{
      org: _org,
      mission: mission,
      target: target,
      user: user
    } do
      # Subscribe to alarm events
      subscribe_to_mission_alarms(mission.id)

      source_id = "HEALTH.cpu_temp_#{System.unique_integer([:positive])}"

      # Step 1: Send violation event
      event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :red,
          previous_state: :green,
          value: 100.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event})

      # Wait for alarm to be created
      {:ok, alarm} = await_alarm_triggered(5000)
      assert alarm.status == :active
      assert alarm.source_id == source_id
      assert alarm.current_value == 100.0

      # Verify alarm is in cache
      cached_alarms = AlarmManager.get_active_alarms(mission.id)
      assert Enum.any?(cached_alarms, &(&1.id == alarm.id))

      # Step 2: Acknowledge the alarm
      {:ok, acked_alarm} = Alarms.acknowledge_alarm(alarm, user.id, "Investigating")
      assert acked_alarm.status == :acknowledged
      assert acked_alarm.acknowledged_by_id == user.id

      # Wait for cache update and verify
      wait_for_alarm_manager(mission.id)
      Process.sleep(50)

      cached_alarm = Enum.find(AlarmManager.get_active_alarms(mission.id), &(&1.id == alarm.id))
      assert cached_alarm.status == :acknowledged

      # Step 3: Send recovery event
      recovery_event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :green,
          previous_state: :red,
          value: 50.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, recovery_event})

      # Wait for alarm to be cleared
      {:ok, cleared_alarm} = await_alarm_cleared(5000)
      assert cleared_alarm.id == alarm.id
      assert cleared_alarm.status == :cleared

      # Verify alarm is removed from cache
      wait_for_alarm_manager(mission.id)
      Process.sleep(50)

      cached_alarms_after = AlarmManager.get_active_alarms(mission.id)
      refute Enum.any?(cached_alarms_after, &(&1.id == alarm.id))

      # Verify alarm recordings were created
      recordings = Recordings.get_aggregate_history("Alarm", alarm.id)
      recordable_types = Enum.map(recordings, & &1.recordable_type)
      assert "AlarmTriggered" in recordable_types
      assert "AlarmAcknowledged" in recordable_types
      assert "AlarmCleared" in recordable_types
    end

    test "violation -> alarm -> shelve -> unshelve -> clear", %{
      org: _org,
      mission: mission,
      target: target,
      user: user
    } do
      subscribe_to_mission_alarms(mission.id)

      source_id = "POWER.voltage_#{System.unique_integer([:positive])}"

      # Step 1: Create alarm via violation
      event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :yellow,
          previous_state: :green,
          value: 85.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event})
      {:ok, alarm} = await_alarm_triggered(5000)
      assert alarm.status == :active

      # Step 2: Shelve the alarm
      {:ok, shelved_alarm} = Alarms.shelve_alarm(alarm, user.id, 30, "Maintenance window")
      assert shelved_alarm.status == :shelved
      assert shelved_alarm.shelved_by_id == user.id
      assert shelved_alarm.shelve_reason == "Maintenance window"

      # Verify shelved_until is set correctly (approximately 30 minutes from now)
      expected_until = DateTime.add(DateTime.utc_now(), 30 * 60, :second)
      diff = DateTime.diff(shelved_alarm.shelved_until, expected_until, :second)
      # Allow 5 seconds tolerance
      assert abs(diff) < 5

      # Step 3: Unshelve the alarm
      {:ok, unshelved_alarm} = Alarms.unshelve_alarm(shelved_alarm, user.id)
      assert unshelved_alarm.status == :active
      assert is_nil(unshelved_alarm.shelved_at)
      assert is_nil(unshelved_alarm.shelved_until)

      # Step 4: Clear via recovery
      recovery_event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :green,
          previous_state: :yellow,
          value: 70.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, recovery_event})
      {:ok, cleared_alarm} = await_alarm_cleared(5000)
      assert cleared_alarm.status == :cleared

      # Verify recording history
      recordings = Recordings.get_aggregate_history("Alarm", alarm.id)
      recordable_types = Enum.map(recordings, & &1.recordable_type)
      assert "AlarmTriggered" in recordable_types
      assert "AlarmShelved" in recordable_types
      assert "AlarmUnshelved" in recordable_types
      assert "AlarmCleared" in recordable_types
    end

    test "violation -> alarm -> escalation -> recovery -> clear", %{
      org: _org,
      mission: mission,
      target: target
    } do
      subscribe_to_mission_alarms(mission.id)

      source_id = "THERMAL.temp_#{System.unique_integer([:positive])}"

      # Step 1: Yellow violation
      yellow_event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :yellow,
          previous_state: :green,
          value: 80.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, yellow_event})
      {:ok, alarm} = await_alarm_triggered(5000)
      assert alarm.status == :active
      assert alarm.severity == :warning
      assert alarm.limit_state == :yellow

      # Step 2: Escalate to red
      red_event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :red,
          previous_state: :yellow,
          value: 100.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, red_event})
      {:ok, updated_alarm} = await_alarm_updated(5000)
      assert updated_alarm.id == alarm.id
      assert updated_alarm.severity == :critical
      assert updated_alarm.limit_state == :red
      assert updated_alarm.current_value == 100.0

      # Step 3: Recovery
      recovery_event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :green,
          previous_state: :red,
          value: 50.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, recovery_event})
      {:ok, cleared_alarm} = await_alarm_cleared(5000)
      assert cleared_alarm.status == :cleared

      # Verify escalation recording was recorded
      recordings = Recordings.get_aggregate_history("Alarm", alarm.id)
      recordable_types = Enum.map(recordings, & &1.recordable_type)
      assert "AlarmTriggered" in recordable_types
      assert "AlarmEscalated" in recordable_types or "AlarmValueUpdated" in recordable_types
      assert "AlarmCleared" in recordable_types
    end

    test "alarm deduplication - same source creates one alarm", %{
      mission: mission,
      target: target
    } do
      subscribe_to_mission_alarms(mission.id)

      source_id = "HEALTH.unique_item_#{System.unique_integer([:positive])}"

      # Send first violation
      event1 =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :red,
          previous_state: :green,
          value: 100.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event1})
      {:ok, alarm1} = await_alarm_triggered(5000)

      # Send second violation for same source
      event2 =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :red,
          previous_state: :red,
          value: 105.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event2})
      {:ok, updated_alarm} = await_alarm_updated(5000)

      # Should be same alarm, just updated
      assert updated_alarm.id == alarm1.id
      assert updated_alarm.current_value == 105.0

      # Verify only one alarm exists for this source
      alarms =
        Alarms.list_alarms(mission.id,
          status: [:active, :acknowledged, :shelved],
          source_id: source_id
        )
        |> Enum.filter(&(&1.target_id == target.id))

      assert length(alarms) == 1
    end

    test "cleared alarm allows new alarm for same source", %{
      mission: mission,
      target: target,
      user: user
    } do
      subscribe_to_mission_alarms(mission.id)

      source_id = "HEALTH.reoccurring_#{System.unique_integer([:positive])}"

      # Create first alarm
      event1 =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :red,
          previous_state: :green,
          value: 100.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event1})
      {:ok, alarm1} = await_alarm_triggered(5000)

      # Clear the alarm manually
      {:ok, _cleared} = Alarms.clear_alarm(alarm1, user.id)
      wait_for_alarm_manager(mission.id)

      # Flush old messages
      collect_alarm_messages(100)

      # Create new violation for same source
      event2 =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :red,
          previous_state: :green,
          value: 110.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event2})
      {:ok, alarm2} = await_alarm_triggered(5000)

      # Should be a new alarm
      assert alarm2.id != alarm1.id
      assert alarm2.source_id == source_id
      assert alarm2.current_value == 110.0
    end
  end

  describe "cache consistency" do
    test "cache stays consistent through all state transitions", %{
      org: _org,
      mission: mission,
      target: target,
      user: user
    } do
      subscribe_to_mission_alarms(mission.id)

      source_id = "HEALTH.cache_test_#{System.unique_integer([:positive])}"

      # Create alarm
      event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: source_id,
          new_state: :red,
          previous_state: :green,
          value: 100.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event})
      {:ok, alarm} = await_alarm_triggered(5000)

      # Helper to verify cache matches expected state
      verify_cache = fn expected_status ->
        wait_for_alarm_manager(mission.id)
        Process.sleep(50)
        cached = Enum.find(AlarmManager.get_active_alarms(mission.id), &(&1.id == alarm.id))

        if expected_status == :cleared do
          assert is_nil(cached), "Expected alarm to be removed from cache"
        else
          assert cached != nil, "Expected alarm to be in cache"

          assert cached.status == expected_status,
                 "Expected status #{expected_status}, got #{cached.status}"
        end
      end

      # Verify initial state
      verify_cache.(:active)

      # Acknowledge
      {:ok, _} = Alarms.acknowledge_alarm(alarm, user.id)
      verify_cache.(:acknowledged)

      # Shelve
      alarm = Alarms.get_alarm!(alarm.id)
      {:ok, _} = Alarms.shelve_alarm(alarm, user.id, 30)
      verify_cache.(:shelved)

      # Unshelve
      alarm = Alarms.get_alarm!(alarm.id)
      {:ok, _} = Alarms.unshelve_alarm(alarm, user.id)
      verify_cache.(:acknowledged)

      # Clear
      alarm = Alarms.get_alarm!(alarm.id)
      {:ok, _} = Alarms.clear_alarm(alarm, user.id)
      verify_cache.(:cleared)
    end
  end
end
