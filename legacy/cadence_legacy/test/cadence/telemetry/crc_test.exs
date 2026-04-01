defmodule Cadence.Telemetry.CRCTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.CRC

  describe "calculate/2" do
    test "CRC-32 produces correct result for standard test vector" do
      # Standard CRC-32 test vector: "123456789" -> 0xCBF43926
      assert CRC.calculate(:crc32, "123456789") == 0xCBF43926
    end

    test "CRC-32 empty string" do
      assert CRC.calculate(:crc32, "") == 0
    end

    test "CRC-16-CCITT produces correct result for standard test vector" do
      # CRC-16-CCITT (init 0xFFFF): "123456789" -> 0x29B1
      assert CRC.calculate(:crc16_ccitt, "123456789") == 0x29B1
    end

    test "CRC-16-CCITT empty string" do
      # Init value with no data
      assert CRC.calculate(:crc16_ccitt, "") == 0xFFFF
    end

    test "CRC-16-XMODEM produces correct result" do
      # CRC-16-XMODEM (init 0x0000): "123456789" -> 0x31C3
      assert CRC.calculate(:crc16_xmodem, "123456789") == 0x31C3
    end

    test "CRC-8 produces correct result" do
      # CRC-8 (polynomial 0x07): "123456789" -> 0xF4
      assert CRC.calculate(:crc8, "123456789") == 0xF4
    end

    test "XOR checksum" do
      # 0x01 XOR 0x02 XOR 0x03 = 0x00
      assert CRC.calculate(:xor_checksum, <<0x01, 0x02, 0x03>>) == 0x00

      # 0x01 XOR 0x02 XOR 0x04 = 0x07
      assert CRC.calculate(:xor_checksum, <<0x01, 0x02, 0x04>>) == 0x07
    end

    test "raises for unknown algorithm" do
      assert_raise ArgumentError, ~r/Unknown CRC algorithm/, fn ->
        CRC.calculate(:unknown, "test")
      end
    end
  end

  describe "size/1" do
    test "returns correct sizes for each algorithm" do
      assert CRC.size(:crc32) == 4
      assert CRC.size(:crc16_ccitt) == 2
      assert CRC.size(:crc16_xmodem) == 2
      assert CRC.size(:crc8) == 1
      assert CRC.size(:xor_checksum) == 1
    end
  end

  describe "encode/3 and decode/3" do
    test "CRC-32 big endian roundtrip" do
      crc = 0xCBF43926
      encoded = CRC.encode(crc, :crc32, :big)
      assert byte_size(encoded) == 4
      assert CRC.decode(encoded, :crc32, :big) == crc
    end

    test "CRC-32 little endian roundtrip" do
      crc = 0xCBF43926
      encoded = CRC.encode(crc, :crc32, :little)
      assert byte_size(encoded) == 4
      assert CRC.decode(encoded, :crc32, :little) == crc
    end

    test "CRC-16 big endian roundtrip" do
      crc = 0x29B1
      encoded = CRC.encode(crc, :crc16_ccitt, :big)
      assert byte_size(encoded) == 2
      assert encoded == <<0x29, 0xB1>>
      assert CRC.decode(encoded, :crc16_ccitt, :big) == crc
    end

    test "CRC-16 little endian roundtrip" do
      crc = 0x29B1
      encoded = CRC.encode(crc, :crc16_ccitt, :little)
      assert byte_size(encoded) == 2
      assert encoded == <<0xB1, 0x29>>
      assert CRC.decode(encoded, :crc16_ccitt, :little) == crc
    end

    test "CRC-8 roundtrip" do
      crc = 0xF4
      encoded = CRC.encode(crc, :crc8, :big)
      assert byte_size(encoded) == 1
      assert CRC.decode(encoded, :crc8, :big) == crc
    end
  end

  describe "verify/3" do
    test "returns ok with valid CRC" do
      data = "123456789"
      crc = CRC.calculate(:crc16_ccitt, data)
      data_with_crc = data <> CRC.encode(crc, :crc16_ccitt, :big)

      assert {:ok, ^data} = CRC.verify(data_with_crc, :crc16_ccitt, :big)
    end

    test "returns error with invalid CRC" do
      data = "123456789"
      bad_crc = <<0x00, 0x00>>
      data_with_bad_crc = data <> bad_crc

      assert {:error, {:crc_mismatch, 0x0000, 0x29B1}} =
               CRC.verify(data_with_bad_crc, :crc16_ccitt, :big)
    end

    test "returns error with insufficient data" do
      assert {:error, :insufficient_data} = CRC.verify(<<0x01>>, :crc16_ccitt, :big)
    end

    test "works with CRC-32" do
      data = "hello"
      crc = CRC.calculate(:crc32, data)
      data_with_crc = data <> CRC.encode(crc, :crc32, :big)

      assert {:ok, ^data} = CRC.verify(data_with_crc, :crc32, :big)
    end

    test "works with little endian" do
      data = "test"
      crc = CRC.calculate(:crc16_ccitt, data)
      data_with_crc = data <> CRC.encode(crc, :crc16_ccitt, :little)

      assert {:ok, ^data} = CRC.verify(data_with_crc, :crc16_ccitt, :little)
    end
  end
end
