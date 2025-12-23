defmodule Cadence.Runtime.Alarms.AlarmManagerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Runtime.Alarms.AlarmManager
  alias Cadence.Alarms.Alarm
  alias Cadence.Telemetry.Events.TelemetryLimitEvent

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.TargetsFixtures
  import Cadence.AlarmsFixtures

  describe "start_link/1" do
    test "starts the alarm manager for a mission" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end

    test "registers in the MissionRegistry" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      assert AlarmManager.whereis(mission.id) == pid

      GenServer.stop(pid)
    end
  end

  describe "get_active_alarms/1" do
    test "returns empty list when no alarms" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      assert AlarmManager.get_active_alarms(mission.id) == []

      GenServer.stop(pid)
    end

    test "returns active alarms loaded from database" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Create alarms before starting manager
      alarm1 = alarm_fixture(organization: org, mission: mission)
      alarm2 = alarm_fixture(organization: org, mission: mission)
      _cleared = cleared_alarm_fixture(organization: org, mission: mission)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      active_alarms = AlarmManager.get_active_alarms(mission.id)

      assert length(active_alarms) == 2
      alarm_ids = Enum.map(active_alarms, & &1.id)
      assert alarm1.id in alarm_ids
      assert alarm2.id in alarm_ids

      GenServer.stop(pid)
    end

    test "includes acknowledged and shelved alarms" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      active = alarm_fixture(organization: org, mission: mission)
      acked = acknowledged_alarm_fixture(organization: org, mission: mission)
      shelved = shelved_alarm_fixture(organization: org, mission: mission)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      active_alarms = AlarmManager.get_active_alarms(mission.id)

      assert length(active_alarms) == 3
      alarm_ids = Enum.map(active_alarms, & &1.id)
      assert active.id in alarm_ids
      assert acked.id in alarm_ids
      assert shelved.id in alarm_ids

      GenServer.stop(pid)
    end
  end

  describe "get_alarm_counts/1" do
    test "returns zero counts when no alarms" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      counts = AlarmManager.get_alarm_counts(mission.id)

      assert counts == %{critical: 0, warning: 0, info: 0}

      GenServer.stop(pid)
    end

    test "returns counts by severity" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      alarm_fixture(organization: org, mission: mission, severity: :warning)
      alarm_fixture(organization: org, mission: mission, severity: :warning)
      critical_alarm_fixture(organization: org, mission: mission)
      alarm_fixture(organization: org, mission: mission, severity: :info)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      counts = AlarmManager.get_alarm_counts(mission.id)

      assert counts.critical == 1
      assert counts.warning == 2
      assert counts.info == 1

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 for limit events" do
    setup do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      target = target_fixture(organization: org, mission: mission)

      # Create a rule that matches
      rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          conditions: %{"limit_state" => ["red", "yellow"]}
        )

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{org: org, mission: mission, target: target, rule: rule, pid: pid}
    end

    test "creates alarm on limit violation", %{mission: mission, target: target} do
      # Subscribe to alarm broadcasts
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:alarms")

      event =
        TelemetryLimitEvent.new(%{
          mission_id: mission.id,
          target_id: target.id,
          item_name: "HEALTH.cpu_temp",
          previous_state: :green,
          new_state: :red,
          value: 105.0,
          limit_set: "NOMINAL"
        })

      # Send the event
      send(AlarmManager.whereis(mission.id), {:limit_event, event})

      # Should receive alarm_triggered broadcast
      assert_receive {:alarm_triggered, %Alarm{} = alarm}, 1000

      assert alarm.source_id == "HEALTH.cpu_temp"
      assert alarm.limit_state == :red
      assert alarm.current_value == 105.0
      assert alarm.status == :active

      # Should be in the cache
      active = AlarmManager.get_active_alarms(mission.id)
      assert Enum.any?(active, &(&1.id == alarm.id))
    end
  end

  describe "alarm recovery" do
    test "clears alarm on recovery" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      target = target_fixture(organization: org, mission: mission)

      # Create a matching rule
      alarm_rule_fixture(
        organization: org,
        mission: mission,
        conditions: %{"limit_state" => ["red", "yellow"]}
      )

      # Create existing alarm
      alarm =
        alarm_fixture(
          organization: org,
          mission: mission,
          target: target,
          source_type: "telemetry_item",
          source_id: "HEALTH.cpu_temp",
          limit_state: :red
        )

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:alarms")

      # Verify alarm is in cache
      assert Enum.any?(AlarmManager.get_active_alarms(mission.id), &(&1.id == alarm.id))

      # Send recovery event
      recovery_event =
        TelemetryLimitEvent.new(%{
          mission_id: mission.id,
          target_id: target.id,
          item_name: "HEALTH.cpu_temp",
          previous_state: :red,
          new_state: :green,
          value: 75.0,
          limit_set: "NOMINAL"
        })

      send(pid, {:limit_event, recovery_event})

      # Should receive alarm_cleared broadcast
      assert_receive {:alarm_cleared, %Alarm{} = cleared}, 1000

      assert cleared.id == alarm.id
      assert cleared.status == :cleared

      # Should no longer be in cache
      refute Enum.any?(AlarmManager.get_active_alarms(mission.id), &(&1.id == alarm.id))

      GenServer.stop(pid)
    end
  end

  describe "alarm escalation" do
    test "updates alarm on continued violation" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      target = target_fixture(organization: org, mission: mission)

      # Create a matching rule
      alarm_rule_fixture(
        organization: org,
        mission: mission,
        conditions: %{"limit_state" => ["red", "yellow"]}
      )

      # Create existing alarm
      alarm =
        alarm_fixture(
          organization: org,
          mission: mission,
          target: target,
          source_type: "telemetry_item",
          source_id: "HEALTH.cpu_temp",
          limit_state: :yellow,
          current_value: 85.0,
          severity: :warning
        )

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:alarms")

      # Send escalation event (yellow -> red)
      escalation_event =
        TelemetryLimitEvent.new(%{
          mission_id: mission.id,
          target_id: target.id,
          item_name: "HEALTH.cpu_temp",
          previous_state: :yellow,
          new_state: :red,
          value: 105.0,
          limit_set: "NOMINAL"
        })

      send(pid, {:limit_event, escalation_event})

      # Should receive alarm_updated broadcast
      assert_receive {:alarm_updated, %Alarm{} = updated}, 1000

      assert updated.id == alarm.id
      assert updated.limit_state == :red
      assert updated.current_value == 105.0
      # Severity should escalate
      assert updated.severity == :critical

      # Cache should have updated alarm
      cached = Enum.find(AlarmManager.get_active_alarms(mission.id), &(&1.id == alarm.id))
      assert cached.severity == :critical

      GenServer.stop(pid)
    end
  end

  describe "shelve expiration" do
    test "unshelves expired alarms" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Create an alarm with expired shelve
      expired = expired_shelved_alarm_fixture(organization: org, mission: mission)

      {:ok, pid} =
        AlarmManager.start_link(
          mission_id: mission.id,
          organization_id: org.id
        )

      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:alarms")

      # Trigger shelve check manually
      send(pid, :check_shelve_expiration)

      # Should receive unshelve broadcast
      assert_receive {:alarm_unshelved, %Alarm{} = unshelved}, 1000

      assert unshelved.id == expired.id
      assert unshelved.status == :active

      GenServer.stop(pid)
    end
  end

  describe "whereis/1" do
    test "returns nil for non-existent mission" do
      assert AlarmManager.whereis("non-existent-mission-id") == nil
    end
  end
end
