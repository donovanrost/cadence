defmodule Cadence.Telemetry.CcsdsIntegrationTest do
  @moduledoc """
  Integration test for CCSDS telemetry processing.

  Tests the complete realistic spacecraft telemetry flow:
  1. PacketSimulator generates CCSDS binary packets
  2. Protocol framing extracts packets using template (sync pattern)
  3. PacketIdentifier identifies packets by APID
  4. Decommutation extracts binary telemetry fields
  5. CVT stores values
  6. PubSub broadcasts updates

  This validates that we can process real spacecraft telemetry.
  """

  use Cadence.IntegrationCase

  import Bitwise
  import Cadence.MissionDatabaseFixtures
  import Cadence.TargetsFixtures

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.{Missions, Organizations}
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Runtime.Telemetry.CurrentValueTable
  alias Cadence.Simulator.PacketSimulator
  alias Cadence.Telemetry.PipelineMetrics
  alias Cadence.Telemetry.Protocols.TemplateProtocol

  @ccsds_sync <<0x1A, 0xCF, 0xFC, 0x1D>>

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

  describe "CCSDS telemetry processing" do
    setup do
      # Create test organization
      {:ok, org} =
        Organizations.create_organization(%{
          name: "CCSDS Test Org",
          slug: "ccsds-test-org-#{System.unique_integer([:positive])}"
        })

      # Create test mission
      {:ok, mission} =
        Missions.create_mission(org.id, %{
          name: "CCSDS Test Mission",
          slug: "ccsds-test-mission-#{System.unique_integer([:positive])}",
          description: "Testing CCSDS binary telemetry processing",
          status: "active"
        })

      definition_set = create_ccsds_definition_set(org, mission)

      create_ccsds_targets(org, mission, definition_set, [
        "CCSDS_SAT_1",
        "MULTI_SAT",
        "SAT_A",
        "SAT_B",
        "SAT_C"
      ])

      # Start the mission (starts CVT, PacketIdentifier, Pipeline)
      {:ok, config} = MissionConfig.load(mission.id)
      {:ok, _pid} = MissionSupervisor.start_mission(config)

      on_exit(fn ->
        MissionSupervisor.stop_mission(mission.id)
      end)

      %{org: org, mission: mission, definition_set: definition_set}
    end

    test "processes CCSDS binary packets end-to-end", %{mission: mission} do
      # Subscribe to telemetry updates
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:telemetry")

      # Start packet simulator in CCSDS mode
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["CCSDS_SAT_1"],
          packet_types: [:health],
          rate_hz: 5.0,
          encoding: :ccsds,
          # CCSDS binary encoding
          output: nil
        )

      on_exit(fn ->
        if Process.alive?(sim_pid), do: PacketSimulator.stop(sim_pid)
      end)

      # Verify we received telemetry updates via PubSub
      assert_receive {:telemetry_packet_update, "CCSDS_SAT_1", "HEALTH", items}, 2_000

      {item_name, telemetry_value} =
        Enum.find(items, fn {name, _value} ->
          String.ends_with?(name, "cpu_temp")
        end)

      assert is_binary(item_name)
      assert is_map(telemetry_value)
      assert Map.has_key?(telemetry_value, :value)

      # Verify data is in CVT - check multiple fields
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "CCSDS_SAT_1", "HEALTH", "HEALTH.cpu_temp")
          )
        end)

      {:ok, cpu_temp} =
        CurrentValueTable.get(mission.id, "CCSDS_SAT_1", "HEALTH", "HEALTH.cpu_temp")

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "CCSDS_SAT_1", "HEALTH", "HEALTH.battery_voltage")
          )
        end)

      {:ok, voltage} =
        CurrentValueTable.get(mission.id, "CCSDS_SAT_1", "HEALTH", "HEALTH.battery_voltage")

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "CCSDS_SAT_1", "HEALTH", "HEALTH.uptime_seconds")
          )
        end)

      {:ok, uptime} =
        CurrentValueTable.get(mission.id, "CCSDS_SAT_1", "HEALTH", "HEALTH.uptime_seconds")

      # CPU temp should be a reasonable value (simulator generates ~20°C with variation)
      assert is_number(cpu_temp.value)
      assert cpu_temp.value > 0.0
      assert cpu_temp.value < 50.0

      # Battery voltage should be realistic (simulator generates ~14.5V)
      assert is_number(voltage.value)
      assert voltage.value > 10.0
      assert voltage.value < 20.0

      # Uptime should be an integer
      assert is_integer(uptime.value)
      assert uptime.value >= 0

      # Verify pipeline stats
      :ok =
        wait_for(fn ->
          stats = PipelineMetrics.get_stats(mission.id)
          stats.packets_processed > 0 and stats.items_processed > 0
        end)
    end

    test "processes all three CCSDS packet types", %{mission: mission} do
      # Start simulator with all packet types
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["MULTI_SAT"],
          packet_types: [:health, :attitude, :power],
          rate_hz: 5.0,
          encoding: :ccsds,
          output: nil
        )

      on_exit(fn ->
        if Process.alive?(sim_pid), do: PacketSimulator.stop(sim_pid)
      end)

      # Verify HEALTH packet (APID 100)
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "MULTI_SAT", "HEALTH", "HEALTH.cpu_temp")
          )
        end)

      {:ok, cpu_temp} =
        CurrentValueTable.get(mission.id, "MULTI_SAT", "HEALTH", "HEALTH.cpu_temp")

      assert is_number(cpu_temp.value)

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "MULTI_SAT", "HEALTH", "HEALTH.battery_percentage")
          )
        end)

      {:ok, battery_pct} =
        CurrentValueTable.get(mission.id, "MULTI_SAT", "HEALTH", "HEALTH.battery_percentage")

      assert is_number(battery_pct.value)
      assert battery_pct.value >= 0 and battery_pct.value <= 100

      # Verify ATTITUDE packet (APID 101)
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "MULTI_SAT", "ATTITUDE", "ATTITUDE.roll")
          )
        end)

      {:ok, roll} = CurrentValueTable.get(mission.id, "MULTI_SAT", "ATTITUDE", "ATTITUDE.roll")
      assert is_number(roll.value)

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "MULTI_SAT", "ATTITUDE", "ATTITUDE.pitch")
          )
        end)

      {:ok, pitch} =
        CurrentValueTable.get(mission.id, "MULTI_SAT", "ATTITUDE", "ATTITUDE.pitch")

      assert is_number(pitch.value)

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "MULTI_SAT", "ATTITUDE", "ATTITUDE.yaw")
          )
        end)

      {:ok, yaw} = CurrentValueTable.get(mission.id, "MULTI_SAT", "ATTITUDE", "ATTITUDE.yaw")
      assert is_number(yaw.value)

      # Verify POWER packet (APID 102)
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "MULTI_SAT", "POWER", "POWER.bus_voltage")
          )
        end)

      {:ok, bus_voltage} =
        CurrentValueTable.get(mission.id, "MULTI_SAT", "POWER", "POWER.bus_voltage")

      assert is_number(bus_voltage.value)

      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "MULTI_SAT", "POWER", "POWER.solar_panel_current")
          )
        end)

      {:ok, solar_current} =
        CurrentValueTable.get(mission.id, "MULTI_SAT", "POWER", "POWER.solar_panel_current")

      assert is_number(solar_current.value)
    end

    test "handles multiple targets with CCSDS packets", %{mission: mission} do
      # Start simulator with 3 satellites
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["SAT_A", "SAT_B", "SAT_C"],
          packet_types: [:health],
          rate_hz: 5.0,
          encoding: :ccsds,
          output: nil
        )

      on_exit(fn ->
        if Process.alive?(sim_pid), do: PacketSimulator.stop(sim_pid)
      end)

      # Each satellite should have separate telemetry in CVT
      :ok =
        wait_for(fn ->
          match?(
            {:ok, _},
            CurrentValueTable.get(mission.id, "SAT_A", "HEALTH", "HEALTH.cpu_temp")
          ) and
            match?(
              {:ok, _},
              CurrentValueTable.get(mission.id, "SAT_B", "HEALTH", "HEALTH.cpu_temp")
            ) and
            match?(
              {:ok, _},
              CurrentValueTable.get(mission.id, "SAT_C", "HEALTH", "HEALTH.cpu_temp")
            )
        end)

      {:ok, temp_a} = CurrentValueTable.get(mission.id, "SAT_A", "HEALTH", "HEALTH.cpu_temp")
      {:ok, temp_b} = CurrentValueTable.get(mission.id, "SAT_B", "HEALTH", "HEALTH.cpu_temp")
      {:ok, temp_c} = CurrentValueTable.get(mission.id, "SAT_C", "HEALTH", "HEALTH.cpu_temp")

      # All should have values
      assert is_number(temp_a.value)
      assert is_number(temp_b.value)
      assert is_number(temp_c.value)
    end

    test "CCSDS protocol framing works correctly" do
      # Test the protocol layer directly with CCSDS packets
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6
        )

      # Build a CCSDS packet manually
      _apid = 100
      seq_count = 42
      payload_data = :crypto.strong_rand_bytes(27)
      # 8 byte secondary header + 19 byte user data

      # CCSDS primary header
      packet_id = 0x0864
      # version=0, type=0, sec_hdr=1, apid=100
      seq_control = 0xC000 + seq_count
      data_length = byte_size(payload_data) - 1

      header = <<packet_id::16, seq_control::16, data_length::16>>
      complete_packet = @ccsds_sync <> header <> payload_data

      # Process the packet
      {:ok, [extracted], _new_state} = TemplateProtocol.read_data(complete_packet, state)

      # Should extract the complete packet including sync
      assert extracted == complete_packet
      assert byte_size(extracted) == 4 + 6 + 27
    end

    test "handles fragmented CCSDS packets over TCP stream" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6
        )

      # Build a CCSDS packet
      payload = :crypto.strong_rand_bytes(20)
      header = <<0x0864::16, 0xC000::16, 19::16>>
      complete_packet = @ccsds_sync <> header <> payload

      # Split into random chunks to simulate TCP stream
      total_size = byte_size(complete_packet)
      chunk1_size = div(total_size, 3)
      chunk2_size = div(total_size, 2)

      chunk1 = binary_part(complete_packet, 0, chunk1_size)
      chunk2 = binary_part(complete_packet, chunk1_size, chunk2_size - chunk1_size)
      chunk3 = binary_part(complete_packet, chunk2_size, total_size - chunk2_size)

      # Process chunks sequentially
      {[], state1} = read_packets(chunk1, state)
      assert byte_size(state1.buffer) > 0

      {[], state2} = read_packets(chunk2, state1)
      # May still be buffering

      {packets, state3} = read_packets(chunk3, state2)

      # Should have extracted the complete packet
      assert length(packets) == 1
      assert hd(packets) == complete_packet
      assert state3.buffer == <<>>
    end

    test "validates CCSDS packet structure after deframing" do
      # Ensure extracted packets have correct CCSDS structure
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6
        )

      # Create packet with known values
      apid = 101
      # ATTITUDE
      seq_count = 123
      payload = :crypto.strong_rand_bytes(32)

      version = 0
      type = 0
      sec_hdr = 1
      packet_id = version <<< 13 ||| type <<< 12 ||| sec_hdr <<< 11 ||| apid

      seq_flags = 3
      seq_control = seq_flags <<< 14 ||| seq_count

      data_length = byte_size(payload) - 1
      header = <<packet_id::16, seq_control::16, data_length::16>>

      complete_packet = @ccsds_sync <> header <> payload

      {:ok, [extracted], _state} = TemplateProtocol.read_data(complete_packet, state)

      # Parse the extracted packet
      <<sync::binary-size(4), pkt_id::16, seq_ctrl::16, data_len::16, rest::binary>> = extracted

      # Verify sync pattern
      assert sync == @ccsds_sync

      # Verify APID
      extracted_apid = pkt_id &&& 0x07FF
      assert extracted_apid == apid

      # Verify sequence count
      extracted_seq = seq_ctrl &&& 0x3FFF
      assert extracted_seq == seq_count

      # Verify data length
      assert data_len == byte_size(payload) - 1
      assert byte_size(rest) == byte_size(payload)
    end
  end

  defp read_packets(chunk, state) do
    case TemplateProtocol.read_data(chunk, state) do
      {:ok, packets, new_state} -> {packets, new_state}
      {:stop, new_state} -> {[], new_state}
    end
  end

  defp create_ccsds_definition_set(org, mission) do
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
        apid: 100,
        packet_type: 1
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
        apid: 101,
        packet_type: 2
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
        apid: 102,
        packet_type: 3
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

  defp create_ccsds_targets(org, mission, definition_set, identifiers) do
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
