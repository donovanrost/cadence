defmodule Cadence.Alarms.Engine.RuleCacheTest do
  @moduledoc """
  Tests for RuleCache ETS-based caching of alarm rules.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Alarms.Engine.RuleCache

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.TargetsFixtures
  import Cadence.AlarmsFixtures

  setup do
    # Use shared sandbox mode since RuleCache GenServer accesses DB
    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, {:shared, self()})

    org = organization_fixture()
    mission = mission_fixture(organization: org)
    target = target_fixture(organization: org, mission: mission)

    # Clear any cached rules for this mission
    RuleCache.invalidate_mission(mission.id)

    %{org: org, mission: mission, target: target}
  end

  # ============================================================================
  # get_rules_for_mission/3
  # ============================================================================

  describe "get_rules_for_mission/3" do
    test "returns empty list when no rules exist", %{org: org, mission: mission} do
      rules = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert rules == []
    end

    test "fetches rules from database on cache miss", %{org: org, mission: mission} do
      # Create a rule
      rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)

      # Invalidate to ensure cache miss
      RuleCache.invalidate_mission(mission.id)

      # Should fetch from DB
      rules = RuleCache.get_rules_for_mission(org.id, mission.id)

      assert length(rules) == 1
      assert hd(rules).id == rule.id
    end

    test "returns cached rules on subsequent calls", %{org: org, mission: mission} do
      rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      RuleCache.invalidate_mission(mission.id)

      # First call - cache miss, fetches from DB
      rules1 = RuleCache.get_rules_for_mission(org.id, mission.id)

      # Create another rule AFTER the cache is populated
      _new_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)

      # Second call - should return cached result (still 1 rule)
      rules2 = RuleCache.get_rules_for_mission(org.id, mission.id)

      assert rules1 == rules2
      assert length(rules2) == 1
      assert hd(rules2).id == rule.id
    end

    test "filters by target_id when provided", %{org: org, mission: mission, target: target} do
      # Create org-wide rule
      org_rule = alarm_rule_fixture(organization: org, enabled: true)

      # Create mission-wide rule
      mission_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)

      # Create target-specific rule
      target_rule =
        alarm_rule_fixture(organization: org, mission: mission, target: target, enabled: true)

      RuleCache.invalidate_mission(mission.id)

      # Without target_id - should get all applicable rules
      rules_no_target = RuleCache.get_rules_for_mission(org.id, mission.id, nil)
      # Should include org-wide and mission-wide, but not target-specific
      rule_ids = Enum.map(rules_no_target, & &1.id)
      assert org_rule.id in rule_ids
      assert mission_rule.id in rule_ids
      refute target_rule.id in rule_ids

      # With target_id - should include target-specific rule
      rules_with_target = RuleCache.get_rules_for_mission(org.id, mission.id, target.id)
      rule_ids = Enum.map(rules_with_target, & &1.id)
      assert org_rule.id in rule_ids
      assert mission_rule.id in rule_ids
      assert target_rule.id in rule_ids
    end

    test "sorts by specificity (target > mission > org)", %{
      org: org,
      mission: mission,
      target: target
    } do
      # Create rules in random order
      mission_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      org_rule = alarm_rule_fixture(organization: org, enabled: true)

      target_rule =
        alarm_rule_fixture(organization: org, mission: mission, target: target, enabled: true)

      RuleCache.invalidate_mission(mission.id)

      rules = RuleCache.get_rules_for_mission(org.id, mission.id, target.id)

      # Should be sorted: target (specificity 3) > mission (2) > org (1)
      assert length(rules) == 3
      assert Enum.at(rules, 0).id == target_rule.id
      assert Enum.at(rules, 1).id == mission_rule.id
      assert Enum.at(rules, 2).id == org_rule.id
    end

    test "excludes disabled rules", %{org: org, mission: mission} do
      _enabled = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      _disabled = disabled_alarm_rule_fixture(organization: org, mission: mission)

      RuleCache.invalidate_mission(mission.id)

      rules = RuleCache.get_rules_for_mission(org.id, mission.id)

      assert length(rules) == 1
      assert hd(rules).enabled == true
    end
  end

  # ============================================================================
  # get_rules_for_event/4
  # ============================================================================

  describe "get_rules_for_event/4" do
    test "filters by event_type", %{org: org, mission: mission} do
      telemetry_rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          event_type: "telemetry_limit",
          enabled: true
        )

      RuleCache.invalidate_mission(mission.id)

      rules = RuleCache.get_rules_for_event(org.id, mission.id, nil, "telemetry_limit")

      assert length(rules) == 1
      assert hd(rules).id == telemetry_rule.id
    end

    test "returns empty list for non-matching event_type", %{org: org, mission: mission} do
      # Create a telemetry_limit rule
      _rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          event_type: "telemetry_limit",
          enabled: true
        )

      RuleCache.invalidate_mission(mission.id)

      # Query for a different event type
      rules = RuleCache.get_rules_for_event(org.id, mission.id, nil, "command_failure")

      assert rules == []
    end
  end

  # ============================================================================
  # Cache Invalidation
  # ============================================================================

  describe "invalidate_mission/1" do
    test "clears cache for specific mission", %{org: org, mission: mission} do
      rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      RuleCache.invalidate_mission(mission.id)

      # Populate cache
      rules1 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules1) == 1
      assert hd(rules1).id == rule.id

      # Create new rule and invalidate
      new_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      RuleCache.invalidate_mission(mission.id)

      # Should now include the new rule
      rules2 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules2) == 2
      rule_ids = Enum.map(rules2, & &1.id)
      assert rule.id in rule_ids
      assert new_rule.id in rule_ids
    end
  end

  describe "invalidate_all/0" do
    test "clears entire cache", %{org: org, mission: mission} do
      rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      RuleCache.invalidate_mission(mission.id)

      # Populate cache
      _rules1 = RuleCache.get_rules_for_mission(org.id, mission.id)

      # Create new rule and invalidate all
      new_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      RuleCache.invalidate_all()

      # Should now include the new rule
      rules2 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules2) == 2
      rule_ids = Enum.map(rules2, & &1.id)
      assert rule.id in rule_ids
      assert new_rule.id in rule_ids
    end
  end

  describe "PubSub invalidation" do
    test "invalidates mission cache on mission rule change", %{org: org, mission: mission} do
      rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      RuleCache.invalidate_mission(mission.id)

      # Populate cache
      rules1 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules1) == 1

      # Simulate a rule change broadcast (this is what the Alarms context does)
      new_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)

      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "alarm_rules:changed",
        {:alarm_rule_changed, :created, new_rule}
      )

      # Give the GenServer time to process the message
      Process.sleep(50)

      # Cache should be invalidated, so we should get fresh data
      rules2 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules2) == 2
    end

    test "invalidates all caches on org-wide rule change", %{org: org, mission: mission} do
      mission_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)
      RuleCache.invalidate_mission(mission.id)

      # Populate cache
      rules1 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules1) == 1
      assert hd(rules1).id == mission_rule.id

      # Create an org-wide rule (no mission_id)
      org_rule = alarm_rule_fixture(organization: org, enabled: true)

      # Broadcast org-wide rule change
      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "alarm_rules:changed",
        {:alarm_rule_changed, :created, org_rule}
      )

      # Give the GenServer time to process
      Process.sleep(50)

      # Cache should be fully invalidated
      rules2 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules2) == 2
    end
  end

  # ============================================================================
  # Target ID Resolution
  # ============================================================================

  describe "target_id resolution" do
    test "passes through valid UUID unchanged", %{org: org, mission: mission, target: target} do
      target_rule =
        alarm_rule_fixture(organization: org, mission: mission, target: target, enabled: true)

      RuleCache.invalidate_mission(mission.id)

      # Pass UUID directly
      rules = RuleCache.get_rules_for_mission(org.id, mission.id, target.id)

      rule_ids = Enum.map(rules, & &1.id)
      assert target_rule.id in rule_ids
    end

    test "resolves string identifier to UUID", %{org: org, mission: mission, target: target} do
      target_rule =
        alarm_rule_fixture(organization: org, mission: mission, target: target, enabled: true)

      RuleCache.invalidate_mission(mission.id)

      # Pass target identifier (string name) instead of UUID
      rules = RuleCache.get_rules_for_mission(org.id, mission.id, target.identifier)

      rule_ids = Enum.map(rules, & &1.id)
      assert target_rule.id in rule_ids
    end

    test "returns nil for unknown identifier", %{org: org, mission: mission} do
      # Create a target-specific rule
      target = target_fixture(organization: org, mission: mission)

      _target_rule =
        alarm_rule_fixture(organization: org, mission: mission, target: target, enabled: true)

      RuleCache.invalidate_mission(mission.id)

      # Pass a non-existent identifier - should get no target-specific rules
      rules = RuleCache.get_rules_for_mission(org.id, mission.id, "NONEXISTENT")

      # Should not include the target-specific rule since identifier couldn't be resolved
      assert Enum.all?(rules, fn r -> is_nil(r.target_id) end)
    end
  end

  # ============================================================================
  # refresh_mission/2
  # ============================================================================

  describe "refresh_mission/2" do
    test "forces cache refresh for a mission", %{org: org, mission: mission} do
      rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)

      # Populate cache
      RuleCache.invalidate_mission(mission.id)
      _rules1 = RuleCache.get_rules_for_mission(org.id, mission.id)

      # Create new rule without invalidating
      new_rule = alarm_rule_fixture(organization: org, mission: mission, enabled: true)

      # Force refresh
      RuleCache.refresh_mission(org.id, mission.id)

      # Should now include the new rule
      rules2 = RuleCache.get_rules_for_mission(org.id, mission.id)
      assert length(rules2) == 2
      rule_ids = Enum.map(rules2, & &1.id)
      assert rule.id in rule_ids
      assert new_rule.id in rule_ids
    end
  end
end
