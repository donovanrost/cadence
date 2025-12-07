defmodule Cadence.Telemetry.ProtocolChain.ProcessorTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.ProtocolChain.Processor

  describe "atomize_protocol_config/1" do
    test "converts valid CRC algorithm strings" do
      config = %{"algorithm" => "crc32"}
      result = Processor.atomize_protocol_config(config)

      assert {:algorithm, :crc32} in result
    end

    test "converts valid CRC algorithm with hyphen" do
      config = %{"algorithm" => "crc16-ccitt"}
      result = Processor.atomize_protocol_config(config)

      assert {:algorithm, :crc16_ccitt} in result
    end

    test "raises for unknown CRC algorithm" do
      config = %{"algorithm" => "invalid_algorithm"}

      assert_raise ArgumentError, ~r/Unknown CRC algorithm/, fn ->
        Processor.atomize_protocol_config(config)
      end
    end

    test "raises for unknown crc_algorithm" do
      config = %{"crc_algorithm" => "bad_algo"}

      assert_raise ArgumentError, ~r/Unknown CRC algorithm/, fn ->
        Processor.atomize_protocol_config(config)
      end
    end

    test "converts valid endian strings" do
      config = %{"endian" => "big", "length_endian" => "little"}
      result = Processor.atomize_protocol_config(config)

      assert {:endian, :big} in result
      assert {:length_endian, :little} in result
    end

    test "converts valid on_failure strings" do
      config = %{"on_failure" => "skip"}
      result = Processor.atomize_protocol_config(config)

      assert {:on_failure, :skip} in result
    end

    test "preserves unknown config keys as strings" do
      config = %{"custom_key" => "custom_value", "another_unknown" => 123}
      result = Processor.atomize_protocol_config(config)

      # Unknown keys should remain as strings
      assert {"custom_key", "custom_value"} in result
      assert {"another_unknown", 123} in result
    end

    test "converts known protocol config keys to atoms" do
      config = %{"sync_pattern" => "value", "frame_size" => 100}
      result = Processor.atomize_protocol_config(config)

      assert {:sync_pattern, "value"} in result
      assert {:frame_size, 100} in result
    end

    test "handles hex string conversion" do
      config = %{"sync_pattern_hex" => "DEADBEEF"}
      result = Processor.atomize_protocol_config(config)

      assert {:sync_pattern, <<0xDE, 0xAD, 0xBE, 0xEF>>} in result
    end

    test "handles boolean crc_enabled" do
      config = %{"crc_enabled" => true}
      result = Processor.atomize_protocol_config(config)

      assert {:crc_enabled, true} in result
    end

    test "handles string boolean crc_enabled" do
      config = %{"crc_enabled" => "true"}
      result = Processor.atomize_protocol_config(config)

      assert {:crc_enabled, true} in result
    end

    test "returns empty list for non-map input" do
      assert Processor.atomize_protocol_config("not a map") == []
      assert Processor.atomize_protocol_config(nil) == []
    end
  end

  describe "protocol_module_for_type/1" do
    test "returns correct module for known types" do
      assert Processor.protocol_module_for_type("ccsds") == Cadence.Telemetry.Protocols.CCSDSProtocol
      assert Processor.protocol_module_for_type("crc") == Cadence.Telemetry.Protocols.CRCProtocol
      assert Processor.protocol_module_for_type("length") == Cadence.Telemetry.Protocols.LengthProtocol
      assert Processor.protocol_module_for_type("terminated") == Cadence.Telemetry.Protocols.TerminatedProtocol
      assert Processor.protocol_module_for_type("fixed") == Cadence.Telemetry.Protocols.FixedProtocol
    end

    test "returns nil for unknown type" do
      assert Processor.protocol_module_for_type("unknown") == nil
      assert Processor.protocol_module_for_type("") == nil
    end
  end

  describe "hex_to_binary/1" do
    test "converts valid hex strings" do
      assert Processor.hex_to_binary("DEADBEEF") == <<0xDE, 0xAD, 0xBE, 0xEF>>
      assert Processor.hex_to_binary("00FF") == <<0x00, 0xFF>>
      assert Processor.hex_to_binary("deadbeef") == <<0xDE, 0xAD, 0xBE, 0xEF>>
    end

    test "returns nil for invalid hex" do
      assert Processor.hex_to_binary("GHIJ") == nil
      assert Processor.hex_to_binary("123") == nil
    end

    test "returns nil for non-string input" do
      assert Processor.hex_to_binary(nil) == nil
      assert Processor.hex_to_binary(123) == nil
    end
  end
end
