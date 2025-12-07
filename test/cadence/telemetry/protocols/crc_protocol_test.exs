defmodule Cadence.Telemetry.Protocols.CRCProtocolTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.Protocols.CRCProtocol
  alias Cadence.Telemetry.CRC

  describe "new/1" do
    test "creates protocol with default options" do
      state = CRCProtocol.new([])

      assert state.algorithm == :crc16_ccitt
      assert state.endian == :big
      assert state.on_failure == :skip
      assert state.crc_size == 2
    end

    test "accepts algorithm option" do
      state = CRCProtocol.new(algorithm: :crc32)
      assert state.algorithm == :crc32
      assert state.crc_size == 4
    end

    test "accepts string algorithm" do
      state = CRCProtocol.new(algorithm: "crc32")
      assert state.algorithm == :crc32
    end

    test "accepts endian option" do
      state = CRCProtocol.new(endian: :little)
      assert state.endian == :little
    end

    test "accepts on_failure option" do
      state = CRCProtocol.new(on_failure: :disconnect)
      assert state.on_failure == :disconnect
    end

    test "raises for unsupported algorithm atom" do
      assert_raise ArgumentError, ~r/Unsupported CRC algorithm/, fn ->
        CRCProtocol.new(algorithm: :unsupported)
      end
    end

    test "raises for unsupported algorithm string" do
      assert_raise ArgumentError, ~r/Unknown CRC algorithm/, fn ->
        CRCProtocol.new(algorithm: "invalid_algorithm")
      end
    end
  end

  describe "read_data/2 - valid CRC" do
    test "validates and strips CRC-16 trailer" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt)
      data = "test data"
      crc = CRC.calculate(:crc16_ccitt, data)
      packet = data <> CRC.encode(crc, :crc16_ccitt, :big)

      assert {:ok, [^data], new_state} = CRCProtocol.read_data(packet, state)
      assert new_state.packets_validated == 1
      assert new_state.packets_failed == 0
    end

    test "validates and strips CRC-32 trailer" do
      state = CRCProtocol.new(algorithm: :crc32)
      data = "test data"
      crc = CRC.calculate(:crc32, data)
      packet = data <> CRC.encode(crc, :crc32, :big)

      assert {:ok, [^data], new_state} = CRCProtocol.read_data(packet, state)
      assert new_state.packets_validated == 1
    end

    test "respects little endian setting" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt, endian: :little)
      data = "test data"
      crc = CRC.calculate(:crc16_ccitt, data)
      packet = data <> CRC.encode(crc, :crc16_ccitt, :little)

      assert {:ok, [^data], _state} = CRCProtocol.read_data(packet, state)
    end
  end

  describe "read_data/2 - invalid CRC with :skip" do
    test "skips packet and returns empty list" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt, on_failure: :skip)
      data = "test data"
      bad_crc = <<0x00, 0x00>>
      packet = data <> bad_crc

      assert {:ok, [], new_state} = CRCProtocol.read_data(packet, state)
      assert new_state.packets_failed == 1
      assert new_state.packets_validated == 0
    end
  end

  describe "read_data/2 - invalid CRC with :disconnect" do
    test "returns disconnect tuple" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt, on_failure: :disconnect)
      data = "test data"
      bad_crc = <<0x00, 0x00>>
      packet = data <> bad_crc

      assert {:disconnect, reason} = CRCProtocol.read_data(packet, state)
      assert reason =~ "CRC mismatch"
    end
  end

  describe "read_data/2 - invalid CRC with :pass" do
    test "returns packet anyway with warning" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt, on_failure: :pass)
      data = "test data"
      bad_crc = <<0x00, 0x00>>
      packet = data <> bad_crc

      assert {:ok, [^data], new_state} = CRCProtocol.read_data(packet, state)
      assert new_state.packets_failed == 1
    end
  end

  describe "read_data/2 - edge cases" do
    test "handles packet too small for CRC" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt)
      # Only 1 byte, but CRC-16 needs 2 bytes
      assert {:ok, [], _state} = CRCProtocol.read_data(<<0x01>>, state)
    end

    test "handles empty packet" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt)
      assert {:ok, [], _state} = CRCProtocol.read_data(<<>>, state)
    end
  end

  describe "write_data/2" do
    test "appends CRC-16 trailer" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt)
      data = "test data"

      assert {:ok, [result], _state} = CRCProtocol.write_data(data, state)
      assert byte_size(result) == byte_size(data) + 2

      # Verify the CRC is correct by reading it back
      assert {:ok, [^data], _state} = CRCProtocol.read_data(result, state)
    end

    test "appends CRC-32 trailer" do
      state = CRCProtocol.new(algorithm: :crc32)
      data = "test data"

      assert {:ok, [result], _state} = CRCProtocol.write_data(data, state)
      assert byte_size(result) == byte_size(data) + 4
    end

    test "respects endian setting" do
      state_big = CRCProtocol.new(algorithm: :crc16_ccitt, endian: :big)
      state_little = CRCProtocol.new(algorithm: :crc16_ccitt, endian: :little)
      data = "test"

      {:ok, [result_big], _} = CRCProtocol.write_data(data, state_big)
      {:ok, [result_little], _} = CRCProtocol.write_data(data, state_little)

      # CRC bytes should be in different order
      <<_data::binary-size(4), crc_big::binary-size(2)>> = result_big
      <<_data::binary-size(4), crc_little::binary-size(2)>> = result_little

      # Reverse of each other
      assert crc_big == :binary.bin_to_list(crc_little) |> Enum.reverse() |> :binary.list_to_bin()
    end
  end

  describe "packet_format/0" do
    test "returns :raw" do
      assert CRCProtocol.packet_format() == :raw
    end
  end

  describe "roundtrip" do
    test "write then read produces original data" do
      state = CRCProtocol.new(algorithm: :crc16_ccitt)
      original = "Hello, CCSDS!"

      {:ok, [with_crc], state} = CRCProtocol.write_data(original, state)
      {:ok, [recovered], _state} = CRCProtocol.read_data(with_crc, state)

      assert recovered == original
    end

    test "works with all algorithms" do
      for algorithm <- [:crc32, :crc16_ccitt, :crc16_xmodem, :crc8, :xor_checksum] do
        state = CRCProtocol.new(algorithm: algorithm)
        original = "Test data for #{algorithm}"

        {:ok, [with_crc], state} = CRCProtocol.write_data(original, state)
        {:ok, [recovered], _state} = CRCProtocol.read_data(with_crc, state)

        assert recovered == original, "Failed for algorithm #{algorithm}"
      end
    end
  end
end
