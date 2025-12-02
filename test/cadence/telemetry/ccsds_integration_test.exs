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

  use Cadence.DataCase

  import Bitwise

  alias Cadence.{Organizations, Missions}
  alias Cadence.Missions.MissionSupervisor
  alias Cadence.Simulator.PacketSimulator
  alias Cadence.Telemetry.{CurrentValueTable, Pipeline}
  alias Cadence.Telemetry.Protocols.TemplateProtocol

  @ccsds_sync <<0x1A, 0xCF, 0xFC, 0x1D>>

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
        Missions.create_mission(%{
          organization_id: org.id,
          name: "CCSDS Test Mission",
          slug: "ccsds-test-mission-#{System.unique_integer([:positive])}",
          description: "Testing CCSDS binary telemetry processing",
          status: "active"
        })

      # Start the mission (starts CVT, PacketIdentifier, Pipeline)
      {:ok, _pid} = MissionSupervisor.start_mission(mission)

      # Give processes time to initialize
      Process.sleep(100)

      %{org: org, mission: mission}
    end

    test "processes CCSDS binary packets end-to-end", %{mission: mission} do
      # Subscribe to telemetry updates
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:telemetry")

      # Start packet simulator in CCSDS mode
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["ccsds-sat-1"],
          packet_types: [:health],
          rate_hz: 5.0,
          encoding: :ccsds,
          # CCSDS binary encoding
          output: nil
        )

      # Wait for packets to be generated and processed
      Process.sleep(800)

      # Verify we received telemetry updates via PubSub
      assert_received {:telemetry_update, "ccsds-sat-1", "HEALTH", item_name, telemetry_value}
      assert is_binary(item_name)
      assert is_map(telemetry_value)
      assert Map.has_key?(telemetry_value, :value)

      # Verify data is in CVT - check multiple fields
      {:ok, cpu_temp} =
        CurrentValueTable.get(mission.id, "ccsds-sat-1", "HEALTH", "cpu_temp")

      {:ok, voltage} =
        CurrentValueTable.get(mission.id, "ccsds-sat-1", "HEALTH", "battery_voltage")

      {:ok, uptime} =
        CurrentValueTable.get(mission.id, "ccsds-sat-1", "HEALTH", "uptime_seconds")

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
      stats = Pipeline.stats(mission.id)
      assert stats.packets_processed > 0
      assert stats.items_processed > 0
      assert stats.errors == 0

      # Cleanup
      PacketSimulator.stop(sim_pid)
      MissionSupervisor.stop_mission(mission.id)
    end

    test "processes all three CCSDS packet types", %{mission: mission} do
      # Start simulator with all packet types
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["multi-sat"],
          packet_types: [:health, :attitude, :power],
          rate_hz: 5.0,
          encoding: :ccsds,
          output: nil
        )

      Process.sleep(1000)

      # Verify HEALTH packet (APID 100)
      {:ok, cpu_temp} = CurrentValueTable.get(mission.id, "multi-sat", "HEALTH", "cpu_temp")
      assert is_number(cpu_temp.value)

      {:ok, battery_pct} =
        CurrentValueTable.get(mission.id, "multi-sat", "HEALTH", "battery_percentage")

      assert is_number(battery_pct.value)
      assert battery_pct.value >= 0 and battery_pct.value <= 100

      # Verify ATTITUDE packet (APID 101)
      {:ok, roll} = CurrentValueTable.get(mission.id, "multi-sat", "ATTITUDE", "roll")
      assert is_number(roll.value)

      {:ok, pitch} = CurrentValueTable.get(mission.id, "multi-sat", "ATTITUDE", "pitch")
      assert is_number(pitch.value)

      {:ok, yaw} = CurrentValueTable.get(mission.id, "multi-sat", "ATTITUDE", "yaw")
      assert is_number(yaw.value)

      # Verify POWER packet (APID 102)
      {:ok, bus_voltage} = CurrentValueTable.get(mission.id, "multi-sat", "POWER", "bus_voltage")
      assert is_number(bus_voltage.value)

      {:ok, solar_current} =
        CurrentValueTable.get(mission.id, "multi-sat", "POWER", "solar_panel_current")

      assert is_number(solar_current.value)

      # Cleanup
      PacketSimulator.stop(sim_pid)
      MissionSupervisor.stop_mission(mission.id)
    end

    test "handles multiple targets with CCSDS packets", %{mission: mission} do
      # Start simulator with 3 satellites
      {:ok, sim_pid} =
        PacketSimulator.start_link(
          mission_id: mission.id,
          targets: ["sat-a", "sat-b", "sat-c"],
          packet_types: [:health],
          rate_hz: 5.0,
          encoding: :ccsds,
          output: nil
        )

      Process.sleep(1000)

      # Each satellite should have separate telemetry in CVT
      {:ok, temp_a} = CurrentValueTable.get(mission.id, "sat-a", "HEALTH", "cpu_temp")
      {:ok, temp_b} = CurrentValueTable.get(mission.id, "sat-b", "HEALTH", "cpu_temp")
      {:ok, temp_c} = CurrentValueTable.get(mission.id, "sat-c", "HEALTH", "cpu_temp")

      # All should have values
      assert is_number(temp_a.value)
      assert is_number(temp_b.value)
      assert is_number(temp_c.value)

      # Values should be different (simulator adds noise)
      values = [temp_a.value, temp_b.value, temp_c.value]
      assert length(Enum.uniq(values)) > 1

      # Cleanup
      PacketSimulator.stop(sim_pid)
      MissionSupervisor.stop_mission(mission.id)
    end

    test "CCSDS protocol framing works correctly" do
      # Test the protocol layer directly with CCSDS packets
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6
        )

      # Build a CCSDS packet manually
      apid = 100
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

      # Process chunks sequentially - returns {:stop, state} when buffering
      {:stop, state1} = TemplateProtocol.read_data(chunk1, state)
      assert byte_size(state1.buffer) > 0

      {:stop, state2} = TemplateProtocol.read_data(chunk2, state1)
      # May still be buffering

      {:ok, packets, state3} = TemplateProtocol.read_data(chunk3, state2)

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
end
