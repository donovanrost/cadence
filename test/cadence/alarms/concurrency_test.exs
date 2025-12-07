defmodule Cadence.Alarms.ConcurrencyTest do
  @moduledoc """
  Concurrency tests for the Alarms feature.

  These tests are designed to expose race conditions and cache consistency issues.
  Some tests are expected to FAIL until the implementation bugs are fixed.

  Key scenarios tested:
  - Concurrent alarm creation (should create only one alarm per source)
  - Concurrent state transitions (acknowledge/shelve/clear)
  - ETS cache consistency under concurrent operations

  Tests tagged with :race_condition are expected to fail until fixed.
  Tests tagged with :cache_consistency are expected to fail until fixed.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Alarms
  alias Cadence.Alarms.Engine.AlarmManager

  import Cadence.OrganizationsFixtures
  import Cadence.MissionsFixtures
  import Cadence.TargetsFixtures
  import Cadence.AlarmsFixtures
  import Cadence.AccountsFixtures
  import Cadence.AlarmsHelpers
  import Cadence.AlarmsBuilders

  setup do
    # Use shared sandbox mode for GenServer database access
    Ecto.Adapters.SQL.Sandbox.mode(Cadence.Repo, {:shared, self()})

    org = organization_fixture()
    mission = mission_fixture(organization: org)
    target = target_fixture(organization: org, mission: mission)

    # Ensure AlarmManager is running for this mission
    start_supervised!({AlarmManager, mission_id: mission.id, organization_id: org.id})

    %{org: org, mission: mission, target: target}
  end

  # ============================================================================
  # Concurrent Alarm Creation
  # ============================================================================

  describe "concurrent alarm creation" do
    @tag :race_condition
    @tag :expected_failure
    test "only one alarm created for simultaneous violations", %{
      org: org,
      mission: mission,
      target: target
    } do
      # Create a rule that will match our events
      _rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          event_type: "telemetry_limit",
          conditions: %{"limit_state" => ["red"]},
          enabled: true
        )

      source_id = "HEALTH.cpu_temp"
      concurrent_count = 10

      # Create events with same source_id - should result in only 1 alarm
      events =
        for i <- 1..concurrent_count do
          build_limit_event(
            mission_id: mission.id,
            target_id: target.id,
            item_name: source_id,
            new_state: :red,
            previous_state: :green,
            value: 100.0 + i
          )
        end

      # Subscribe to alarm events
      subscribe_to_mission_alarms(mission.id)

      # Fire all events concurrently
      tasks =
        Enum.map(events, fn event ->
          Task.async(fn ->
            # Send directly to AlarmManager
            send(AlarmManager.whereis(mission.id), {:limit_event, event})
          end)
        end)

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      # Wait for AlarmManager to process all messages
      wait_for_alarm_manager(mission.id)

      # Collect all triggered alarm messages
      Process.sleep(100)
      messages = collect_alarm_messages(500)

      triggered_count =
        Enum.count(messages, fn
          {:alarm_triggered, _} -> true
          _ -> false
        end)

      # There should be exactly 1 triggered and N-1 updates
      # Due to race condition, this may fail with multiple triggered messages
      assert triggered_count == 1,
             "Expected 1 alarm_triggered, got #{triggered_count}. Race condition detected!"

      # Verify database has only one active alarm for this source
      active_alarms =
        Alarms.list_alarms(mission.id,
          status: [:active, :acknowledged, :shelved],
          source_id: source_id
        )
        |> Enum.filter(&(&1.target_id == target.id))

      assert length(active_alarms) == 1,
             "Expected 1 active alarm in DB, got #{length(active_alarms)}. " <>
               "Race condition created duplicate alarms!"
    end

    test "find_or_create_alarm handles concurrent inserts correctly", %{
      org: org,
      mission: mission,
      target: target
    } do
      # This test exercises the new find_or_create_alarm function
      source_type = "telemetry_item"
      source_id = "POWER.voltage_#{System.unique_integer([:positive])}"

      # Create identical alarm attrs
      attrs = %{
        organization_id: org.id,
        mission_id: mission.id,
        target_id: target.id,
        alarm_type: "telemetry_limit",
        severity: :warning,
        status: :active,
        source_type: source_type,
        source_id: source_id,
        source_origin: :rule,
        limit_state: :red,
        current_value: 105.0,
        message: "Voltage exceeded threshold",
        triggered_at: DateTime.utc_now()
      }

      concurrent_count = 5

      # Try to create the same alarm concurrently using find_or_create_alarm
      tasks =
        for _i <- 1..concurrent_count do
          Task.async(fn ->
            Alarms.find_or_create_alarm(attrs)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # Count how many created vs found existing
      created_count = Enum.count(results, fn r -> match?({:ok, _, :created}, r) end)
      existing_count = Enum.count(results, fn r -> match?({:ok, _, :existing}, r) end)
      error_count = Enum.count(results, fn r -> match?({:error, _}, r) end)

      # Should be exactly 1 created and N-1 existing
      assert created_count == 1,
             "Expected 1 create, got #{created_count}. " <>
               "Existing: #{existing_count}, Errors: #{error_count}."

      assert existing_count == concurrent_count - 1,
             "Expected #{concurrent_count - 1} existing, got #{existing_count}"

      assert error_count == 0,
             "Expected 0 errors, got #{error_count}: #{inspect(Enum.filter(results, fn r -> match?({:error, _}, r) end))}"

      # Verify database state - only 1 alarm should exist
      all_alarms =
        Alarms.list_alarms(mission.id,
          status: [:active, :acknowledged, :shelved],
          source_id: source_id
        )
        |> Enum.filter(&(&1.target_id == target.id))

      assert length(all_alarms) == 1,
             "Expected 1 alarm in DB, got #{length(all_alarms)}"

      # All results should reference the same alarm ID
      alarm_ids =
        results
        |> Enum.filter(fn r -> match?({:ok, _, _}, r) end)
        |> Enum.map(fn {:ok, alarm, _} -> alarm.id end)
        |> Enum.uniq()

      assert length(alarm_ids) == 1,
             "Expected all results to reference same alarm, got #{length(alarm_ids)} different alarms"
    end
  end

  # ============================================================================
  # Concurrent State Transitions
  # ============================================================================

  describe "concurrent state transitions" do
    test "acknowledge and shelve don't corrupt state", %{
      org: org,
      mission: mission,
      target: target
    } do
      # Create an alarm
      alarm =
        alarm_fixture(
          organization: org,
          mission: mission,
          target: target,
          severity: :warning,
          limit_state: :yellow,
          current_value: 85.0
        )

      user = user_fixture(organization: org)

      # Run acknowledge and shelve concurrently
      ack_task =
        Task.async(fn ->
          Alarms.acknowledge_alarm(alarm, user.id, "Acknowledging")
        end)

      shelve_task =
        Task.async(fn ->
          Alarms.shelve_alarm(alarm, user.id, 30, "Shelving for maintenance")
        end)

      ack_result = Task.await(ack_task)
      shelve_result = Task.await(shelve_task)

      # At least one should succeed
      assert match?({:ok, _}, ack_result) or match?({:ok, _}, shelve_result),
             "Both operations failed: ack=#{inspect(ack_result)}, shelve=#{inspect(shelve_result)}"

      # Reload alarm and verify it's in a consistent state
      final_alarm = Alarms.get_alarm!(alarm.id)

      # Status should be valid
      assert final_alarm.status in [:acknowledged, :shelved],
             "Unexpected status: #{final_alarm.status}"

      # If acknowledged, should have ack fields set
      if final_alarm.status == :acknowledged do
        assert final_alarm.acknowledged_by_id == user.id
        assert final_alarm.acknowledged_at != nil
      end

      # If shelved, should have shelve fields set
      if final_alarm.status == :shelved do
        assert final_alarm.shelved_by_id == user.id
        assert final_alarm.shelved_at != nil
      end
    end

    test "shelve and clear don't corrupt state", %{
      org: org,
      mission: mission,
      target: target
    } do
      alarm =
        alarm_fixture(
          organization: org,
          mission: mission,
          target: target
        )

      user = user_fixture(organization: org)

      shelve_task =
        Task.async(fn ->
          Alarms.shelve_alarm(alarm, user.id, 30, "Shelving for maintenance")
        end)

      clear_task =
        Task.async(fn ->
          Process.sleep(5)
          Alarms.clear_alarm(alarm, user.id)
        end)

      shelve_result = Task.await(shelve_task)
      clear_result = Task.await(clear_task)

      # At least one should succeed
      assert match?({:ok, _}, shelve_result) or match?({:ok, _}, clear_result),
             "Both operations failed"

      # Reload and verify consistent state
      final_alarm = Alarms.get_alarm!(alarm.id)
      assert final_alarm.status in [:shelved, :cleared]

      if final_alarm.status == :shelved do
        assert final_alarm.shelved_by_id == user.id
        assert final_alarm.shelved_at != nil
        assert final_alarm.shelved_until != nil
      end

      if final_alarm.status == :cleared do
        assert final_alarm.cleared_at != nil
      end
    end
  end

  # ============================================================================
  # Cache Consistency
  # ============================================================================

  describe "ETS cache consistency" do
    @tag :cache_consistency
    @tag :expected_failure
    test "cache matches database after concurrent operations", %{
      org: org,
      mission: mission,
      target: target
    } do
      user = user_fixture(organization: org)

      # Create several alarms - these go directly to DB, not through AlarmManager
      alarms =
        for i <- 1..5 do
          alarm_fixture(
            organization: org,
            mission: mission,
            target: target,
            source_id: "ITEM_#{i}"
          )
        end

      # Perform mixed concurrent operations using the Alarms context
      tasks =
        alarms
        |> Enum.with_index()
        |> Enum.map(fn {alarm, idx} ->
          Task.async(fn ->
            case rem(idx, 3) do
              0 -> Alarms.acknowledge_alarm(alarm, user.id)
              1 -> Alarms.shelve_alarm(alarm, user.id, 30)
              2 -> Alarms.clear_alarm(alarm, user.id)
            end
          end)
        end)

      # Wait for all operations to complete
      Enum.each(tasks, &Task.await/1)

      # Give cache time to update
      wait_for_alarm_manager(mission.id)
      Process.sleep(100)

      # Compare cache to database
      cached_alarms = AlarmManager.get_active_alarms(mission.id)
      cached_ids = Enum.map(cached_alarms, & &1.id) |> Enum.sort()

      db_alarms = Alarms.list_active_alarms(mission.id)
      db_ids = Enum.map(db_alarms, & &1.id) |> Enum.sort()

      assert cached_ids == db_ids,
             """
             Cache/DB mismatch after concurrent operations!
             Cache: #{inspect(cached_ids)}
             DB:    #{inspect(db_ids)}
             This indicates the cache is not being updated correctly when
             alarm mutations happen outside the AlarmManager GenServer.
             """
    end

    @tag :cache_consistency
    @tag :expected_failure
    test "cache reflects alarms created via AlarmManager", %{
      org: org,
      mission: mission,
      target: target
    } do
      # Create a rule that will match our event
      _rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          event_type: "telemetry_limit",
          conditions: %{"limit_state" => ["red"]},
          enabled: true
        )

      # Subscribe to alarm events
      subscribe_to_mission_alarms(mission.id)

      # Send a limit event through AlarmManager
      event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: "HEALTH.cpu_temp",
          new_state: :red,
          previous_state: :green,
          value: 100.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event})

      # Wait for alarm to be triggered
      case await_alarm_triggered(5000) do
        {:ok, alarm} ->
          # Cache should contain this alarm
          cached_alarms = AlarmManager.get_active_alarms(mission.id)
          assert Enum.any?(cached_alarms, &(&1.id == alarm.id)),
                 "Alarm created via AlarmManager not found in cache!"

        {:error, :timeout} ->
          flunk("Timeout waiting for alarm to be triggered")
      end
    end

    @tag :cache_consistency
    @tag :expected_failure
    test "cache updated when alarm acknowledged via context directly", %{
      org: org,
      mission: mission,
      target: target
    } do
      user = user_fixture(organization: org)

      # Create alarm via AlarmManager path
      _rule =
        alarm_rule_fixture(
          organization: org,
          mission: mission,
          event_type: "telemetry_limit",
          conditions: %{"limit_state" => ["red"]},
          enabled: true
        )

      subscribe_to_mission_alarms(mission.id)

      event =
        build_limit_event(
          mission_id: mission.id,
          target_id: target.id,
          item_name: "HEALTH.test_item",
          new_state: :red,
          previous_state: :green,
          value: 100.0
        )

      send(AlarmManager.whereis(mission.id), {:limit_event, event})

      # Wait for alarm
      {:ok, alarm} = await_alarm_triggered(5000)

      # Verify alarm is in cache initially
      initial_cached = AlarmManager.get_active_alarms(mission.id)
      assert Enum.any?(initial_cached, &(&1.id == alarm.id)),
             "Alarm should be in cache after creation via AlarmManager"

      # Acknowledge via context (bypasses AlarmManager)
      {:ok, acked_alarm} = Alarms.acknowledge_alarm(alarm, user.id)
      assert acked_alarm.status == :acknowledged

      # Give time for any async updates
      Process.sleep(50)

      # Check cache - it should reflect the acknowledged status
      # This test WILL FAIL because cache is not updated when using context directly
      cached_alarm = Enum.find(AlarmManager.get_active_alarms(mission.id), &(&1.id == alarm.id))

      assert cached_alarm != nil,
             "Acknowledged alarm should still be in active alarms cache"

      assert cached_alarm.status == :acknowledged,
             """
             Cache not updated! Expected status: :acknowledged, got: #{inspect(cached_alarm && cached_alarm.status)}
             This fails because Alarms.acknowledge_alarm/3 doesn't route through AlarmManager.
             """
    end
  end
end
