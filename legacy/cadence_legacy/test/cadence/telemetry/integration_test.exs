defmodule Cadence.Telemetry.IntegrationTest do
  @moduledoc """
  End-to-end integration test for the telemetry pipeline.

  Tests the complete flow:
  1. Packet Simulator generates telemetry
  2. Telemetry Pipeline parses and resolves packets
  3. Decommutation extracts telemetry items
  4. CVT stores current values
  5. PubSub broadcasts updates
  """

  use Cadence.IntegrationCase

  import Cadence.MissionDatabaseFixtures
  import Cadence.TargetsFixtures

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.{Missions, Organizations}
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Simulator.PacketSimulator
  alias Cadence.Telemetry.PipelineMetrics

  defp wait_for(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    interval = Keyword.get(opts, :interval, 25)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_for(fun, deadline, interval)
  end

  defp do_wait_for(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(interval)
        do_wait_for(fun, deadline, interval)
      else
        flunk("Condition was not met within timeout")
      end
    end
  end

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

      definition_set = create_sim_definition_set(org, mission)

      create_sim_targets(org, mission, definition_set, [
        "TEST_TARGET_1",
        "SAT_1",
        "SAT_2",
        "SAT_3"
      ])

      # Start the mission (starts CVT and pipeline)
      {:ok, config} = MissionConfig.load(mission.id)
      {:ok, _pid} = MissionSupervisor.start_mission(config)

      on_exit(fn ->
        MissionSupervisor.stop_mission(mission.id)
      end)

      %{org: org, mission: mission, definition_set: definition_set}
    end

    test "simulator packets flow through pipeline to CVT", %{mission: mission} do
      # Subscribe to telemetry updates to verify broadcasting
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:telemetry")

      # Start packet simulator
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["TEST_TARGET_1"],
          packet_types: [:health],
          rate_hz: 10.0,
          # PubSub only (no network output for test)
          output: nil
        )

      on_exit(fn ->
        if Process.alive?(sim_pid), do: PacketSimulator.stop(sim_pid)
      end)

      # Verify we received telemetry updates via PubSub
      assert_receive {:telemetry_packet_update, "TEST_TARGET_1", "HEALTH", items}, 2_000

      {item_name, telemetry_value} =
        Enum.find(items, fn {name, _value} ->
          String.ends_with?(name, "cpu_temp")
        end)

      assert is_binary(item_name)
      assert is_map(telemetry_value)
      assert Map.has_key?(telemetry_value, :value)
      assert Map.has_key?(telemetry_value, :received_time)

      # Verify data is in CVT
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")
          )
        end)

      {:ok, cpu_temp} =
        CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")

      assert is_map(cpu_temp)
      assert is_number(cpu_temp.value)
      assert cpu_temp.limits_state == :green
      assert %DateTime{} = cpu_temp.received_time

      # Verify pipeline stats
      :ok =
        wait_for(fn ->
          stats = PipelineMetrics.get_stats(mission.id)
          stats.packets_processed > 0 and stats.items_processed > 0
        end)

      # Verify CVT stats
      :ok =
        wait_for(fn ->
          cvt_stats = CurrentValueTable.stats(mission.id)
          cvt_stats.total_entries > 0
        end)
    end

    test "multiple packet types are processed correctly", %{mission: mission} do
      # Start simulator with multiple packet types
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["TEST_TARGET_1"],
          packet_types: [:health, :attitude, :power],
          rate_hz: 5.0,
          output: nil
        )

      on_exit(fn ->
        if Process.alive?(sim_pid), do: PacketSimulator.stop(sim_pid)
      end)

      # Verify all packet types are in CVT
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")
          )
        end)

      {:ok, cpu_temp} =
        CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")

      assert is_number(cpu_temp.value)

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "TEST_TARGET_1", "ATTITUDE", "ATTITUDE.roll")
          )
        end)

      {:ok, roll} =
        CurrentValueTable.get(mission.id, "TEST_TARGET_1", "ATTITUDE", "ATTITUDE.roll")

      assert is_number(roll.value)

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "TEST_TARGET_1", "POWER", "POWER.bus_voltage")
          )
        end)

      {:ok, bus_voltage} =
        CurrentValueTable.get(mission.id, "TEST_TARGET_1", "POWER", "POWER.bus_voltage")

      assert is_number(bus_voltage.value)
    end

    test "multiple targets are isolated correctly", %{mission: mission} do
      # Start simulator with multiple targets
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["SAT_1", "SAT_2", "SAT_3"],
          packet_types: [:health],
          rate_hz: 5.0,
          output: nil
        )

      on_exit(fn ->
        if Process.alive?(sim_pid), do: PacketSimulator.stop(sim_pid)
      end)

      # Verify each target has separate telemetry
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "SAT_1", "HEALTH", "HEALTH.cpu_temp")
          ) and
            match?(
              {:ok, _},
              CurrentValueTable.get(mission.id, "SAT_2", "HEALTH", "HEALTH.cpu_temp")
            ) and
            match?(
              {:ok, _},
              CurrentValueTable.get(mission.id, "SAT_3", "HEALTH", "HEALTH.cpu_temp")
            )
        end)

      {:ok, sat1_temp} = CurrentValueTable.get(mission.id, "SAT_1", "HEALTH", "HEALTH.cpu_temp")
      {:ok, sat2_temp} = CurrentValueTable.get(mission.id, "SAT_2", "HEALTH", "HEALTH.cpu_temp")
      {:ok, sat3_temp} = CurrentValueTable.get(mission.id, "SAT_3", "HEALTH", "HEALTH.cpu_temp")

      # All should have values
      assert is_number(sat1_temp.value)
      assert is_number(sat2_temp.value)
      assert is_number(sat3_temp.value)
    end

    test "CVT maintains most recent value only", %{mission: mission} do
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["TEST_TARGET_1"],
          packet_types: [:health],
          rate_hz: 10.0,
          output: nil
        )

      # Get initial value
      on_exit(fn ->
        if Process.alive?(sim_pid), do: PacketSimulator.stop(sim_pid)
      end)

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")
          )
        end)

      {:ok, initial} =
        CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")

      initial_time = initial.received_time

      # Wait for more packets
      :ok =
        wait_for(
          fn ->
            {:ok, updated} =
              CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")

            DateTime.compare(updated.received_time, initial_time) == :gt
          end,
          timeout: 3_000
        )

      # Get updated value
      {:ok, updated} =
        CurrentValueTable.get(mission.id, "TEST_TARGET_1", "HEALTH", "HEALTH.cpu_temp")

      updated_time = updated.received_time

      # Verify time has advanced (newer value)
      assert DateTime.compare(updated_time, initial_time) == :gt

      # CVT should only have one entry per item (most recent)
      target_telemetry = CurrentValueTable.get_target_telemetry(mission.id, "TEST_TARGET_1")

      # Count how many times cpu_temp appears
      cpu_temp_count =
        Enum.count(target_telemetry, fn {{_tid, _pname, item}, _val} ->
          item == "HEALTH.cpu_temp"
        end)

      assert cpu_temp_count == 1
    end
  end

  defp create_sim_definition_set(org, mission) do
    database = database_fixture(organization: org, mission: mission)

    definition_set =
      definition_set_fixture(organization: org, mission: mission, database: database)

    float_dt = float_data_type_fixture(definition_set: definition_set)

    uint32_dt =
      data_type_fixture(
        definition_set: definition_set,
        base_type: :integer,
        encoding: %{
          encoding_type: :integer,
          size_in_bits: 32,
          byte_order: :big_endian,
          integer_encoding: :unsigned
        }
      )

    uint16_dt =
      data_type_fixture(
        definition_set: definition_set,
        base_type: :integer,
        encoding: %{
          encoding_type: :integer,
          size_in_bits: 16,
          byte_order: :big_endian,
          integer_encoding: :unsigned
        }
      )

    uint8_dt =
      data_type_fixture(
        definition_set: definition_set,
        base_type: :integer,
        encoding: %{
          encoding_type: :integer,
          size_in_bits: 8,
          byte_order: :big_endian,
          integer_encoding: :unsigned
        }
      )

    health =
      container_fixture(
        definition_set: definition_set,
        name: "HEALTH",
        apid: 100
      )

    add_entry(definition_set, health, "cpu_temp", float_dt, 0)
    add_entry(definition_set, health, "battery_voltage", float_dt, 32)
    add_entry(definition_set, health, "battery_current", float_dt, 64)
    add_entry(definition_set, health, "battery_percentage", uint8_dt, 96)
    add_entry(definition_set, health, "uptime_seconds", uint32_dt, 104)
    add_entry(definition_set, health, "memory_used_mb", uint16_dt, 136)

    attitude =
      container_fixture(
        definition_set: definition_set,
        name: "ATTITUDE",
        apid: 101
      )

    add_entry(definition_set, attitude, "roll", float_dt, 0)
    add_entry(definition_set, attitude, "pitch", float_dt, 32)
    add_entry(definition_set, attitude, "yaw", float_dt, 64)
    add_entry(definition_set, attitude, "roll_rate", float_dt, 96)
    add_entry(definition_set, attitude, "pitch_rate", float_dt, 128)
    add_entry(definition_set, attitude, "yaw_rate", float_dt, 160)

    power =
      container_fixture(
        definition_set: definition_set,
        name: "POWER",
        apid: 102
      )

    add_entry(definition_set, power, "solar_panel_voltage", float_dt, 0)
    add_entry(definition_set, power, "solar_panel_current", float_dt, 32)
    add_entry(definition_set, power, "bus_voltage", float_dt, 64)
    add_entry(definition_set, power, "bus_current", float_dt, 96)
    add_entry(definition_set, power, "power_mode", uint8_dt, 128)

    definition_set
  end

  defp add_entry(definition_set, container, name, data_type, bit_offset) do
    parameter =
      parameter_fixture(
        definition_set: definition_set,
        data_type: data_type,
        name: name
      )

    container_entry_fixture(
      container: container,
      parameter: parameter,
      bit_offset: bit_offset
    )
  end

  defp create_sim_targets(org, mission, definition_set, identifiers) do
    Enum.each(identifiers, fn identifier ->
      target_fixture(
        organization: org,
        mission: mission,
        definition_set: definition_set,
        name: identifier,
        identifier: identifier,
        status: "online"
      )
    end)
  end
end
