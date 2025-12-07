defmodule Cadence.Telemetry.Protocols.CCSDSProtocol do
  @moduledoc """
  CCSDS Space Packet Protocol implementation.

  Handles the complete CCSDS packet lifecycle including:
  - Sync pattern detection and framing
  - Primary header parsing (APID, sequence count, data length)
  - Optional CRC validation/generation

  ## CCSDS Packet Structure

  ```
  [Sync Pattern (4)][Primary Header (6)][Data Field (variable)][CRC (optional)]

  Primary Header:
    Bytes 0-1: Packet ID (version, type, sec hdr flag, APID)
    Bytes 2-3: Sequence Control (flags, count)
    Bytes 4-5: Data Length (payload bytes - 1)
  ```

  ## Configuration

  - `sync_pattern` - Sync marker bytes (default: 0x1ACFFC1D)
  - `include_sync` - Whether sync is present in stream (default: true)
  - `discard_sync` - Strip sync from extracted packets (default: true)
  - `crc_enabled` - Enable CRC validation/generation (default: false)
  - `crc_algorithm` - CRC algorithm: :crc16_ccitt, :crc32 (default: :crc16_ccitt)
  - `crc_endian` - CRC byte order: :big, :little (default: :big)
  - `crc_on_failure` - Failure mode: :skip, :disconnect, :pass (default: :skip)
  - `default_apid` - APID for write path when building headers (default: 0)

  ## Read Flow

  1. Search for sync pattern in buffer
  2. Parse 6-byte CCSDS primary header
  3. Extract data field based on length field
  4. Validate CRC if enabled (covers header + data, not sync)
  5. Strip sync if discard_sync is true
  6. Return extracted packet

  ## Write Flow

  1. Detect if input has CCSDS header (6+ bytes, valid structure)
  2. If no header: build one using default_apid and sequence counter
  3. Update data length field to include CRC if enabled
  4. Calculate and append CRC if enabled (covers header + data)
  5. Prepend sync pattern
  6. Return framed packet

  ## Example Configuration

      # Basic CCSDS with CRC
      %{
        "sync_pattern_hex" => "1ACFFC1D",
        "crc_enabled" => true,
        "crc_algorithm" => "crc16_ccitt"
      }
  """

  use Cadence.Telemetry.Protocol

  import Bitwise
  require Logger

  alias Cadence.Telemetry.CRC

  @default_sync <<0x1A, 0xCF, 0xFC, 0x1D>>
  @header_size 6

  defstruct [
    :sync_pattern,
    :crc_algorithm,
    :crc_endian,
    :crc_on_failure,
    :crc_size,
    :default_apid,
    include_sync: true,
    discard_sync: true,
    crc_enabled: false,
    buffer: <<>>,
    sequence_count: 0,
    packets_extracted: 0,
    packets_written: 0,
    crc_failures: 0
  ]

  @doc """
  Creates a new CCSDS protocol state.

  ## Options

  - `:sync_pattern` - Sync bytes (default: <<0x1A, 0xCF, 0xFC, 0x1D>>)
  - `:include_sync` - Expect sync in stream (default: true)
  - `:discard_sync` - Strip sync from output (default: true)
  - `:crc_enabled` - Enable CRC (default: false)
  - `:crc_algorithm` - :crc16_ccitt, :crc32, etc. (default: :crc16_ccitt)
  - `:crc_endian` - :big or :little (default: :big)
  - `:crc_on_failure` - :skip, :disconnect, :pass (default: :skip)
  - `:default_apid` - APID for generated headers (default: 0)
  """
  def new(opts \\ []) do
    sync_pattern = Keyword.get(opts, :sync_pattern, @default_sync)
    crc_enabled = Keyword.get(opts, :crc_enabled, false)
    crc_algorithm = normalize_algorithm(Keyword.get(opts, :crc_algorithm, :crc16_ccitt))
    crc_endian = normalize_endian(Keyword.get(opts, :crc_endian, :big))
    crc_on_failure = normalize_on_failure(Keyword.get(opts, :crc_on_failure, :skip))

    %__MODULE__{
      sync_pattern: sync_pattern,
      include_sync: Keyword.get(opts, :include_sync, true),
      discard_sync: Keyword.get(opts, :discard_sync, true),
      crc_enabled: crc_enabled,
      crc_algorithm: crc_algorithm,
      crc_endian: crc_endian,
      crc_on_failure: crc_on_failure,
      crc_size: if(crc_enabled, do: CRC.size(crc_algorithm), else: 0),
      default_apid: Keyword.get(opts, :default_apid, 0)
    }
  end

  @doc """
  Extract CCSDS packets from incoming data stream.
  """
  def read_data(data, state) do
    buffer = state.buffer <> data
    extract_packets(buffer, state, [])
  end

  @doc """
  Frame outgoing data as CCSDS packet.

  Accepts either:
  - Raw payload (will build CCSDS header)
  - Pre-built CCSDS packet (header + payload, will add sync and optional CRC)
  """
  def write_data(data, state) when byte_size(data) < @header_size do
    # Too small to have header - treat as raw payload, build full packet
    build_packet(data, state)
  end

  def write_data(data, state) do
    # Check if data looks like it already has a CCSDS header
    case parse_header(data) do
      {:ok, _apid, _seq, declared_length} ->
        # Has valid header - check if length makes sense
        actual_payload_size = byte_size(data) - @header_size

        if declared_length == actual_payload_size - 1 or
             declared_length == actual_payload_size - 1 - state.crc_size do
          # Pre-built packet - just add framing
          frame_existing_packet(data, state)
        else
          # Header present but length doesn't match - treat as raw payload
          build_packet(data, state)
        end

      :error ->
        # No valid header - build full packet
        build_packet(data, state)
    end
  end

  @doc """
  Returns :ccsds packet format.
  """
  def packet_format, do: :ccsds

  ## Private - Packet Extraction (Read Path)

  defp extract_packets(buffer, state, acc) do
    sync_size = byte_size(state.sync_pattern)
    min_packet_size = sync_size + @header_size + state.crc_size

    if byte_size(buffer) < min_packet_size do
      return_packets(acc, %{state | buffer: buffer})
    else
      case find_sync(buffer, state.sync_pattern) do
        :not_found ->
          # Keep last (sync_size - 1) bytes in case sync spans chunks
          keep_size = min(byte_size(buffer), sync_size - 1)
          <<_discard::binary-size(byte_size(buffer) - keep_size), keep::binary>> = buffer
          return_packets(acc, %{state | buffer: keep})

        {:found, offset} ->
          # Discard bytes before sync
          <<_garbage::binary-size(offset), sync_and_rest::binary>> = buffer

          if byte_size(sync_and_rest) < sync_size + @header_size do
            # Need more data for header
            return_packets(acc, %{state | buffer: sync_and_rest})
          else
            # Parse header
            <<_sync::binary-size(sync_size), header::binary-size(@header_size), rest::binary>> =
              sync_and_rest

            case parse_header(header) do
              {:ok, _apid, _seq, data_length} ->
                # CCSDS data_length = (data_field_bytes - 1)
                # When CRC is enabled, data_length already includes CRC bytes
                # So total_data_size is just data_length + 1
                total_data_size = data_length + 1

                if byte_size(rest) >= total_data_size do
                  # Extract complete packet
                  <<payload_and_crc::binary-size(total_data_size), remaining::binary>> = rest

                  packet_without_sync = header <> payload_and_crc
                  full_packet = state.sync_pattern <> packet_without_sync

                  # Validate CRC if enabled
                  case validate_crc(packet_without_sync, state) do
                    {:ok, validated_data} ->
                      # Decide what to return based on discard_sync
                      output =
                        if state.discard_sync do
                          validated_data
                        else
                          state.sync_pattern <> validated_data
                        end

                      new_state = %{state | packets_extracted: state.packets_extracted + 1}
                      extract_packets(remaining, new_state, [output | acc])

                    {:error, :crc_mismatch, expected, actual} ->
                      handle_crc_failure(state, expected, actual, full_packet, remaining, acc)

                    {:skip} ->
                      # CRC disabled, return the full packet (header + data)
                      output =
                        if state.discard_sync do
                          packet_without_sync
                        else
                          state.sync_pattern <> packet_without_sync
                        end

                      new_state = %{state | packets_extracted: state.packets_extracted + 1}
                      extract_packets(remaining, new_state, [output | acc])
                  end
                else
                  # Need more data for payload
                  return_packets(acc, %{state | buffer: sync_and_rest})
                end

              :error ->
                # Invalid header - skip sync and try again
                <<_sync::binary-size(sync_size), rest_after_sync::binary>> = sync_and_rest
                extract_packets(rest_after_sync, state, acc)
            end
          end
      end
    end
  end

  defp find_sync(buffer, sync_pattern) do
    case :binary.match(buffer, sync_pattern) do
      {offset, _length} -> {:found, offset}
      :nomatch -> :not_found
    end
  end

  defp parse_header(<<packet_id::16, seq_control::16, data_length::16>>) do
    # Extract fields from packet ID
    _version = packet_id >>> 13 &&& 0x07
    _type = packet_id >>> 12 &&& 0x01
    _sec_hdr_flag = packet_id >>> 11 &&& 0x01
    apid = packet_id &&& 0x07FF

    # Extract sequence fields
    _seq_flags = seq_control >>> 14 &&& 0x03
    seq_count = seq_control &&& 0x3FFF

    {:ok, apid, seq_count, data_length}
  end

  defp parse_header(data) when byte_size(data) >= @header_size do
    <<header::binary-size(@header_size), _rest::binary>> = data
    parse_header(header)
  end

  defp parse_header(_), do: :error

  defp validate_crc(_data, %{crc_enabled: false}), do: {:skip}

  defp validate_crc(data, state) do
    crc_size = state.crc_size
    data_size = byte_size(data) - crc_size

    if data_size < @header_size do
      {:error, :crc_mismatch, 0, 0}
    else
      <<packet_data::binary-size(data_size), crc_bytes::binary-size(crc_size)>> = data
      expected_crc = CRC.decode(crc_bytes, state.crc_algorithm, state.crc_endian)
      actual_crc = CRC.calculate(state.crc_algorithm, packet_data)

      if expected_crc == actual_crc do
        {:ok, packet_data}
      else
        {:error, :crc_mismatch, expected_crc, actual_crc}
      end
    end
  end

  defp handle_crc_failure(state, expected, actual, _full_packet, remaining, acc) do
    new_state = %{state | crc_failures: state.crc_failures + 1}

    case state.crc_on_failure do
      :disconnect ->
        {:disconnect,
         "CCSDS CRC mismatch: expected 0x#{Integer.to_string(expected, 16)}, " <>
           "got 0x#{Integer.to_string(actual, 16)}"}

      :skip ->
        Logger.warning(
          "CCSDS CRC mismatch (skipping): expected 0x#{Integer.to_string(expected, 16)}, " <>
            "got 0x#{Integer.to_string(actual, 16)}"
        )

        extract_packets(remaining, new_state, acc)

      :pass ->
        Logger.warning(
          "CCSDS CRC mismatch (passing): expected 0x#{Integer.to_string(expected, 16)}, " <>
            "got 0x#{Integer.to_string(actual, 16)}"
        )

        # TODO: pass the packet anyway
        extract_packets(remaining, new_state, acc)
    end
  end

  defp return_packets([], state), do: {:ok, [], state}
  defp return_packets(acc, state), do: {:ok, Enum.reverse(acc), state}

  ## Private - Packet Building (Write Path)

  # Frame an existing CCSDS packet (has header) - add CRC and sync
  defp frame_existing_packet(packet, state) do
    # Packet already has header + payload
    # Need to: optionally add CRC, then prepend sync

    packet_with_crc =
      if state.crc_enabled do
        # Update length field to account for CRC
        <<packet_id::16, seq_control::16, data_length::16, payload::binary>> = packet
        new_length = data_length + state.crc_size
        updated_header = <<packet_id::16, seq_control::16, new_length::16>>
        updated_packet = updated_header <> payload

        # Calculate CRC on header + payload (not sync)
        crc = CRC.calculate(state.crc_algorithm, updated_packet)
        crc_bytes = CRC.encode(crc, state.crc_algorithm, state.crc_endian)
        updated_packet <> crc_bytes
      else
        packet
      end

    # Prepend sync
    framed = state.sync_pattern <> packet_with_crc
    new_state = %{state | packets_written: state.packets_written + 1}

    {:ok, [framed], new_state}
  end

  # Build a complete CCSDS packet from raw payload
  defp build_packet(payload, state) do
    # Build CCSDS primary header
    version = 0
    type = 0
    sec_hdr_flag = if byte_size(payload) > 0, do: 1, else: 0
    apid = state.default_apid

    packet_id = version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid

    seq_flags = 3
    seq_count = state.sequence_count
    seq_control = seq_flags <<< 14 ||| seq_count

    # Data length = payload_size - 1 (+ CRC size if enabled, will be added)
    base_length = byte_size(payload) - 1
    data_length = if state.crc_enabled, do: base_length + state.crc_size, else: base_length

    header = <<packet_id::16, seq_control::16, data_length::16>>
    packet = header <> payload

    packet_with_crc =
      if state.crc_enabled do
        crc = CRC.calculate(state.crc_algorithm, packet)
        crc_bytes = CRC.encode(crc, state.crc_algorithm, state.crc_endian)
        packet <> crc_bytes
      else
        packet
      end

    framed = state.sync_pattern <> packet_with_crc

    new_state = %{
      state
      | packets_written: state.packets_written + 1,
        sequence_count: rem(state.sequence_count + 1, 16384)
    }

    {:ok, [framed], new_state}
  end

  ## Private - Helpers

  defp normalize_algorithm(alg) when is_atom(alg), do: alg

  defp normalize_algorithm(alg) when is_binary(alg) do
    case alg do
      "crc16_ccitt" -> :crc16_ccitt
      "crc16-ccitt" -> :crc16_ccitt
      "crc32" -> :crc32
      "crc16_xmodem" -> :crc16_xmodem
      "crc16-xmodem" -> :crc16_xmodem
      other -> raise ArgumentError, "Unknown CRC algorithm: #{inspect(other)}"
    end
  end

  defp normalize_endian(e) when e in [:big, :little], do: e
  defp normalize_endian("big"), do: :big
  defp normalize_endian("little"), do: :little
  defp normalize_endian(_), do: :big

  defp normalize_on_failure(f) when f in [:skip, :disconnect, :pass], do: f
  defp normalize_on_failure("skip"), do: :skip
  defp normalize_on_failure("disconnect"), do: :disconnect
  defp normalize_on_failure("pass"), do: :pass
  defp normalize_on_failure(_), do: :skip
end
