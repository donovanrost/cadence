defmodule Cadence.Telemetry.Protocols.LengthProtocol do
  @moduledoc """
  Variable-length packet protocol with embedded length field.

  Delineates packets by reading a length field from the data stream, then
  extracting that many bytes as the packet payload. Supports complex configurations
  including bit offsets, sync patterns, and byte multipliers.

  ## COSMOS Parameters

  Based on OpenC3 COSMOS LengthProtocol:

  - `length_bit_offset` - Bit offset to start of length field (default: 0)
  - `length_bit_size` - Size of length field in bits (default: 32)
  - `length_value_offset` - Value added to length field (default: 0)
  - `length_bytes_per_count` - Length multiplier, 1 = bytes (default: 1)
  - `length_endian` - :big or :little endian (default: :big)
  - `discard_leading_bytes` - Bytes to skip before packet data (default: 0)
  - `sync_pattern` - Optional sync pattern to search for (default: nil)
  - `fill_length_and_sync` - Fill to length + sync pattern (default: false)

  ## Examples

      # Simple 4-byte big-endian length header
      LengthProtocol.new(
        length_bit_size: 32,
        length_endian: :big
      )

      # CCSDS-style with sync pattern
      LengthProtocol.new(
        length_bit_offset: 64,      # After 8-byte header
        length_bit_size: 16,         # 2 bytes
        length_value_offset: 1,      # CCSDS length = actual - 1
        length_endian: :big,
        sync_pattern: <<0x1A, 0xCF, 0xFC, 0x1D>>
      )

  ## Read Flow

  1. Optionally search for sync pattern
  2. Read length field at specified bit offset
  3. Calculate packet size: (length * bytes_per_count) + value_offset
  4. Extract packet payload
  5. Optionally discard leading bytes from payload

  ## Write Flow

  1. Calculate length: (payload_size / bytes_per_count) - value_offset
  2. Encode length field
  3. Prepend sync pattern if configured
  4. Return framed packet
  """

  use Cadence.Telemetry.Protocol

  defstruct [
    :length_bit_offset,
    :length_bit_size,
    :length_value_offset,
    :length_bytes_per_count,
    :length_endian,
    :discard_leading_bytes,
    :sync_pattern,
    :fill_length_and_sync,
    buffer: <<>>,
    packets_extracted: 0
  ]

  @doc """
  Create new LengthProtocol instance.

  ## Options

  See moduledoc for parameter descriptions.
  """
  def new(opts \\ []) do
    %__MODULE__{
      length_bit_offset: Keyword.get(opts, :length_bit_offset, 0),
      length_bit_size: Keyword.get(opts, :length_bit_size, 32),
      length_value_offset: Keyword.get(opts, :length_value_offset, 0),
      length_bytes_per_count: Keyword.get(opts, :length_bytes_per_count, 1),
      length_endian: Keyword.get(opts, :length_endian, :big),
      discard_leading_bytes: Keyword.get(opts, :discard_leading_bytes, 0),
      sync_pattern: Keyword.get(opts, :sync_pattern),
      fill_length_and_sync: Keyword.get(opts, :fill_length_and_sync, false)
    }
  end

  @doc """
  Extract packets from incoming data stream.

  Buffers incomplete data and returns :stop when more data needed.
  Returns {:ok, packets, state} when complete packets extracted.
  """
  def read_data(data, state) when is_binary(data) do
    new_buffer = state.buffer <> data
    extract_packets(new_buffer, state, [])
  end

  # Recursive packet extraction
  defp extract_packets(buffer, state, acc) do
    # First, handle sync pattern if configured
    if state.sync_pattern do
      case find_sync_pattern(buffer, state.sync_pattern) do
        {:ok, offset} ->
          # Skip to sync pattern and continue
          sync_len = byte_size(state.sync_pattern)
          <<_skip::binary-size(offset), _sync::binary-size(sync_len), rest::binary>> = buffer
          extract_packets_after_sync(rest, state, acc)

        :not_found ->
          # Keep last N bytes in case sync is split across reads
          keep_bytes = max(0, byte_size(state.sync_pattern) - 1)

          keep =
            if byte_size(buffer) > keep_bytes do
              binary_part(buffer, byte_size(buffer) - keep_bytes, keep_bytes)
            else
              buffer
            end

          # Return early - no sync found
          return_packets(acc, %{state | buffer: keep})
      end
    else
      # No sync pattern - process directly
      extract_packets_after_sync(buffer, state, acc)
    end
  end

  # Continue extraction after sync pattern found (or no sync configured)
  defp extract_packets_after_sync(buffer, state, acc) do

    # Calculate offsets for length field
    length_byte_offset = div(state.length_bit_offset, 8)
    length_byte_size = div(state.length_bit_size, 8)
    length_total_bytes = length_byte_offset + length_byte_size

    cond do
      # Not enough data for length field
      byte_size(buffer) < length_total_bytes ->
        return_packets(acc, %{state | buffer: buffer})

      # Have length field, extract it
      true ->
        <<_skip::binary-size(length_byte_offset), length_bytes::binary-size(length_byte_size),
          _after_length::binary>> = buffer

        # Decode length field
        length_value = decode_length(length_bytes, state)

        # Calculate total packet size
        # Length can be:
        # 1. Just payload size (length_value_offset = 0)
        # 2. Payload - 1 (CCSDS: length_value_offset = 1)
        # 3. In units other than bytes (length_bytes_per_count != 1)
        payload_size = length_value * state.length_bytes_per_count + state.length_value_offset

        # Total packet includes length header + payload
        total_packet_size = length_total_bytes + payload_size

        # Check if we have complete packet
        if byte_size(buffer) >= total_packet_size do
          # Extract complete packet
          <<packet::binary-size(total_packet_size), remaining::binary>> = buffer

          # Optionally discard leading bytes (e.g., length header itself)
          packet =
            if state.discard_leading_bytes > 0 and
                 byte_size(packet) > state.discard_leading_bytes do
              binary_part(packet, state.discard_leading_bytes, byte_size(packet) - state.discard_leading_bytes)
            else
              packet
            end

          new_state = %{state | packets_extracted: state.packets_extracted + 1}

          # Continue extracting more packets
          extract_packets(remaining, new_state, [packet | acc])
        else
          # Need more data for payload
          return_packets(acc, %{state | buffer: buffer})
        end
    end
  end

  # Helper to return accumulated packets
  defp return_packets([], state) do
    {:stop, state}
  end

  defp return_packets(packets, state) do
    {:ok, Enum.reverse(packets), state}
  end

  # Decode length field based on endianness
  defp decode_length(bytes, state) do
    case state.length_endian do
      :big -> :binary.decode_unsigned(bytes, :big)
      :little -> :binary.decode_unsigned(bytes, :little)
    end
  end

  # Find sync pattern in buffer
  defp find_sync_pattern(buffer, pattern) do
    case :binary.match(buffer, pattern) do
      {offset, _length} -> {:ok, offset}
      :nomatch -> :not_found
    end
  end

  @doc """
  Encode outgoing packet with length header.

  Adds length field and optional sync pattern for command transmission.
  """
  def write_data(data, state) do
    # Calculate length value
    # Length = (payload_size - value_offset) / bytes_per_count
    length_value =
      div(byte_size(data) - state.length_value_offset, state.length_bytes_per_count)

    # Encode length field
    length_bytes =
      case state.length_endian do
        :big -> <<length_value::unsigned-big-size(state.length_bit_size)>>
        :little -> <<length_value::unsigned-little-size(state.length_bit_size)>>
      end

    # Build packet: [optional sync][length][payload]
    packet =
      if state.sync_pattern do
        state.sync_pattern <> length_bytes <> data
      else
        length_bytes <> data
      end

    {:ok, [packet], state}
  end
end
