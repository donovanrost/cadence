defmodule Cadence.Telemetry.Protocols.CCSDSProtocolTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Cadence.Telemetry.Protocols.CCSDSProtocol
  alias Cadence.Telemetry.CRC

  @default_sync <<0x1A, 0xCF, 0xFC, 0x1D>>
  @header_size 6

  # Helper to build a valid CCSDS primary header
  defp build_header(apid, seq_count, data_length) do
    # Version: 0, Type: 0, Sec Hdr Flag: 1, APID: apid
    packet_id = 0 <<< 13 ||| 0 <<< 12 ||| 1 <<< 11 ||| apid
    # Seq Flags: 3 (standalone), Seq Count: seq_count
    seq_control = 3 <<< 14 ||| seq_count
    <<packet_id::16, seq_control::16, data_length::16>>
  end

  # Helper to build a complete CCSDS packet
  defp build_packet(apid, seq_count, payload, opts \\ []) do
    sync = Keyword.get(opts, :sync, @default_sync)
    include_sync = Keyword.get(opts, :include_sync, true)

    # CCSDS data_length = payload_size - 1
    data_length = byte_size(payload) - 1
    header = build_header(apid, seq_count, data_length)
    packet_body = header <> payload

    if include_sync do
      sync <> packet_body
    else
      packet_body
    end
  end

  # Helper to build packet with CRC
  # Note: For CCSDS with CRC, the data_length field in the header includes the CRC bytes
  # data_length = (payload_bytes + crc_bytes) - 1
  defp build_packet_with_crc(apid, seq_count, payload, algorithm, opts \\ []) do
    sync = Keyword.get(opts, :sync, @default_sync)
    endian = Keyword.get(opts, :endian, :big)
    include_sync = Keyword.get(opts, :include_sync, true)

    crc_size = CRC.size(algorithm)
    # data_length = (payload + crc) - 1
    # This matches how CCSDSProtocol writes packets
    data_length = byte_size(payload) + crc_size - 1
    header = build_header(apid, seq_count, data_length)

    # CRC covers header + payload, NOT sync
    packet_body = header <> payload
    crc = CRC.calculate(algorithm, packet_body)
    crc_bytes = CRC.encode(crc, algorithm, endian)

    packet_with_crc = packet_body <> crc_bytes

    if include_sync do
      sync <> packet_with_crc
    else
      packet_with_crc
    end
  end

  describe "new/1" do
    test "creates protocol with default options" do
      state = CCSDSProtocol.new([])

      assert state.sync_pattern == @default_sync
      assert state.include_sync == true
      assert state.discard_sync == true
      assert state.crc_enabled == false
      assert state.crc_algorithm == :crc16_ccitt
      assert state.crc_endian == :big
      assert state.crc_on_failure == :skip
      assert state.default_apid == 0
      assert state.buffer == <<>>
      assert state.sequence_count == 0
    end

    test "accepts custom sync pattern" do
      custom_sync = <<0xAA, 0xBB, 0xCC, 0xDD>>
      state = CCSDSProtocol.new(sync_pattern: custom_sync)
      assert state.sync_pattern == custom_sync
    end

    test "accepts CRC options" do
      state = CCSDSProtocol.new(
        crc_enabled: true,
        crc_algorithm: :crc32,
        crc_endian: :little,
        crc_on_failure: :disconnect
      )

      assert state.crc_enabled == true
      assert state.crc_algorithm == :crc32
      assert state.crc_endian == :little
      assert state.crc_on_failure == :disconnect
      assert state.crc_size == 4
    end

    test "normalizes string algorithm to atom" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: "crc32")
      assert state.crc_algorithm == :crc32
    end

    test "normalizes string endian to atom" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_endian: "little")
      assert state.crc_endian == :little
    end

    test "normalizes string on_failure to atom" do
      state = CCSDSProtocol.new(crc_on_failure: "disconnect")
      assert state.crc_on_failure == :disconnect
    end

    test "accepts default_apid option" do
      state = CCSDSProtocol.new(default_apid: 42)
      assert state.default_apid == 42
    end

    test "accepts include_sync and discard_sync options" do
      state = CCSDSProtocol.new(include_sync: false, discard_sync: false)
      assert state.include_sync == false
      assert state.discard_sync == false
    end
  end

  describe "read_data/2 - basic packet extraction" do
    test "extracts single packet without CRC" do
      state = CCSDSProtocol.new([])
      payload = "Hello, CCSDS!"
      packet = build_packet(100, 1, payload)

      assert {:ok, [extracted], new_state} = CCSDSProtocol.read_data(packet, state)
      assert new_state.packets_extracted == 1

      # With discard_sync: true (default), sync should be stripped
      # Packet should be: header (6 bytes) + payload
      assert byte_size(extracted) == @header_size + byte_size(payload)
    end

    test "extracts packet keeping sync when discard_sync is false" do
      state = CCSDSProtocol.new(discard_sync: false)
      payload = "Hello, CCSDS!"
      packet = build_packet(100, 1, payload)

      assert {:ok, [extracted], _state} = CCSDSProtocol.read_data(packet, state)

      # Should include sync
      assert byte_size(extracted) == byte_size(@default_sync) + @header_size + byte_size(payload)
      assert :binary.match(extracted, @default_sync) == {0, 4}
    end

    test "extracts multiple packets from single buffer" do
      state = CCSDSProtocol.new([])

      packet1 = build_packet(100, 1, "First packet")
      packet2 = build_packet(200, 2, "Second packet")
      combined = packet1 <> packet2

      assert {:ok, packets, new_state} = CCSDSProtocol.read_data(combined, state)
      assert length(packets) == 2
      assert new_state.packets_extracted == 2
    end

    test "buffers partial packet and extracts on next read" do
      state = CCSDSProtocol.new([])
      payload = "Complete payload data"
      packet = build_packet(100, 1, payload)

      # Split packet in middle
      split_point = div(byte_size(packet), 2)
      <<first_half::binary-size(split_point), second_half::binary>> = packet

      # First read - should buffer
      assert {:ok, [], state} = CCSDSProtocol.read_data(first_half, state)
      assert state.buffer == first_half

      # Second read - should extract
      assert {:ok, [_extracted], state} = CCSDSProtocol.read_data(second_half, state)
      assert state.packets_extracted == 1
    end

    test "skips garbage data before sync pattern" do
      state = CCSDSProtocol.new([])
      payload = "Valid payload"
      packet = build_packet(100, 1, payload)

      # Add garbage before the packet
      garbage = <<0xFF, 0xFE, 0xFD, 0xFC, 0xFB>>
      data = garbage <> packet

      assert {:ok, [_extracted], state} = CCSDSProtocol.read_data(data, state)
      assert state.packets_extracted == 1
    end

    test "handles empty buffer" do
      state = CCSDSProtocol.new([])
      assert {:ok, [], _state} = CCSDSProtocol.read_data(<<>>, state)
    end
  end

  describe "read_data/2 - CRC validation" do
    test "validates CRC-16 successfully" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc16_ccitt)
      payload = "Test payload"
      packet = build_packet_with_crc(100, 1, payload, :crc16_ccitt)

      assert {:ok, [extracted], new_state} = CCSDSProtocol.read_data(packet, state)
      assert new_state.packets_extracted == 1
      assert new_state.crc_failures == 0

      # Extracted packet should NOT include CRC bytes (stripped by validation)
      assert byte_size(extracted) == @header_size + byte_size(payload)
    end

    test "validates CRC-32 successfully" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc32)
      payload = "Test payload"
      packet = build_packet_with_crc(100, 1, payload, :crc32)

      assert {:ok, [_extracted], new_state} = CCSDSProtocol.read_data(packet, state)
      assert new_state.crc_failures == 0
    end

    test "skips packet on CRC failure with on_failure: :skip" do
      state = CCSDSProtocol.new(
        crc_enabled: true,
        crc_algorithm: :crc16_ccitt,
        crc_on_failure: :skip
      )

      # Build packet with incorrect CRC
      payload = "Test payload"
      header = build_header(100, 1, byte_size(payload) + 2 - 1)
      bad_crc = <<0x00, 0x00>>
      packet = @default_sync <> header <> payload <> bad_crc

      assert {:ok, [], new_state} = CCSDSProtocol.read_data(packet, state)
      assert new_state.crc_failures == 1
    end

    test "disconnects on CRC failure with on_failure: :disconnect" do
      state = CCSDSProtocol.new(
        crc_enabled: true,
        crc_algorithm: :crc16_ccitt,
        crc_on_failure: :disconnect
      )

      # Build packet with incorrect CRC
      payload = "Test payload"
      header = build_header(100, 1, byte_size(payload) + 2 - 1)
      bad_crc = <<0x00, 0x00>>
      packet = @default_sync <> header <> payload <> bad_crc

      assert {:disconnect, reason} = CCSDSProtocol.read_data(packet, state)
      assert reason =~ "CRC mismatch"
    end

    test "respects CRC endianness" do
      state = CCSDSProtocol.new(
        crc_enabled: true,
        crc_algorithm: :crc16_ccitt,
        crc_endian: :little
      )

      payload = "Test payload"
      packet = build_packet_with_crc(100, 1, payload, :crc16_ccitt, endian: :little)

      assert {:ok, [_extracted], _state} = CCSDSProtocol.read_data(packet, state)
    end
  end

  describe "write_data/2 - building packets from raw payload" do
    test "builds complete packet from raw payload" do
      state = CCSDSProtocol.new(default_apid: 50)
      payload = "Raw payload data"

      assert {:ok, [framed], new_state} = CCSDSProtocol.write_data(payload, state)
      assert new_state.packets_written == 1
      assert new_state.sequence_count == 1

      # Should have: sync (4) + header (6) + payload
      expected_size = byte_size(@default_sync) + @header_size + byte_size(payload)
      assert byte_size(framed) == expected_size

      # Verify sync is present
      assert :binary.match(framed, @default_sync) == {0, 4}
    end

    test "builds packet with CRC" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc16_ccitt)
      payload = "Payload with CRC"

      assert {:ok, [framed], _state} = CCSDSProtocol.write_data(payload, state)

      # Should have: sync (4) + header (6) + payload + CRC (2)
      expected_size = byte_size(@default_sync) + @header_size + byte_size(payload) + 2
      assert byte_size(framed) == expected_size
    end

    test "increments sequence counter" do
      state = CCSDSProtocol.new([])

      {:ok, _, state} = CCSDSProtocol.write_data("packet1", state)
      assert state.sequence_count == 1

      {:ok, _, state} = CCSDSProtocol.write_data("packet2", state)
      assert state.sequence_count == 2

      {:ok, _, state} = CCSDSProtocol.write_data("packet3", state)
      assert state.sequence_count == 3
    end

    test "wraps sequence counter at 16384" do
      state = %{CCSDSProtocol.new([]) | sequence_count: 16383}

      {:ok, _, state} = CCSDSProtocol.write_data("payload", state)
      assert state.sequence_count == 0
    end
  end

  describe "write_data/2 - framing pre-built packets" do
    test "detects pre-built packet and adds framing" do
      state = CCSDSProtocol.new([])
      payload = "Pre-built payload"

      # Build packet without sync
      pre_built = build_packet(100, 5, payload, include_sync: false)

      assert {:ok, [framed], _state} = CCSDSProtocol.write_data(pre_built, state)

      # Should have sync prepended
      assert :binary.match(framed, @default_sync) == {0, 4}
      assert byte_size(framed) == byte_size(@default_sync) + byte_size(pre_built)
    end

    test "adds CRC to pre-built packet" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc16_ccitt)
      payload = "Pre-built payload"

      # Build packet without sync or CRC
      pre_built = build_packet(100, 5, payload, include_sync: false)
      original_size = byte_size(pre_built)

      assert {:ok, [framed], _state} = CCSDSProtocol.write_data(pre_built, state)

      # Should have: sync (4) + original + CRC (2)
      expected_size = byte_size(@default_sync) + original_size + 2
      assert byte_size(framed) == expected_size
    end

    test "pre-built packet is readable after framing" do
      write_state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc16_ccitt)
      read_state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc16_ccitt)

      payload = "Roundtrip test"
      pre_built = build_packet(100, 5, payload, include_sync: false)

      # Write: add sync + CRC
      {:ok, [framed], _} = CCSDSProtocol.write_data(pre_built, write_state)

      # Read: should extract successfully
      {:ok, [extracted], _} = CCSDSProtocol.read_data(framed, read_state)

      # Extracted should be header + payload (no sync, no CRC)
      assert byte_size(extracted) == @header_size + byte_size(payload)
    end
  end

  describe "roundtrip - write then read" do
    test "raw payload roundtrip without CRC" do
      state = CCSDSProtocol.new([])
      original_payload = "Hello, Space!"

      {:ok, [framed], state} = CCSDSProtocol.write_data(original_payload, state)
      {:ok, [extracted], _state} = CCSDSProtocol.read_data(framed, state)

      # Extracted includes header + payload
      # Extract just the payload part
      <<_header::binary-size(@header_size), recovered_payload::binary>> = extracted
      assert recovered_payload == original_payload
    end

    test "raw payload roundtrip with CRC" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc16_ccitt)
      original_payload = "Validated payload"

      {:ok, [framed], state} = CCSDSProtocol.write_data(original_payload, state)
      {:ok, [extracted], _state} = CCSDSProtocol.read_data(framed, state)

      <<_header::binary-size(@header_size), recovered_payload::binary>> = extracted
      assert recovered_payload == original_payload
    end

    test "roundtrip with all supported CRC algorithms" do
      for algorithm <- [:crc16_ccitt, :crc32, :crc16_xmodem] do
        state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: algorithm)
        original = "Test for #{algorithm}"

        {:ok, [framed], state} = CCSDSProtocol.write_data(original, state)
        {:ok, [extracted], _state} = CCSDSProtocol.read_data(framed, state)

        <<_header::binary-size(@header_size), recovered::binary>> = extracted
        assert recovered == original, "Failed for algorithm #{algorithm}"
      end
    end

    test "pre-built packet roundtrip" do
      state = CCSDSProtocol.new(crc_enabled: true, crc_algorithm: :crc16_ccitt)

      apid = 123
      seq = 456
      payload = "Pre-built roundtrip"
      pre_built = build_packet(apid, seq, payload, include_sync: false)

      {:ok, [framed], _} = CCSDSProtocol.write_data(pre_built, state)
      {:ok, [extracted], _} = CCSDSProtocol.read_data(framed, state)

      # Verify APID and sequence are preserved
      <<packet_id::16, seq_control::16, _data_length::16, recovered_payload::binary>> = extracted

      recovered_apid = packet_id &&& 0x07FF
      recovered_seq = seq_control &&& 0x3FFF

      assert recovered_apid == apid
      assert recovered_seq == seq
      assert recovered_payload == payload
    end
  end

  describe "packet_format/0" do
    test "returns :ccsds" do
      assert CCSDSProtocol.packet_format() == :ccsds
    end
  end

  describe "connect_reset/1" do
    test "clears buffer on reset" do
      state = %{CCSDSProtocol.new([]) | buffer: "leftover data"}
      reset_state = CCSDSProtocol.connect_reset(state)
      assert reset_state.buffer == <<>>
    end
  end

  describe "edge cases" do
    test "handles packet with minimum payload (1 byte)" do
      state = CCSDSProtocol.new([])
      payload = <<0x42>>
      packet = build_packet(100, 1, payload)

      assert {:ok, [extracted], _state} = CCSDSProtocol.read_data(packet, state)
      <<_header::binary-size(@header_size), recovered::binary>> = extracted
      assert recovered == payload
    end

    test "handles large payload" do
      state = CCSDSProtocol.new([])
      # Create ~64KB payload (near CCSDS max)
      payload = :crypto.strong_rand_bytes(65535)
      packet = build_packet(100, 1, payload)

      assert {:ok, [extracted], _state} = CCSDSProtocol.read_data(packet, state)
      <<_header::binary-size(@header_size), recovered::binary>> = extracted
      assert recovered == payload
    end

    test "handles custom sync pattern" do
      custom_sync = <<0xDE, 0xAD, 0xBE, 0xEF>>
      state = CCSDSProtocol.new(sync_pattern: custom_sync)

      payload = "Custom sync test"
      packet = build_packet(100, 1, payload, sync: custom_sync)

      assert {:ok, [_extracted], _state} = CCSDSProtocol.read_data(packet, state)
    end

    test "ignores packets with wrong sync pattern" do
      state = CCSDSProtocol.new([])

      # Build packet with wrong sync
      wrong_sync = <<0xAA, 0xBB, 0xCC, 0xDD>>
      payload = "Wrong sync"
      header = build_header(100, 1, byte_size(payload) - 1)
      packet = wrong_sync <> header <> payload

      # Should buffer, looking for correct sync
      assert {:ok, [], new_state} = CCSDSProtocol.read_data(packet, state)
      assert new_state.packets_extracted == 0
    end
  end

  describe "state tracking" do
    test "tracks packets_extracted" do
      state = CCSDSProtocol.new([])

      packet1 = build_packet(100, 1, "First")
      packet2 = build_packet(100, 2, "Second")

      {:ok, _, state} = CCSDSProtocol.read_data(packet1, state)
      assert state.packets_extracted == 1

      {:ok, _, state} = CCSDSProtocol.read_data(packet2, state)
      assert state.packets_extracted == 2
    end

    test "tracks packets_written" do
      state = CCSDSProtocol.new([])

      {:ok, _, state} = CCSDSProtocol.write_data("First", state)
      assert state.packets_written == 1

      {:ok, _, state} = CCSDSProtocol.write_data("Second", state)
      assert state.packets_written == 2
    end

    test "tracks crc_failures" do
      state = CCSDSProtocol.new(
        crc_enabled: true,
        crc_algorithm: :crc16_ccitt,
        crc_on_failure: :skip
      )

      # Build packet with bad CRC
      payload = "Bad CRC"
      header = build_header(100, 1, byte_size(payload) + 2 - 1)
      bad_packet = @default_sync <> header <> payload <> <<0x00, 0x00>>

      {:ok, [], state} = CCSDSProtocol.read_data(bad_packet, state)
      assert state.crc_failures == 1
    end
  end
end
