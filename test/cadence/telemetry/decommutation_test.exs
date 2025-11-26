defmodule Cadence.Telemetry.DecommutationTest do
  @moduledoc """
  Unit tests for binary packet decommutation.

  Tests bit-level field extraction for all supported data types:
  - Unsigned integers (uint)
  - Signed integers (int)
  - Floats (32-bit and 64-bit)
  - Strings
  - Booleans
  """

  use ExUnit.Case, async: true

  alias Cadence.Telemetry.Decommutation

  describe "unsigned integer extraction" do
    test "extracts 8-bit uint at byte boundary" do
      packet = <<0x2A, 0x00, 0x00>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 8,
        data_type: "uint"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == 42
    end

    test "extracts 16-bit uint at byte boundary" do
      packet = <<0x12, 0x34, 0x00>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 16,
        data_type: "uint"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == 0x1234
    end

    test "extracts 32-bit uint at byte boundary" do
      packet = <<0xDE, 0xAD, 0xBE, 0xEF, 0x00>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 32,
        data_type: "uint"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == 0xDEADBEEF
    end

    test "extracts uint at non-byte boundary" do
      # Packet: 0b00011010 0b11001111 (0x1A 0xCF)
      # Extract 12 bits starting at bit 4: 0b101011001111 = 0xACF = 2767
      packet = <<0x1A, 0xCF>>

      item_def = %{
        name: "test_value",
        bit_offset: 4,
        bit_length: 12,
        data_type: "uint"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == 0x0ACF
    end

    test "extracts multiple uints from same packet" do
      # Packet layout: [temp:16][voltage:16][current:12][status:4]
      # temp=25 (0x0019), voltage=3600 (0x0E10), current=2748 (0xABC), status=15 (0xF)
      packet = <<0x00, 0x19, 0x0E, 0x10, 0xAB, 0xCF>>

      temp_def = %{name: "temperature", bit_offset: 0, bit_length: 16, data_type: "uint"}
      voltage_def = %{name: "voltage", bit_offset: 16, bit_length: 16, data_type: "uint"}
      current_def = %{name: "current", bit_offset: 32, bit_length: 12, data_type: "uint"}
      status_def = %{name: "status", bit_offset: 44, bit_length: 4, data_type: "uint"}

      {:ok, temp} = Decommutation.extract_field(packet, temp_def)
      {:ok, voltage} = Decommutation.extract_field(packet, voltage_def)
      {:ok, current} = Decommutation.extract_field(packet, current_def)
      {:ok, status} = Decommutation.extract_field(packet, status_def)

      assert temp == 25
      assert voltage == 3600
      assert current == 0xABC
      assert status == 15
    end

    test "returns error when packet too small" do
      packet = <<0x01, 0x02>>

      item_def = %{
        name: "test_value",
        bit_offset: 16,
        bit_length: 16,
        data_type: "uint"
      }

      {:error, :insufficient_data} = Decommutation.extract_field(packet, item_def)
    end
  end

  describe "signed integer extraction" do
    test "extracts positive signed integer" do
      # 8-bit: 42 (0x2A)
      packet = <<0x2A>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 8,
        data_type: "int"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == 42
    end

    test "extracts negative signed integer (two's complement)" do
      # 8-bit: -1 (0xFF)
      packet = <<0xFF>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 8,
        data_type: "int"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == -1
    end

    test "extracts 16-bit negative integer" do
      # -1000 in 16-bit two's complement: 0xFC18
      packet = <<0xFC, 0x18>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 16,
        data_type: "int"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == -1000
    end

    test "extracts 12-bit negative integer" do
      # -100 in 12-bit two's complement
      # -100 = 4096 - 100 = 3996 = 0xF9C
      # Packet: 0xF9C in 12 bits = 0b111110011100
      # Padded: 0b0000111110011100 = 0x0F9C
      packet = <<0x0F, 0x9C>>

      item_def = %{
        name: "test_value",
        bit_offset: 4,
        bit_length: 12,
        data_type: "int"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == -100
    end

    test "handles sign bit correctly at boundaries" do
      # Maximum positive value for 8-bit signed: 127 (0x7F)
      packet_pos = <<0x7F>>
      # Minimum negative value for 8-bit signed: -128 (0x80)
      packet_neg = <<0x80>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 8,
        data_type: "int"
      }

      {:ok, pos_value} = Decommutation.extract_field(packet_pos, item_def)
      {:ok, neg_value} = Decommutation.extract_field(packet_neg, item_def)

      assert pos_value == 127
      assert neg_value == -128
    end
  end

  describe "float extraction" do
    test "extracts 32-bit float" do
      # IEEE 754 single precision: 3.14159
      packet = <<3.14159::float-32>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 32,
        data_type: "float"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert_in_delta value, 3.14159, 0.00001
    end

    test "extracts 64-bit float" do
      # IEEE 754 double precision: 2.718281828
      packet = <<2.718281828::float-64>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 64,
        data_type: "float"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert_in_delta value, 2.718281828, 0.000000001
    end

    test "extracts negative float" do
      packet = <<-273.15::float-32>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 32,
        data_type: "float"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert_in_delta value, -273.15, 0.01
    end

    test "extracts float at non-zero offset" do
      # Packet: [uint16][float32]
      packet = <<0x00, 0x2A>> <> <<25.5::float-32>>

      item_def = %{
        name: "temperature",
        bit_offset: 16,
        bit_length: 32,
        data_type: "float"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert_in_delta value, 25.5, 0.001
    end

    test "returns error for unsupported float size" do
      packet = <<0x01, 0x02, 0x03>>

      item_def = %{
        name: "test_value",
        bit_offset: 0,
        bit_length: 16,
        data_type: "float"
      }

      {:error, {:unsupported_float_size, 16}} = Decommutation.extract_field(packet, item_def)
    end
  end

  describe "boolean extraction" do
    test "extracts true boolean" do
      packet = <<0x80>>
      # 0b10000000

      item_def = %{
        name: "test_flag",
        bit_offset: 0,
        bit_length: 1,
        data_type: "boolean"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == true
    end

    test "extracts false boolean" do
      packet = <<0x7F>>
      # 0b01111111

      item_def = %{
        name: "test_flag",
        bit_offset: 0,
        bit_length: 1,
        data_type: "boolean"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == false
    end

    test "extracts boolean at arbitrary bit position" do
      # Packet: 0b00010000 (bit 3 is set)
      packet = <<0x10>>

      item_def = %{
        name: "test_flag",
        bit_offset: 3,
        bit_length: 1,
        data_type: "boolean"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == true
    end

    test "extracts multiple boolean flags" do
      # Packet: 0b10101010
      packet = <<0xAA>>

      flags =
        for bit_offset <- 0..7 do
          item_def = %{
            name: "flag_#{bit_offset}",
            bit_offset: bit_offset,
            bit_length: 1,
            data_type: "boolean"
          }

          {:ok, value} = Decommutation.extract_field(packet, item_def)
          value
        end

      # Bits 0, 2, 4, 6 are set (alternating pattern)
      assert flags == [true, false, true, false, true, false, true, false]
    end
  end

  describe "string extraction" do
    test "extracts fixed-length string" do
      # 8 bytes: "CADENCE" + null terminator
      packet = <<"CADENCE", 0x00>>

      item_def = %{
        name: "mission_name",
        bit_offset: 0,
        bit_length: 64,
        data_type: "string"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == "CADENCE"
    end

    test "extracts string without null terminator" do
      packet = <<"TEST">>

      item_def = %{
        name: "test_string",
        bit_offset: 0,
        bit_length: 32,
        data_type: "string"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == "TEST"
    end

    test "extracts string at non-zero offset" do
      # Packet: [uint16][string:4bytes]
      packet = <<0x00, 0x2A, "OKAY">>

      item_def = %{
        name: "status",
        bit_offset: 16,
        bit_length: 32,
        data_type: "string"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      assert value == "OKAY"
    end

    test "handles string with embedded nulls" do
      # String extraction removes nulls, but when there are multiple consecutive nulls
      # in the middle, it still removes them all
      packet = <<"ABC", 0x00, 0x00>>

      item_def = %{
        name: "test_string",
        bit_offset: 0,
        bit_length: 40,
        data_type: "string"
      }

      {:ok, value} = Decommutation.extract_field(packet, item_def)
      # Null bytes should be removed
      assert value == "ABC"
    end
  end

  describe "JSON decommutation" do
    test "extracts items from JSON packet" do
      json_data = ~s({"cpu_temp": 25.5, "battery_voltage": 14.2, "uptime": 3600})

      packet_def = %{
        id: 1,
        name: "HEALTH",
        items: [
          %{name: "cpu_temp", bit_offset: 0, bit_length: 32, data_type: "float"},
          %{name: "battery_voltage", bit_offset: 32, bit_length: 32, data_type: "float"},
          %{name: "uptime", bit_offset: 64, bit_length: 32, data_type: "uint"}
        ]
      }

      {:ok, items} = Decommutation.decommutate(json_data, packet_def, :json)

      assert items["cpu_temp"] == 25.5
      assert items["battery_voltage"] == 14.2
      assert items["uptime"] == 3600
    end

    test "handles missing fields in JSON" do
      json_data = ~s({"cpu_temp": 25.5})

      packet_def = %{
        id: 1,
        name: "HEALTH",
        items: [
          %{name: "cpu_temp", bit_offset: 0, bit_length: 32, data_type: "float"},
          %{name: "battery_voltage", bit_offset: 32, bit_length: 32, data_type: "float"}
        ]
      }

      {:ok, items} = Decommutation.decommutate(json_data, packet_def, :json)

      assert items["cpu_temp"] == 25.5
      assert items["battery_voltage"] == nil
    end

    test "returns error for invalid JSON" do
      invalid_json = ~s({"cpu_temp": 25.5)

      packet_def = %{
        id: 1,
        name: "HEALTH",
        items: [%{name: "cpu_temp", bit_offset: 0, bit_length: 32, data_type: "float"}]
      }

      {:error, {:json_parse_error, _reason}} =
        Decommutation.decommutate(invalid_json, packet_def, :json)
    end
  end

  describe "binary decommutation (full packet)" do
    test "decommutates realistic CCSDS health packet" do
      # CCSDS health packet layout (after sync and headers):
      # [timestamp:48][target_hash:16][cpu_temp:float32][voltage:float32][current:float32][battery_pct:uint8][uptime:uint32][memory:uint16]

      timestamp = 1_700_000_000
      target_hash = 12345
      cpu_temp = 25.5
      voltage = 14.2
      current = 2.3
      battery_pct = 85
      uptime = 3600
      memory = 512

      packet =
        <<timestamp::48, target_hash::16>> <>
          <<cpu_temp::float-32, voltage::float-32, current::float-32, battery_pct::8,
            uptime::32, memory::16>>

      packet_def = %{
        id: 100,
        name: "HEALTH",
        items: [
          %{name: "timestamp", bit_offset: 0, bit_length: 48, data_type: "uint"},
          %{name: "target_hash", bit_offset: 48, bit_length: 16, data_type: "uint"},
          %{name: "cpu_temp", bit_offset: 64, bit_length: 32, data_type: "float"},
          %{name: "battery_voltage", bit_offset: 96, bit_length: 32, data_type: "float"},
          %{name: "battery_current", bit_offset: 128, bit_length: 32, data_type: "float"},
          %{name: "battery_percentage", bit_offset: 160, bit_length: 8, data_type: "uint"},
          %{name: "uptime_seconds", bit_offset: 168, bit_length: 32, data_type: "uint"},
          %{name: "memory_used_mb", bit_offset: 200, bit_length: 16, data_type: "uint"}
        ]
      }

      {:ok, items} = Decommutation.decommutate(packet, packet_def, :binary)

      assert items["timestamp"] == timestamp
      assert items["target_hash"] == target_hash
      assert_in_delta items["cpu_temp"], cpu_temp, 0.001
      assert_in_delta items["battery_voltage"], voltage, 0.001
      assert_in_delta items["battery_current"], current, 0.001
      assert items["battery_percentage"] == battery_pct
      assert items["uptime_seconds"] == uptime
      assert items["memory_used_mb"] == memory
    end

    test "handles packet with mixed data types" do
      # Packet: [status_flags:8][temperature:float32][count:uint16][name:32bits]
      status = 0xAA
      temp = -15.5
      count = 1024
      name = "TEST"

      packet = <<status::8>> <> <<temp::float-32>> <> <<count::16, name::binary>>

      packet_def = %{
        id: 1,
        name: "MIXED",
        items: [
          %{name: "status_flags", bit_offset: 0, bit_length: 8, data_type: "uint"},
          %{name: "temperature", bit_offset: 8, bit_length: 32, data_type: "float"},
          %{name: "count", bit_offset: 40, bit_length: 16, data_type: "uint"},
          %{name: "name", bit_offset: 56, bit_length: 32, data_type: "string"}
        ]
      }

      {:ok, items} = Decommutation.decommutate(packet, packet_def, :binary)

      assert items["status_flags"] == status
      assert_in_delta items["temperature"], temp, 0.001
      assert items["count"] == count
      assert items["name"] == name
    end
  end

  describe "packet definition validation" do
    test "validates complete packet definition" do
      valid_def = %{
        id: 1,
        name: "TEST",
        items: [
          %{name: "field1", bit_offset: 0, bit_length: 8, data_type: "uint"}
        ]
      }

      assert :ok = Decommutation.validate_packet_definition(valid_def)
    end

    test "rejects packet definition missing required fields" do
      invalid_def = %{
        name: "TEST",
        items: []
      }

      {:error, {:missing_fields, missing}} =
        Decommutation.validate_packet_definition(invalid_def)

      assert :id in missing
    end

    test "rejects item definition missing required fields" do
      invalid_def = %{
        id: 1,
        name: "TEST",
        items: [
          %{name: "field1", bit_length: 8, data_type: "uint"}
        ]
      }

      {:error, {:invalid_items, _errors}} =
        Decommutation.validate_packet_definition(invalid_def)
    end
  end
end
