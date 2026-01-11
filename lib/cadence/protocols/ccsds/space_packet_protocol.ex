defmodule Cadence.Protocols.CCSDS.SpacePacketProtocol do
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
      buffer
      |> next_packet(state, sync_size)
      |> handle_next_packet(acc)
    end
  end

  defp handle_next_packet({:emit, output, remaining, new_state}, acc) do
    extract_packets(remaining, new_state, [output | acc])
  end

  defp handle_next_packet({:skip, remaining, new_state}, acc) do
    extract_packets(remaining, new_state, acc)
  end

  defp handle_next_packet({:need_more, new_buffer, new_state}, acc) do
    return_packets(acc, %{new_state | buffer: new_buffer})
  end

  defp handle_next_packet({:disconnect, reason}, _acc) do
    {:disconnect, reason}
  end

  defp find_sync(buffer, sync_pattern) do
    case :binary.match(buffer, sync_pattern) do
      {position, _length} -> {:ok, position}
      :nomatch -> :error
    end
  end

  defp next_packet(buffer, state, sync_size) do
    case find_sync(buffer, state.sync_pattern) do
      {:ok, 0} ->
        extract_from_sync(buffer, state, sync_size)

      {:ok, position} ->
        # Skip data before sync
        Logger.debug("Skipping #{position} bytes before sync")
        <<_skip::binary-size(position), remaining::binary>> = buffer
        next_packet(remaining, state, sync_size)

      :error ->
        # No sync found - keep last sync_size-1 bytes (in case sync spans boundary)
        keep_size = max(sync_size - 1, 0)
        <<_skip::binary-size(byte_size(buffer) - keep_size), remaining::binary>> = buffer
        {:need_more, remaining, state}
    end
  end

  defp extract_from_sync(buffer, state, sync_size) do
    min_size = sync_size + @header_size + state.crc_size

    if byte_size(buffer) < min_size do
      {:need_more, buffer, state}
    else
      <<_sync::binary-size(sync_size), rest::binary>> = buffer

      case parse_header(rest) do
        {:ok, _apid, _seq, length} ->
          total_size = sync_size + @header_size + length + 1

          if byte_size(buffer) >= total_size do
            <<packet::binary-size(total_size), remaining::binary>> = buffer
            handle_extracted_packet(packet, remaining, state, sync_size)
          else
            {:need_more, buffer, state}
          end

        :error ->
          # Invalid header after sync, skip sync and continue
          <<_skip::binary-size(sync_size), remaining::binary>> = buffer
          {:need_more, remaining, state}
      end
    end
  end

  defp handle_extracted_packet(packet, remaining, state, sync_size) do
    <<sync::binary-size(sync_size), rest::binary>> = packet

    {payload, crc} = split_crc(rest, state)

    case validate_crc(payload, crc, state) do
      :ok ->
        output =
          if state.discard_sync do
            payload
          else
            sync <> payload
          end

        new_state = %{state | packets_extracted: state.packets_extracted + 1}
        {:emit, output, remaining, new_state}

      {:error, reason} ->
        handle_crc_failure(reason, payload, remaining, state)
    end
  end

  defp split_crc(rest, state) do
    if state.crc_enabled do
      payload_size = byte_size(rest) - state.crc_size
      <<payload::binary-size(payload_size), crc::binary-size(state.crc_size)>> = rest
      {payload, crc}
    else
      {rest, <<>>}
    end
  end

  defp validate_crc(_payload, _crc, %{crc_enabled: false}), do: :ok

  defp validate_crc(payload, crc, state) do
    expected_value = CRC.calculate(state.crc_algorithm, payload)
    expected_crc = CRC.encode(expected_value, state.crc_algorithm, state.crc_endian)

    if crc == expected_crc do
      :ok
    else
      {:error, {:crc_mismatch, expected_crc, crc}}
    end
  end

  defp handle_crc_failure(reason, payload, remaining, state) do
    new_state = %{state | crc_failures: state.crc_failures + 1}
    message = format_crc_failure(reason)

    case state.crc_on_failure do
      :skip ->
        {:skip, remaining, new_state}

      :disconnect ->
        {:disconnect, message}

      :pass ->
        {:emit, payload, remaining, new_state}
    end
  end

  defp return_packets([], state), do: {:ok, [], state}

  defp return_packets(packets, state) do
    {:ok, Enum.reverse(packets), state}
  end

  ## Private - Write Path

  defp build_packet(payload, state) do
    {header, new_state} = build_header(payload, state)
    packet = header <> payload
    framed = add_framing(packet, state)
    {:ok, [framed], new_state}
  end

  defp frame_existing_packet(packet, state) do
    {packet, framing_state} = prepare_existing_packet(packet, state)
    framed = add_framing(packet, framing_state)
    new_state = %{state | packets_written: state.packets_written + 1}
    {:ok, [framed], new_state}
  end

  defp add_framing(packet, state) do
    packet
    |> maybe_add_crc(state)
    |> maybe_add_sync(state)
  end

  defp maybe_add_crc(packet, %{crc_enabled: false}), do: packet

  defp maybe_add_crc(packet, state) do
    crc_value = CRC.calculate(state.crc_algorithm, packet)
    packet <> CRC.encode(crc_value, state.crc_algorithm, state.crc_endian)
  end

  defp maybe_add_sync(packet, %{include_sync: false}), do: packet

  defp maybe_add_sync(packet, state) do
    state.sync_pattern <> packet
  end

  defp build_header(payload, state) do
    packet_id = build_packet_id(state.default_apid)
    seq_control = build_sequence_control(state.sequence_count)
    length = byte_size(payload) - 1 + state.crc_size

    header = <<packet_id::16, seq_control::16, length::16>>

    new_state = %{
      state
      | sequence_count: next_sequence(state.sequence_count),
        packets_written: state.packets_written + 1
    }
    {header, new_state}
  end

  defp prepare_existing_packet(packet, %{crc_enabled: true} = state) do
    if packet_has_crc?(packet, state) do
      {packet, %{state | crc_enabled: false}}
    else
      {update_length_for_crc(packet, state), state}
    end
  end

  defp prepare_existing_packet(packet, state), do: {packet, state}

  defp packet_has_crc?(packet, state) do
    crc_size = state.crc_size

    if byte_size(packet) < @header_size + crc_size do
      false
    else
      data_size = byte_size(packet) - crc_size
      <<data::binary-size(data_size), crc::binary-size(crc_size)>> = packet
      expected_value = CRC.calculate(state.crc_algorithm, data)
      expected_crc = CRC.encode(expected_value, state.crc_algorithm, state.crc_endian)
      crc == expected_crc
    end
  end

  defp update_length_for_crc(packet, state) do
    case parse_header(packet) do
      {:ok, _apid, _seq, length} ->
        update_length(packet, length + state.crc_size)

      :error ->
        packet
    end
  end

  defp update_length(<<packet_id::16, seq_control::16, _length::16, rest::binary>>, new_length) do
    <<packet_id::16, seq_control::16, new_length::16, rest::binary>>
  end

  defp format_crc_failure({:crc_mismatch, expected, actual}) do
    "CRC mismatch (expected=#{Base.encode16(expected)}, actual=#{Base.encode16(actual)})"
  end

  defp format_crc_failure(reason), do: "CRC mismatch (#{inspect(reason)})"

  defp build_packet_id(apid) do
    version = 0
    type = 0
    sec_hdr_flag = 1
    version <<< 13 ||| type <<< 12 ||| sec_hdr_flag <<< 11 ||| apid
  end

  defp build_sequence_control(sequence_count) do
    sequence_flags = 3
    sequence_flags <<< 14 ||| sequence_count
  end

  defp next_sequence(sequence_count) do
    rem(sequence_count + 1, 16_384)
  end

  defp parse_header(<<packet_id::16, seq_control::16, length::16, _rest::binary>>) do
    apid = packet_id &&& 0x07FF
    seq = seq_control &&& 0x3FFF
    {:ok, apid, seq, length}
  end

  defp parse_header(_), do: :error

  ## Normalization

  defp normalize_algorithm(value) when is_atom(value), do: value

  defp normalize_algorithm(value) when is_binary(value) do
    case String.downcase(value) do
      "crc16" -> :crc16_ccitt
      "crc16_ccitt" -> :crc16_ccitt
      "crc16-ccitt" -> :crc16_ccitt
      "crc16_xmodem" -> :crc16_xmodem
      "crc16-xmodem" -> :crc16_xmodem
      "crc32" -> :crc32
      "crc8" -> :crc8
      "xor" -> :xor_checksum
      "xor_checksum" -> :xor_checksum
      other -> raise ArgumentError, "Unsupported CRC algorithm: #{inspect(other)}"
    end
  end

  defp normalize_endian(value) when is_atom(value), do: value

  defp normalize_endian(value) when is_binary(value) do
    case String.downcase(value) do
      "big" -> :big
      "little" -> :little
      other -> raise ArgumentError, "Invalid endian: #{inspect(other)}"
    end
  end

  defp normalize_on_failure(value) when is_atom(value), do: value

  defp normalize_on_failure(value) when is_binary(value) do
    case String.downcase(value) do
      "skip" -> :skip
      "disconnect" -> :disconnect
      "pass" -> :pass
      other -> raise ArgumentError, "Invalid crc_on_failure: #{inspect(other)}"
    end
  end
end
