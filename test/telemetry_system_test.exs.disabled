defmodule Cadence.TelemetrySystemTest do
  @moduledoc """
  End-to-end test for the complete telemetry system.

  Tests the full flow:
  Interface → Protocol Chain → Broadway → Decommutation → Conversions → CVT
  """

  use Cadence.DataCase
  import Cadence.Factory

  alias Cadence.Missions
  alias Cadence.Targets
  alias Cadence.Interfaces
  alias Cadence.Telemetry.{Packet, Conversions, CurrentValueTable}

  describe "Complete Telemetry Flow" do
    setup do
      # Create organization
      org = insert(:organization)

      # Create mission
      {:ok, mission} =
        Missions.create_mission(%{
          name: "Test Mission",
          description: "Testing telemetry system",
          organization_id: org.id,
          status: "active"
        })

      # Create target
      {:ok, target} =
        Targets.create_target(%{
          name: "Test Satellite",
          identifier: "SAT-001",
          type: "spacecraft",
          mission_id: mission.id
        })

      # Create packet definition with items
      {:ok, packet_def} =
        Packet.create_packet_definition(%{
          name: "HEALTH",
          target_id: target.id,
          mission_id: mission.id,
          type_byte: 1,
          description: "Health telemetry"
        })

      # Create temperature conversion (ADC counts to Celsius)
      # Temp = -50 + 0.1 * ADC
      {:ok, temp_conversion} =
        Conversions.create_polynomial_conversion(%{
          name: "TEMP_SENSOR",
          mission_id: mission.id,
          coefficients: [-50.0, 0.1]
        })

      # Create mode state table conversion
      {:ok, mode_conversion} =
        Conversions.create_state_table_conversion(%{
          name: "POWER_MODE",
          mission_id: mission.id,
          states: %{"0" => "OFF", "1" => "STANDBY", "2" => "NOMINAL"},
          default_state: "UNKNOWN"
        })

      # Create packet items
      {:ok, _temp_item} =
        Packet.create_packet_item(%{
          packet_definition_id: packet_def.id,
          name: "cpu_temp",
          bit_offset: 0,
          bit_size: 32,
          data_type: "uint",
          endianness: "big_endian",
          conversion_id: temp_conversion.id
        })

      {:ok, _voltage_item} =
        Packet.create_packet_item(%{
          packet_definition_id: packet_def.id,
          name: "battery_voltage",
          bit_offset: 32,
          bit_size: 32,
          data_type: "uint",
          endianness: "big_endian"
        })

      {:ok, _mode_item} =
        Packet.create_packet_item(%{
          packet_definition_id: packet_def.id,
          name: "power_mode",
          bit_offset: 64,
          bit_size: 8,
          data_type: "uint",
          endianness: "big_endian",
          conversion_id: mode_conversion.id
        })

      # Create interface
      {:ok, interface} =
        Interfaces.create_interface(%{
          name: "TCP_TEST",
          connection_type: "tcp_client",
          host: "127.0.0.1",
          port: 9999,
          mission_id: mission.id,
          config: %{"target_id" => target.id}
        })

      # Link target to interface
      {:ok, _} = Interfaces.add_target_to_interface(target, interface, "read")

      %{
        mission: mission,
        target: target,
        interface: interface,
        packet_def: packet_def
      }
    end

    test "full telemetry flow", %{mission: mission, target: target} do
      # Activate mission (starts Broadway pipeline, interface supervisor, etc.)
      {:ok, _} = Missions.activate_mission(mission)

      # Give the system time to start up
      Process.sleep(100)

      # Simulate a binary telemetry packet
      # Format: <<cpu_temp:32, battery_voltage:32, power_mode:8>>
      # cpu_temp = 1000 (ADC counts) → should convert to 50.0°C (-50 + 0.1*1000)
      # battery_voltage = 14200 (millivolts, no conversion)
      # power_mode = 2 → should convert to "NOMINAL"

      binary_payload = <<
        1000::32-big-unsigned,
        # cpu_temp ADC
        14200::32-big-unsigned,
        # battery_voltage
        2::8-unsigned
        # power_mode
      >>

      # Wrap in simulator packet format
      # [type_byte:8][target_id_len:8][target_id][payload]
      target_id = "SAT-001"
      target_id_len = byte_size(target_id)

      full_packet = <<
        1::8,
        # type_byte (HEALTH)
        target_id_len::8,
        # target_id length
        target_id::binary,
        # target_id
        binary_payload::binary
        # payload
      >>

      # Publish to telemetry raw topic (Broadway will process)
      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "mission:#{mission.id}:telemetry:raw",
        {:telemetry_packet, full_packet, %{received_at: DateTime.utc_now(), stored: false}}
      )

      # Give Broadway time to process
      Process.sleep(200)

      # Check CVT for values
      cvt_values = CurrentValueTable.get_all(mission.id, target.id)

      # Verify cpu_temp was converted
      assert cvt_values["HEALTH"]["cpu_temp"] == 50.0

      # Verify battery_voltage (no conversion)
      assert cvt_values["HEALTH"]["battery_voltage"] == 14200

      # Verify power_mode was converted to state string
      assert cvt_values["HEALTH"]["power_mode"] == "NOMINAL"

      # Clean up
      Missions.deactivate_mission(mission.id)
    end
  end
end
