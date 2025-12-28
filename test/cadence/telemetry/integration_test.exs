defmodule Cadence.Telemetry.IntegrationTest do
  @moduledoc """
  End-to-end integration test for the telemetry pipeline.

  Tests the complete flow:
  1. Packet Simulator generates telemetry
  2. Telemetry Pipeline processes packets
  3. Packet Identifier identifies packet types
  4. Decommutation extracts telemetry items
  5. CVT stores current values
  6. PubSub broadcasts updates
  """

  use Cadence.DataCase

  alias Cadence.{Missions, Organizations}
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Runtime.Telemetry.Pipeline
  alias Cadence.Simulator.PacketSimulator

  describe "end-to-end telemetry flow" do
    setup do
      # Create test organization
      {:ok, org} =
        Organizations.create_organization(%{
          name: "Test Org",
          slug: "test-org-#{System.unique_integer([:positive])}"
        })

      # Create test mission
      {:ok, mission} =
        Missions.create_mission(org.id, %{
          name: "Test Mission",
          slug: "test-mission-#{System.unique_integer([:positive])}",
          description: "Integration test mission",
          status: "active"
        })

      # Start the mission (starts CVT, PacketIdentifier, Pipeline)
      {:ok, _pid} = MissionSupervisor.start_mission(mission)

      # Give processes time to initialize
      Process.sleep(100)

      %{org: org, mission: mission}
    end

    test "simulator packets flow through pipeline to CVT", %{mission: mission} do
      # Subscribe to telemetry updates to verify broadcasting
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:telemetry")

      # Start packet simulator
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["test-target-1"],
          packet_types: [:health],
          rate_hz: 10.0,
          # PubSub only (no network output for test)
          output: nil
        )

      # Wait for a few packets to be generated and processed
      Process.sleep(500)

      # Verify we received telemetry updates via PubSub
      assert_received {:telemetry_update, "test-target-1", "HEALTH", item_name, telemetry_value}
      assert is_binary(item_name)
      assert is_map(telemetry_value)
      assert Map.has_key?(telemetry_value, :value)
      assert Map.has_key?(telemetry_value, :received_time)

      # Verify data is in CVT
      {:ok, cpu_temp} = CurrentValueTable.get(mission.id, "test-target-1", "HEALTH", "cpu_temp")

      assert is_map(cpu_temp)
      assert is_number(cpu_temp.value)
      assert cpu_temp.limits_state == :green
      assert %DateTime{} = cpu_temp.received_time

      # Verify pipeline stats
      stats = Pipeline.stats(mission.id)
      assert stats.packets_processed > 0
      assert stats.items_processed > 0
      assert stats.errors == 0

      # Verify CVT stats
      cvt_stats = CurrentValueTable.stats(mission.id)
      assert cvt_stats.total_entries > 0

      # Stop simulator
      PacketSimulator.stop(sim_pid)

      # Stop mission
      MissionSupervisor.stop_mission(mission.id)
    end

    test "multiple packet types are processed correctly", %{mission: mission} do
      # Start simulator with multiple packet types
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["test-target-1"],
          packet_types: [:health, :attitude, :power],
          rate_hz: 5.0,
          output: nil
        )

      # Wait for packets to be processed
      Process.sleep(1000)

      # Verify all packet types are in CVT
      {:ok, cpu_temp} = CurrentValueTable.get(mission.id, "test-target-1", "HEALTH", "cpu_temp")
      assert is_number(cpu_temp.value)

      {:ok, roll} = CurrentValueTable.get(mission.id, "test-target-1", "ATTITUDE", "roll")
      assert is_number(roll.value)

      {:ok, bus_voltage} =
        CurrentValueTable.get(mission.id, "test-target-1", "POWER", "bus_voltage")

      assert is_number(bus_voltage.value)

      # Cleanup
      PacketSimulator.stop(sim_pid)
      MissionSupervisor.stop_mission(mission.id)
    end

    test "multiple targets are isolated correctly", %{mission: mission} do
      # Start simulator with multiple targets
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["sat-1", "sat-2", "sat-3"],
          packet_types: [:health],
          rate_hz: 5.0,
          output: nil
        )

      # Wait for packets
      Process.sleep(800)

      # Verify each target has separate telemetry
      {:ok, sat1_temp} = CurrentValueTable.get(mission.id, "sat-1", "HEALTH", "cpu_temp")
      {:ok, sat2_temp} = CurrentValueTable.get(mission.id, "sat-2", "HEALTH", "cpu_temp")
      {:ok, sat3_temp} = CurrentValueTable.get(mission.id, "sat-3", "HEALTH", "cpu_temp")

      # All should have values
      assert is_number(sat1_temp.value)
      assert is_number(sat2_temp.value)
      assert is_number(sat3_temp.value)

      # Values should be different (simulator adds noise)
      # Note: There's a small chance they could be equal, but very unlikely
      values = [sat1_temp.value, sat2_temp.value, sat3_temp.value]
      assert length(Enum.uniq(values)) > 1

      # Cleanup
      PacketSimulator.stop(sim_pid)
      MissionSupervisor.stop_mission(mission.id)
    end

    test "CVT maintains most recent value only", %{mission: mission} do
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["test-target-1"],
          packet_types: [:health],
          rate_hz: 10.0,
          output: nil
        )

      # Get initial value
      Process.sleep(200)
      {:ok, initial} = CurrentValueTable.get(mission.id, "test-target-1", "HEALTH", "cpu_temp")
      initial_time = initial.received_time

      # Wait for more packets
      Process.sleep(500)

      # Get updated value
      {:ok, updated} = CurrentValueTable.get(mission.id, "test-target-1", "HEALTH", "cpu_temp")
      updated_time = updated.received_time

      # Verify time has advanced (newer value)
      assert DateTime.compare(updated_time, initial_time) == :gt

      # CVT should only have one entry per item (most recent)
      target_telemetry = CurrentValueTable.get_target_telemetry(mission.id, "test-target-1")

      # Count how many times cpu_temp appears
      cpu_temp_count =
        Enum.count(target_telemetry, fn {{_tid, _pname, item}, _val} ->
          item == "cpu_temp"
        end)

      assert cpu_temp_count == 1

      # Cleanup
      PacketSimulator.stop(sim_pid)
      MissionSupervisor.stop_mission(mission.id)
    end
  end
end
