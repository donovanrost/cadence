defmodule Cadence.AlarmsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Alarms
  alias Cadence.Alarms.{Alarm, AlarmRule, AlarmEvent}

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.TargetsFixtures
  import Cadence.AlarmsFixtures

  # ============================================================================
  # Alarm Rules
  # ============================================================================

  describe "list_rules/2" do
    test "returns all rules for an organization" do
      org = organization_fixture()
      rule1 = alarm_rule_fixture(organization: org)
      rule2 = alarm_rule_fixture(organization: org)

      # Rule for different org should not appear
      _other_rule = alarm_rule_fixture()

      rules = Alarms.list_rules(org.id)

      assert length(rules) == 2
      assert Enum.any?(rules, &(&1.id == rule1.id))
      assert Enum.any?(rules, &(&1.id == rule2.id))
    end

    test "filters by mission_id" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      mission_rule = alarm_rule_fixture(organization: org, mission: mission)
      _org_rule = alarm_rule_fixture(organization: org)

      rules = Alarms.list_rules(org.id, mission_id: mission.id)

      # Should include both mission-specific and org-wide rules
      assert length(rules) == 2
      assert Enum.any?(rules, &(&1.id == mission_rule.id))
    end

    test "filters by enabled status" do
      org = organization_fixture()
      enabled_rule = alarm_rule_fixture(organization: org, enabled: true)
      _disabled_rule = disabled_alarm_rule_fixture(organization: org)

      rules = Alarms.list_rules(org.id, enabled: true)

      assert length(rules) == 1
      assert hd(rules).id == enabled_rule.id
    end

    test "filters by event_type" do
      org = organization_fixture()
      rule = alarm_rule_fixture(organization: org, event_type: "telemetry_limit")

      rules = Alarms.list_rules(org.id, event_type: "telemetry_limit")

      assert length(rules) == 1
      assert hd(rules).id == rule.id
    end
  end

  describe "get_rule/1" do
    test "returns the rule with given id" do
      rule = alarm_rule_fixture()
      assert Alarms.get_rule(rule.id).id == rule.id
    end

    test "returns nil for non-existent rule" do
      assert is_nil(Alarms.get_rule(Ecto.UUID.generate()))
    end
  end

  describe "create_rule/1" do
    test "creates a rule with valid data" do
      org = organization_fixture()

      attrs = %{
        organization_id: org.id,
        name: "Battery Alert",
        event_type: "telemetry_limit",
        severity: :critical,
        conditions: %{"limit_state" => ["red"]}
      }

      assert {:ok, %AlarmRule{} = rule} = Alarms.create_rule(attrs)
      assert rule.name == "Battery Alert"
      assert rule.severity == :critical
      assert rule.enabled == true
    end

    test "returns error changeset with invalid data" do
      assert {:error, %Ecto.Changeset{}} = Alarms.create_rule(%{})
    end

    test "validates event_type is supported" do
      org = organization_fixture()

      attrs = %{
        organization_id: org.id,
        name: "Test Rule",
        event_type: "invalid_type"
      }

      assert {:error, changeset} = Alarms.create_rule(attrs)
      assert "is invalid" in errors_on(changeset).event_type
    end
  end

  describe "update_rule/2" do
    test "updates the rule with valid data" do
      rule = alarm_rule_fixture()

      assert {:ok, %AlarmRule{} = updated} =
               Alarms.update_rule(rule, %{name: "Updated Name", severity: :critical})

      assert updated.name == "Updated Name"
      assert updated.severity == :critical
    end

    test "returns error changeset with invalid data" do
      rule = alarm_rule_fixture()

      assert {:error, %Ecto.Changeset{}} = Alarms.update_rule(rule, %{name: nil})
    end
  end

  describe "enable_rule/1 and disable_rule/3" do
    test "enables a disabled rule" do
      rule = disabled_alarm_rule_fixture()

      assert {:ok, %AlarmRule{} = enabled} = Alarms.enable_rule(rule)
      assert enabled.enabled == true
      assert is_nil(enabled.disabled_at)
      assert is_nil(enabled.disabled_reason)
    end

    test "disables an enabled rule" do
      rule = alarm_rule_fixture()
      user = Cadence.AccountsFixtures.user_fixture()

      assert {:ok, %AlarmRule{} = disabled} =
               Alarms.disable_rule(rule, user.id, "Maintenance window")

      assert disabled.enabled == false
      assert not is_nil(disabled.disabled_at)
      assert disabled.disabled_reason == "Maintenance window"
    end
  end

  describe "delete_rule/1" do
    test "deletes the rule" do
      rule = alarm_rule_fixture()

      assert {:ok, %AlarmRule{}} = Alarms.delete_rule(rule)
      assert is_nil(Alarms.get_rule(rule.id))
    end
  end

  describe "find_matching_rules/4" do
    test "returns rules matching event criteria" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          event_type: "telemetry_limit",
          enabled: true
        )

      rules = Alarms.find_matching_rules(org.id, mission.id, nil, "telemetry_limit")

      assert length(rules) == 1
      assert hd(rules).id == rule.id
    end

    test "returns rules in specificity order (most specific first)" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      target = target_fixture(mission: mission, organization: org)

      org_rule = alarm_rule_fixture(organization: org, event_type: "telemetry_limit")

      mission_rule =
        alarm_rule_fixture(organization: org, mission: mission, event_type: "telemetry_limit")

      target_rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          target: target,
          event_type: "telemetry_limit"
        )

      rules = Alarms.find_matching_rules(org.id, mission.id, target.id, "telemetry_limit")

      assert length(rules) == 3
      # Most specific first
      assert Enum.at(rules, 0).id == target_rule.id
      assert Enum.at(rules, 1).id == mission_rule.id
      assert Enum.at(rules, 2).id == org_rule.id
    end

    test "excludes disabled rules" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      _disabled = disabled_alarm_rule_fixture(organization: org, event_type: "telemetry_limit")

      rules = Alarms.find_matching_rules(org.id, mission.id, nil, "telemetry_limit")

      assert rules == []
    end
  end

  # ============================================================================
  # Alarms
  # ============================================================================

  describe "list_alarms/2" do
    test "returns all alarms for a mission" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      alarm1 = alarm_fixture(organization: org, mission: mission)
      alarm2 = alarm_fixture(organization: org, mission: mission)

      # Alarm for different mission should not appear
      _other_alarm = alarm_fixture()

      alarms = Alarms.list_alarms(mission.id)

      assert length(alarms) == 2
      assert Enum.any?(alarms, &(&1.id == alarm1.id))
      assert Enum.any?(alarms, &(&1.id == alarm2.id))
    end

    test "filters by status" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      active = alarm_fixture(organization: org, mission: mission, status: :active)
      _cleared = cleared_alarm_fixture(organization: org, mission: mission)

      alarms = Alarms.list_alarms(mission.id, status: :active)

      assert length(alarms) == 1
      assert hd(alarms).id == active.id
    end

    test "filters by multiple statuses" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      active = alarm_fixture(organization: org, mission: mission, status: :active)
      acked = acknowledged_alarm_fixture(organization: org, mission: mission)
      _cleared = cleared_alarm_fixture(organization: org, mission: mission)

      alarms = Alarms.list_alarms(mission.id, status: [:active, :acknowledged])

      assert length(alarms) == 2
      ids = Enum.map(alarms, & &1.id)
      assert active.id in ids
      assert acked.id in ids
    end

    test "filters by severity" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      warning = alarm_fixture(organization: org, mission: mission, severity: :warning)
      _critical = critical_alarm_fixture(organization: org, mission: mission)

      alarms = Alarms.list_alarms(mission.id, severity: :warning)

      assert length(alarms) == 1
      assert hd(alarms).id == warning.id
    end

    test "supports pagination with limit and offset" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Create 5 alarms
      for _ <- 1..5, do: alarm_fixture(organization: org, mission: mission)

      page1 = Alarms.list_alarms(mission.id, limit: 2, offset: 0)
      page2 = Alarms.list_alarms(mission.id, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 2
      refute Enum.any?(page1, fn a -> a.id in Enum.map(page2, & &1.id) end)
    end
  end

  describe "list_active_alarms/2" do
    test "returns only active, acknowledged, and shelved alarms" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      active = alarm_fixture(organization: org, mission: mission, status: :active)
      acked = acknowledged_alarm_fixture(organization: org, mission: mission)
      shelved = shelved_alarm_fixture(organization: org, mission: mission)
      _cleared = cleared_alarm_fixture(organization: org, mission: mission)

      alarms = Alarms.list_active_alarms(mission.id)

      assert length(alarms) == 3
      ids = Enum.map(alarms, & &1.id)
      assert active.id in ids
      assert acked.id in ids
      assert shelved.id in ids
    end
  end

  describe "count_alarms_by_status/1" do
    test "returns counts grouped by status" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      alarm_fixture(organization: org, mission: mission, status: :active)
      alarm_fixture(organization: org, mission: mission, status: :active)
      acknowledged_alarm_fixture(organization: org, mission: mission)
      cleared_alarm_fixture(organization: org, mission: mission)

      counts = Alarms.count_alarms_by_status(mission.id)

      assert counts[:active] == 2
      assert counts[:acknowledged] == 1
      assert counts[:cleared] == 1
    end
  end

  describe "get_alarm/1" do
    test "returns the alarm with given id" do
      alarm = alarm_fixture()
      assert Alarms.get_alarm(alarm.id).id == alarm.id
    end

    test "returns nil for non-existent alarm" do
      assert is_nil(Alarms.get_alarm(Ecto.UUID.generate()))
    end
  end

  describe "find_active_alarm/4" do
    test "finds existing active alarm for source" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      alarm =
        alarm_fixture(
          organization: org,
          mission: mission,
          source_type: "telemetry_item",
          source_id: "HEALTH.cpu_temp"
        )

      found = Alarms.find_active_alarm(mission.id, nil, "telemetry_item", "HEALTH.cpu_temp")

      assert found.id == alarm.id
    end

    test "returns nil when no active alarm exists" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      # Create a cleared alarm (not active)
      cleared_alarm_fixture(
        organization: org,
        mission: mission,
        source_type: "telemetry_item",
        source_id: "HEALTH.cpu_temp"
      )

      found = Alarms.find_active_alarm(mission.id, nil, "telemetry_item", "HEALTH.cpu_temp")

      assert is_nil(found)
    end

    test "distinguishes by target_id" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)
      target = target_fixture(organization: org, mission: mission)

      _no_target =
        alarm_fixture(
          organization: org,
          mission: mission,
          source_type: "telemetry_item",
          source_id: "HEALTH.cpu_temp"
        )

      with_target =
        alarm_fixture(
          organization: org,
          mission: mission,
          target: target,
          source_type: "telemetry_item",
          source_id: "HEALTH.cpu_temp"
        )

      found = Alarms.find_active_alarm(mission.id, target.id, "telemetry_item", "HEALTH.cpu_temp")

      assert found.id == with_target.id
    end
  end

  describe "create_alarm/1" do
    test "creates an alarm with valid data" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      attrs = %{
        organization_id: org.id,
        mission_id: mission.id,
        alarm_type: "telemetry_limit",
        severity: :warning,
        source_type: "telemetry_item",
        source_id: "HEALTH.cpu_temp",
        current_value: 85.0,
        message: "Temperature warning",
        triggered_at: DateTime.utc_now()
      }

      assert {:ok, %Alarm{} = alarm} = Alarms.create_alarm(attrs)
      assert alarm.alarm_type == "telemetry_limit"
      assert alarm.severity == :warning
      assert alarm.status == :active
    end

    test "creates a triggered event along with the alarm" do
      org = organization_fixture()
      mission = mission_fixture(organization: org)

      attrs = %{
        organization_id: org.id,
        mission_id: mission.id,
        alarm_type: "telemetry_limit",
        severity: :warning,
        source_type: "telemetry_item",
        source_id: "HEALTH.cpu_temp",
        triggered_at: DateTime.utc_now()
      }

      assert {:ok, %Alarm{} = alarm} = Alarms.create_alarm(attrs)

      events = Alarms.list_alarm_events(alarm.id)
      assert length(events) == 1
      assert hd(events).event_type == :triggered
    end

    test "returns error changeset with invalid data" do
      assert {:error, %Ecto.Changeset{}} = Alarms.create_alarm(%{})
    end
  end

  describe "acknowledge_alarm/3" do
    test "acknowledges an active alarm" do
      alarm = alarm_fixture()
      user = Cadence.AccountsFixtures.user_fixture()

      assert {:ok, %Alarm{} = acked} = Alarms.acknowledge_alarm(alarm, user.id, "Got it")
      assert acked.status == :acknowledged
      assert acked.acknowledged_by_id == user.id
      assert not is_nil(acked.acknowledged_at)
      assert acked.acknowledgment_note == "Got it"
    end

    test "creates an acknowledged event" do
      alarm = alarm_fixture()
      user = Cadence.AccountsFixtures.user_fixture()

      {:ok, acked} = Alarms.acknowledge_alarm(alarm, user.id)

      events = Alarms.list_alarm_events(acked.id)
      assert Enum.any?(events, &(&1.event_type == :acknowledged))
    end
  end

  describe "shelve_alarm/4" do
    test "shelves an alarm for specified duration" do
      alarm = alarm_fixture()
      user = Cadence.AccountsFixtures.user_fixture()

      assert {:ok, %Alarm{} = shelved} =
               Alarms.shelve_alarm(alarm, user.id, 30, "Investigating")

      assert shelved.status == :shelved
      assert shelved.shelved_by_id == user.id
      assert not is_nil(shelved.shelved_at)
      assert not is_nil(shelved.shelved_until)
      assert shelved.shelve_reason == "Investigating"
    end

    test "creates a shelved event" do
      alarm = alarm_fixture()
      user = Cadence.AccountsFixtures.user_fixture()

      {:ok, shelved} = Alarms.shelve_alarm(alarm, user.id, 30)

      events = Alarms.list_alarm_events(shelved.id)
      assert Enum.any?(events, &(&1.event_type == :shelved))
    end
  end

  describe "unshelve_alarm/2" do
    test "unshelves an alarm returning it to active" do
      alarm = shelved_alarm_fixture()

      assert {:ok, %Alarm{} = unshelved} = Alarms.unshelve_alarm(alarm)
      assert unshelved.status == :active
      assert is_nil(unshelved.shelved_at)
      assert is_nil(unshelved.shelved_until)
    end

    test "returns to acknowledged if previously acknowledged" do
      acked = acknowledged_alarm_fixture()

      shelved =
        acked
        |> Alarm.shelve_changeset(%{
          shelved_by_id: acked.acknowledged_by_id,
          shelved_at: DateTime.utc_now(),
          shelved_until: DateTime.add(DateTime.utc_now(), 1800, :second)
        })
        |> Repo.update!()

      assert {:ok, %Alarm{} = unshelved} = Alarms.unshelve_alarm(shelved)
      assert unshelved.status == :acknowledged
    end

    test "creates an unshelved event" do
      alarm = shelved_alarm_fixture()

      {:ok, unshelved} = Alarms.unshelve_alarm(alarm)

      events = Alarms.list_alarm_events(unshelved.id)
      assert Enum.any?(events, &(&1.event_type == :unshelved))
    end
  end

  describe "clear_alarm/2" do
    test "clears an alarm" do
      alarm = alarm_fixture()

      assert {:ok, %Alarm{} = cleared} = Alarms.clear_alarm(alarm)
      assert cleared.status == :cleared
      assert not is_nil(cleared.cleared_at)
    end

    test "creates a cleared event" do
      alarm = alarm_fixture()

      {:ok, cleared} = Alarms.clear_alarm(alarm)

      events = Alarms.list_alarm_events(cleared.id)
      assert Enum.any?(events, &(&1.event_type == :cleared))
    end
  end

  describe "update_alarm_value/5" do
    test "updates the current value" do
      alarm = alarm_fixture(current_value: 80.0)

      assert {:ok, %Alarm{} = updated} =
               Alarms.update_alarm_value(alarm, 90.0, :yellow, :warning)

      assert updated.current_value == 90.0
      assert not is_nil(updated.last_value_at)
    end

    test "escalates severity and creates escalated event" do
      alarm = alarm_fixture(severity: :warning, limit_state: :yellow)

      {:ok, escalated} = Alarms.update_alarm_value(alarm, 105.0, :red, :critical, "Now critical!")

      assert escalated.severity == :critical
      assert escalated.limit_state == :red

      events = Alarms.list_alarm_events(escalated.id)
      assert Enum.any?(events, &(&1.event_type == :escalated))
    end

    test "deescalates severity and creates deescalated event" do
      alarm = alarm_fixture(severity: :critical, limit_state: :red)

      {:ok, deescalated} = Alarms.update_alarm_value(alarm, 85.0, :yellow, :warning)

      assert deescalated.severity == :warning
      assert deescalated.limit_state == :yellow

      events = Alarms.list_alarm_events(deescalated.id)
      assert Enum.any?(events, &(&1.event_type == :deescalated))
    end

    test "creates value_updated event when severity unchanged" do
      alarm = alarm_fixture(severity: :warning, current_value: 80.0)

      {:ok, updated} = Alarms.update_alarm_value(alarm, 82.0, :yellow, :warning)

      events = Alarms.list_alarm_events(updated.id)
      assert Enum.any?(events, &(&1.event_type == :value_updated))
    end
  end

  # ============================================================================
  # Alarm Events
  # ============================================================================

  describe "list_alarm_events/1" do
    test "returns events for an alarm in chronological order" do
      alarm = alarm_fixture()

      # Create several events
      event1 = alarm_event_fixture(alarm: alarm, event_type: :triggered)
      Process.sleep(10)
      event2 = alarm_event_fixture(alarm: alarm, event_type: :acknowledged)
      Process.sleep(10)
      event3 = alarm_event_fixture(alarm: alarm, event_type: :cleared)

      events = Alarms.list_alarm_events(alarm.id)

      assert length(events) == 3
      # Should be in chronological order (oldest first)
      assert Enum.at(events, 0).id == event1.id
      assert Enum.at(events, 1).id == event2.id
      assert Enum.at(events, 2).id == event3.id
    end
  end

  # ============================================================================
  # Shelve Expiration
  # ============================================================================

  describe "find_expired_shelved_alarms/0" do
    test "returns alarms with expired shelve periods" do
      expired = expired_shelved_alarm_fixture()
      _active = shelved_alarm_fixture()

      alarms = Alarms.find_expired_shelved_alarms()

      assert length(alarms) == 1
      assert hd(alarms).id == expired.id
    end
  end

  describe "unshelve_expired_alarms/0" do
    test "unshelves all expired alarms" do
      expired1 = expired_shelved_alarm_fixture()
      expired2 = expired_shelved_alarm_fixture()
      still_shelved = shelved_alarm_fixture()

      assert {:ok, 2} = Alarms.unshelve_expired_alarms()

      # Expired alarms should now be active
      assert Alarms.get_alarm(expired1.id).status == :active
      assert Alarms.get_alarm(expired2.id).status == :active
      # Still-shelved should remain shelved
      assert Alarms.get_alarm(still_shelved.id).status == :shelved
    end
  end
end
