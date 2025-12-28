defmodule Cadence.Telemetry.ProtocolsTest do
  @moduledoc """
  Comprehensive unit tests for all protocol implementations.

  Tests the four COSMOS-style protocol types:
  - LengthProtocol - Variable-length with embedded length field
  - TemplateProtocol - Sync pattern with header parsing (CCSDS)
  - TerminatedProtocol - Delimiter-based framing
  - FixedProtocol - Fixed-size packets
  """

  use ExUnit.Case, async: true

  import Bitwise

  alias Cadence.Telemetry.Protocols.{
    FixedProtocol,
    LengthProtocol,
    TemplateProtocol,
    TerminatedProtocol
  }

  @ccsds_sync <<0x1A, 0xCF, 0xFC, 0x1D>>

  describe "LengthProtocol" do
    test "extracts simple length-prefixed packet" do
      state = LengthProtocol.new(length_bit_size: 32, length_endian: :big)

      payload = "Hello, World!"
      length = byte_size(payload)
      packet = <<length::32, payload::binary>>

      assert {:ok, [^packet], _state} = LengthProtocol.read_data(packet, state)
    end

    test "extracts multiple packets from buffer" do
      state = LengthProtocol.new(length_bit_size: 16, length_endian: :big)

      payload1 = "First"
      payload2 = "Second"
      packet1 = <<byte_size(payload1)::16, payload1::binary>>
      packet2 = <<byte_size(payload2)::16, payload2::binary>>
      buffer = packet1 <> packet2

      assert {:ok, packets, _state} = LengthProtocol.read_data(buffer, state)
      assert length(packets) == 2
      assert Enum.at(packets, 0) == packet1
      assert Enum.at(packets, 1) == packet2
    end

    test "buffers incomplete packet" do
      state = LengthProtocol.new(length_bit_size: 32)

      payload = "Test data"
      length = byte_size(payload)
      packet = <<length::32, payload::binary>>

      # Send only first 5 bytes
      partial = binary_part(packet, 0, 5)

      assert {:stop, state1} = LengthProtocol.read_data(partial, state)
      assert byte_size(state1.buffer) == 5

      # Send remaining bytes
      remaining = binary_part(packet, 5, byte_size(packet) - 5)
      assert {:ok, [^packet], state2} = LengthProtocol.read_data(remaining, state1)
      assert state2.buffer == <<>>
    end

    test "handles little-endian length" do
      state = LengthProtocol.new(length_bit_size: 16, length_endian: :little)

      payload = "Test"
      length = byte_size(payload)
      packet = <<length::16-little, payload::binary>>

      assert {:ok, [^packet], _state} = LengthProtocol.read_data(packet, state)
    end

    test "handles length with sync pattern" do
      sync = <<0xAA, 0xBB>>
      state = LengthProtocol.new(sync_pattern: sync, length_bit_size: 16)

      payload = "Data"
      length = byte_size(payload)
      packet = sync <> <<length::16>> <> payload

      assert {:ok, [extracted], _state} = LengthProtocol.read_data(packet, state)
      # Sync pattern is skipped during extraction
      assert extracted == <<length::16>> <> payload
      assert extracted == <<0, 4, 68, 97, 116, 97>>
    end

    test "handles CCSDS-style length (length = actual - 1)" do
      state =
        LengthProtocol.new(
          length_bit_offset: 32,
          # After 4-byte header
          length_bit_size: 16,
          length_value_offset: 1,
          # CCSDS convention
          length_endian: :big
        )

      header = <<0x01, 0x02, 0x03, 0x04>>
      payload = "12345"
      # 5 bytes
      length_field = byte_size(payload) - 1
      # Store 4 (actual - 1)
      packet = header <> <<length_field::16>> <> payload

      assert {:ok, [^packet], _state} = LengthProtocol.read_data(packet, state)
    end

    test "handles length multiplier (words instead of bytes)" do
      # Length field in 4-byte words
      state =
        LengthProtocol.new(
          length_bit_size: 16,
          length_bytes_per_count: 4
        )

      payload = "1234567890123456"
      # 16 bytes = 4 words
      length_in_words = div(byte_size(payload), 4)
      packet = <<length_in_words::16, payload::binary>>

      assert {:ok, [^packet], _state} = LengthProtocol.read_data(packet, state)
    end

    test "discards leading bytes" do
      state =
        LengthProtocol.new(
          length_bit_size: 32,
          discard_leading_bytes: 4
        )

      payload = "Data"
      packet = <<byte_size(payload)::32, payload::binary>>

      assert {:ok, [extracted], _state} = LengthProtocol.read_data(packet, state)
      # Should have discarded the 4-byte length header
      assert extracted == payload
    end

    test "write_data encodes outgoing packet" do
      state = LengthProtocol.new(length_bit_size: 16, length_endian: :big)

      payload = "Outgoing"
      assert {:ok, [packet], _state} = LengthProtocol.write_data(payload, state)

      # Should have length prefix
      <<length::16, data::binary>> = packet
      assert length == byte_size(payload)
      assert data == payload
    end

    test "write_data with sync pattern" do
      sync = <<0xFF, 0xFE>>
      state = LengthProtocol.new(sync_pattern: sync, length_bit_size: 32)

      payload = "Test"
      assert {:ok, [packet], _state} = LengthProtocol.write_data(payload, state)

      # Should start with sync
      <<^sync::binary-size(2), length::32, data::binary>> = packet
      assert length == byte_size(payload)
      assert data == payload
    end
  end

  describe "TemplateProtocol" do
    test "extracts packet with CCSDS sync pattern" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6,
          length_offset: 4,
          length_bit_size: 16,
          length_value_offset: 1
        )

      # CCSDS packet: sync + 6-byte header + payload
      header = <<0x08, 0x64, 0xC0, 0x00, 0x00, 0x05>>
      # length=5 means 6 bytes payload
      payload = "123456"
      packet = @ccsds_sync <> header <> payload

      assert {:ok, [^packet], _state} = TemplateProtocol.read_data(packet, state)
    end

    test "extracts multiple CCSDS packets" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6,
          length_offset: 4,
          length_bit_size: 16,
          length_value_offset: 1
        )

      # Build two packets
      header1 = <<0x08, 0x64, 0xC0, 0x00, 0x00, 0x02>>
      # length=2 means 3 bytes
      payload1 = "ABC"
      packet1 = @ccsds_sync <> header1 <> payload1

      header2 = <<0x08, 0x65, 0xC0, 0x01, 0x00, 0x03>>
      # length=3 means 4 bytes
      payload2 = "DEFG"
      packet2 = @ccsds_sync <> header2 <> payload2

      buffer = packet1 <> packet2

      assert {:ok, packets, _state} = TemplateProtocol.read_data(buffer, state)
      assert length(packets) == 2
      assert Enum.at(packets, 0) == packet1
      assert Enum.at(packets, 1) == packet2
    end

    test "buffers incomplete packet" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6,
          length_offset: 4,
          length_bit_size: 16,
          length_value_offset: 1
        )

      header = <<0x08, 0x64, 0xC0, 0x00, 0x00, 0x09>>
      # length=9 means 10 bytes payload
      payload = "1234567890"
      complete_packet = @ccsds_sync <> header <> payload

      # Send only first 10 bytes (sync + partial header)
      partial = binary_part(complete_packet, 0, 10)

      assert {:stop, state1} = TemplateProtocol.read_data(partial, state)
      assert byte_size(state1.buffer) == 10

      # Send rest
      remaining = binary_part(complete_packet, 10, byte_size(complete_packet) - 10)
      assert {:ok, [^complete_packet], _state} = TemplateProtocol.read_data(remaining, state1)
    end

    test "searches for sync pattern in noisy data" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6,
          length_offset: 4,
          length_bit_size: 16,
          length_value_offset: 1
        )

      # Garbage data before sync
      garbage = :crypto.strong_rand_bytes(20)

      header = <<0x08, 0x64, 0xC0, 0x00, 0x00, 0x02>>
      payload = "ABC"
      packet = @ccsds_sync <> header <> payload

      buffer = garbage <> packet

      assert {:ok, [^packet], _state} = TemplateProtocol.read_data(buffer, state)
    end

    test "handles fragmented sync pattern across reads" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6,
          length_offset: 4,
          length_bit_size: 16,
          length_value_offset: 1
        )

      # Build complete packet with 1 byte payload (length field = 0 means actual size 1)
      header = <<0x01, 0x02, 0x03, 0x04, 0x00, 0x00>>
      payload = "X"
      packet = @ccsds_sync <> header <> payload

      # Split sync pattern across reads
      chunk1 = binary_part(@ccsds_sync, 0, 2)
      # First 2 bytes of sync

      assert {:stop, state1} = TemplateProtocol.read_data(chunk1, state)

      # Send rest
      chunk2 = binary_part(packet, 2, byte_size(packet) - 2)
      assert {:ok, [^packet], _state} = TemplateProtocol.read_data(chunk2, state1)
    end

    test "discards leading bytes from extracted packet" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6,
          length_offset: 4,
          length_bit_size: 16,
          length_value_offset: 1,
          discard_leading_bytes: 10
        )

      # Discard sync + header
      header = <<0x08, 0x64, 0xC0, 0x00, 0x00, 0x02>>
      payload = "ABC"
      packet = @ccsds_sync <> header <> payload

      assert {:ok, [extracted], _state} = TemplateProtocol.read_data(packet, state)
      # Should only have payload
      assert extracted == payload
    end

    test "write_data builds packet with sync and header" do
      state =
        TemplateProtocol.new(
          sync_pattern: @ccsds_sync,
          header_length: 6,
          length_offset: 4,
          length_bit_size: 16,
          length_value_offset: 1
        )

      payload = "Test"
      assert {:ok, [packet], _state} = TemplateProtocol.write_data(payload, state)

      # Should start with sync
      <<sync::binary-size(4), header::binary-size(6), data::binary>> = packet
      assert sync == @ccsds_sync
      assert data == payload

      # Check length field in header
      <<_before::binary-size(4), length::16, _after::binary>> = header
      assert length == byte_size(payload) - 1
    end
  end

  describe "TerminatedProtocol" do
    test "extracts newline-terminated packet" do
      state = TerminatedProtocol.new(terminator: "\n")

      packet = "Hello, World!\n"

      assert {:ok, [extracted], _state} = TerminatedProtocol.read_data(packet, state)
      # Default strips terminator
      assert extracted == "Hello, World!"
    end

    test "extracts CRLF-terminated packet" do
      state = TerminatedProtocol.new(terminator: "\r\n")

      packet = "Line 1\r\n"

      assert {:ok, [extracted], _state} = TerminatedProtocol.read_data(packet, state)
      assert extracted == "Line 1"
    end

    test "extracts multiple terminated packets" do
      state = TerminatedProtocol.new(terminator: "\n")

      buffer = "First\nSecond\nThird\n"

      assert {:ok, packets, _state} = TerminatedProtocol.read_data(buffer, state)
      assert length(packets) == 3
      assert Enum.at(packets, 0) == "First"
      assert Enum.at(packets, 1) == "Second"
      assert Enum.at(packets, 2) == "Third"
    end

    test "buffers incomplete packet" do
      state = TerminatedProtocol.new(terminator: "\n")

      partial = "Incomplete data"

      assert {:stop, state1} = TerminatedProtocol.read_data(partial, state)
      assert state1.buffer == partial

      # Complete the packet
      assert {:ok, ["Incomplete data"], _state} =
               TerminatedProtocol.read_data("\n", state1)
    end

    test "keeps terminator when strip_terminator is false" do
      state = TerminatedProtocol.new(terminator: "\n", strip_terminator: false)

      packet = "Keep newline\n"

      assert {:ok, [^packet], _state} = TerminatedProtocol.read_data(packet, state)
    end

    test "handles custom binary terminator" do
      term = <<0xFF, 0xFF>>
      state = TerminatedProtocol.new(terminator: term)

      data = "Binary data"
      packet = data <> term

      assert {:ok, [^data], _state} = TerminatedProtocol.read_data(packet, state)
    end

    test "handles sync pattern with terminator" do
      sync = <<0xAA>>

      state =
        TerminatedProtocol.new(
          sync_pattern: sync,
          terminator: "\n",
          fill_sync_pattern: true
        )

      packet = sync <> "Data\n"

      assert {:ok, [extracted], _state} = TerminatedProtocol.read_data(packet, state)
      # Should include sync (strip_terminator defaults to true)
      assert extracted == <<0xAA>> <> "Data"
      assert extracted == <<170, 68, 97, 116, 97>>
    end

    test "write_data appends terminator" do
      state = TerminatedProtocol.new(terminator: "\r\n")

      data = "Outgoing"
      assert {:ok, [packet], _state} = TerminatedProtocol.write_data(data, state)
      assert packet == "Outgoing\r\n"
    end

    test "write_data with sync pattern" do
      sync = <<0xBB>>
      state = TerminatedProtocol.new(sync_pattern: sync, terminator: "\n")

      data = "Test"
      assert {:ok, [packet], _state} = TerminatedProtocol.write_data(data, state)
      assert packet == sync <> "Test\n"
    end
  end

  describe "FixedProtocol" do
    test "extracts fixed-size packet" do
      state = FixedProtocol.new(packet_size: 10)

      packet = "1234567890"

      assert {:ok, [^packet], _state} = FixedProtocol.read_data(packet, state)
    end

    test "extracts multiple fixed-size packets" do
      state = FixedProtocol.new(packet_size: 4)

      buffer = "AAAABBBBCCCCDDDD"

      assert {:ok, packets, _state} = FixedProtocol.read_data(buffer, state)
      assert length(packets) == 4
      assert Enum.at(packets, 0) == "AAAA"
      assert Enum.at(packets, 1) == "BBBB"
      assert Enum.at(packets, 2) == "CCCC"
      assert Enum.at(packets, 3) == "DDDD"
    end

    test "buffers incomplete packet" do
      state = FixedProtocol.new(packet_size: 8)

      partial = "12345"

      assert {:stop, state1} = FixedProtocol.read_data(partial, state)
      assert state1.buffer == partial

      # Complete the packet
      assert {:ok, ["12345678"], _state} = FixedProtocol.read_data("678", state1)
    end

    test "extracts packets with remaining partial" do
      state = FixedProtocol.new(packet_size: 5)

      buffer = "AAAAABBBBBCC"

      assert {:ok, packets, state1} = FixedProtocol.read_data(buffer, state)
      assert length(packets) == 2
      assert Enum.at(packets, 0) == "AAAAA"
      assert Enum.at(packets, 1) == "BBBBB"
      assert state1.buffer == "CC"
    end

    test "handles sync pattern with fixed size" do
      sync = <<0xAA, 0xBB>>
      # When fill_sync_pattern is true, packet_size is data size after sync
      # Total bytes needed = sync_size + packet_size
      state = FixedProtocol.new(sync_pattern: sync, packet_size: 8, fill_sync_pattern: true)

      # Total bytes: sync (2 bytes) + data (8 bytes) = 10 bytes
      data = "12345678"
      packet = sync <> data

      # The protocol finds sync, then extracts sync + packet_size bytes total
      assert {:ok, [extracted], _state} = FixedProtocol.read_data(packet, state)
      assert extracted == sync <> data
      assert extracted == <<170, 187, 49, 50, 51, 52, 53, 54, 55, 56>>
    end

    test "discards leading bytes from fixed packet" do
      state = FixedProtocol.new(packet_size: 10, discard_leading_bytes: 4)

      packet = "0123456789"

      assert {:ok, [extracted], _state} = FixedProtocol.read_data(packet, state)
      # Should discard first 4 bytes
      assert extracted == "456789"
    end

    test "write_data validates packet size" do
      state = FixedProtocol.new(packet_size: 8)

      # Correct size
      assert {:ok, [packet], _state} = FixedProtocol.write_data("12345678", state)
      assert packet == "12345678"

      # Wrong size
      assert {:disconnect, _reason} = FixedProtocol.write_data("123", state)
    end

    test "write_data with sync pattern" do
      sync = <<0xFF>>
      state = FixedProtocol.new(sync_pattern: sync, packet_size: 5)

      data = "12345"
      assert {:ok, [packet], _state} = FixedProtocol.write_data(data, state)
      assert packet == sync <> "12345"
    end
  end

  describe "Protocol lifecycle methods" do
    test "LengthProtocol connect_reset clears buffer" do
      state = LengthProtocol.new(length_bit_size: 32)
      state = %{state | buffer: "garbage"}

      new_state = LengthProtocol.connect_reset(state)
      assert new_state.buffer == <<>>
    end

    test "TemplateProtocol disconnect_reset clears buffer" do
      state = TemplateProtocol.new(sync_pattern: @ccsds_sync, header_length: 6)
      state = %{state | buffer: "garbage"}

      new_state = TemplateProtocol.disconnect_reset(state)
      assert new_state.buffer == <<>>
    end

    test "TerminatedProtocol reset is a no-op" do
      state = TerminatedProtocol.new(terminator: "\n")

      new_state = TerminatedProtocol.reset(state, [], nil)
      assert new_state == state
    end
  end
end
