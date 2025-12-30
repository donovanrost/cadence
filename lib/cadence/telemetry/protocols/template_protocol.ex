defmodule Cadence.Telemetry.Protocols.TemplateProtocol do
  @moduledoc """
  Template-based packet protocol with sync pattern and header parsing.

  Delineates packets by searching for a sync pattern, then reading a fixed-length
  header to determine the packet payload size. This is the standard CCSDS approach.

  ## COSMOS Parameters

  Based on OpenC3 COSMOS TemplateProtocol:

  - `sync_pattern` - Binary sync pattern to search for (required)
  - `header_length` - Number of bytes in header after sync (default: 6)
  - `length_offset` - Byte offset in header where length field starts (default: 4)
  - `length_bit_size` - Size of length field in bits (default: 16)
  - `length_value_offset` - Value added to length field (default: 1)
  - `length_bytes_per_count` - Length multiplier (default: 1)
  - `length_endian` - :big or :little endian (default: :big)
  - `discard_leading_bytes` - Bytes to discard before returning packet (default: 0)

  ## Examples

      # CCSDS Space Packet Protocol
      TemplateProtocol.new(
        sync_pattern: <<0x1A, 0xCF, 0xFC, 0x1D>>,
        header_length: 6,
        length_offset: 4,          # Data length at bytes 4-5
        length_bit_size: 16,
        length_value_offset: 1,    # CCSDS: length = actual - 1
        length_endian: :big
      )

      # Custom sync with 4-byte header
      TemplateProtocol.new(
        sync_pattern: <<0xDE, 0xAD, 0xBE, 0xEF>>,
        header_length: 4,
        length_offset: 2,
        length_bit_size: 16
      )

  ## Packet Structure

  ```
  [Sync Pattern][Header][Payload]
  ```

  The header contains a length field that specifies the payload size.
  Total packet size = sync_size + header_size + payload_size.

  ## Read Flow

  1. Search for sync pattern in buffer
  2. Read header_length bytes after sync
  3. Extract length field from header at length_offset
  4. Calculate payload size: (length * bytes_per_count) + value_offset
  5. Extract complete packet (sync + header + payload)
  6. Continue extracting more packets or buffer if incomplete

  ## Write Flow

  1. Calculate length field: (payload_size / bytes_per_count) - value_offset
  2. Build header with encoded length
  3. Prepend sync pattern
  4. Return [sync][header][payload]
  """

  use Cadence.Telemetry.Protocol

  defstruct [
    :sync_pattern,
    :header_length,
    :length_offset,
    :length_bit_size,
    :length_value_offset,
    :length_bytes_per_count,
    :length_endian,
    :discard_leading_bytes,
    buffer: <<>>,
    packets_extracted: 0
  ]

  @doc """
  Create new TemplateProtocol instance.

  ## Options

  See moduledoc for parameter descriptions.
  """
  def new(opts \\ []) do
    sync_pattern = Keyword.fetch!(opts, :sync_pattern)

    unless is_binary(sync_pattern) and byte_size(sync_pattern) > 0 do
      raise ArgumentError, "sync_pattern must be a non-empty binary"
    end

    %__MODULE__{
      sync_pattern: sync_pattern,
      header_length: Keyword.get(opts, :header_length, 6),
      length_offset: Keyword.get(opts, :length_offset, 4),
      length_bit_size: Keyword.get(opts, :length_bit_size, 16),
      length_value_offset: Keyword.get(opts, :length_value_offset, 1),
      length_bytes_per_count: Keyword.get(opts, :length_bytes_per_count, 1),
      length_endian: Keyword.get(opts, :length_endian, :big),
      discard_leading_bytes: Keyword.get(opts, :discard_leading_bytes, 0)
    }
  end

  @doc """
  Extract packets from incoming data stream.

  Searches for sync pattern, reads header, extracts complete packets.
  Returns :stop when more data needed.
  """
  def read_data(data, state) when is_binary(data) do
    new_buffer = state.buffer <> data
    extract_packets(new_buffer, state, [])
  end

  # Recursive packet extraction
  defp extract_packets(buffer, state, acc) do
    sync_size = byte_size(state.sync_pattern)
    header_size = state.header_length

    case next_packet(buffer, state, sync_size, header_size) do
      {:emit, packet, remaining, new_state} ->
        extract_packets(remaining, new_state, [packet | acc])

      {:need_more, new_buffer, new_state} ->
        return_packets(acc, %{new_state | buffer: new_buffer})

      {:disconnect, reason} ->
        {:disconnect, reason}
    end
  end

  defp next_packet(buffer, state, sync_size, header_size) do
    case locate_sync(buffer, state.sync_pattern, sync_size) do
      {:ok, synced_buffer} ->
        extract_from_synced(synced_buffer, state, sync_size, header_size)

      {:need_more, new_buffer} ->
        {:need_more, new_buffer, state}
    end
  end

  defp extract_from_synced(synced_buffer, state, sync_size, header_size) do
    with {:ok, header} <- extract_header(synced_buffer, sync_size, header_size),
         {:ok, payload_size} <- payload_size_from_header(header, state, header_size),
         {:ok, packet, remaining} <-
           extract_packet(synced_buffer, sync_size, header_size, payload_size) do
      packet = maybe_discard_leading(packet, state)
      new_state = %{state | packets_extracted: state.packets_extracted + 1}
      {:emit, packet, remaining, new_state}
    else
      {:need_more, new_buffer} ->
        {:need_more, new_buffer, state}

      {:error, reason} ->
        {:disconnect, reason}

      {:disconnect, reason} ->
        {:disconnect, reason}
    end
  end

  defp locate_sync(buffer, sync_pattern, sync_size) do
    case find_sync_pattern(buffer, sync_pattern) do
      {:ok, sync_offset} ->
        {:ok, binary_part(buffer, sync_offset, byte_size(buffer) - sync_offset)}

      :not_found ->
        keep_bytes = max(0, sync_size - 1)

        if byte_size(buffer) > keep_bytes do
          keep = binary_part(buffer, byte_size(buffer) - keep_bytes, keep_bytes)
          {:need_more, keep}
        else
          {:need_more, buffer}
        end
    end
  end

  defp extract_header(buffer, sync_size, header_size) do
    if byte_size(buffer) < sync_size + header_size do
      {:need_more, buffer}
    else
      <<_sync::binary-size(sync_size), header::binary-size(header_size), _rest::binary>> = buffer
      {:ok, header}
    end
  end

  defp extract_packet(buffer, sync_size, header_size, payload_size) do
    total_size = sync_size + header_size + payload_size

    if byte_size(buffer) >= total_size do
      <<packet::binary-size(total_size), remaining::binary>> = buffer
      {:ok, packet, remaining}
    else
      {:need_more, buffer}
    end
  end

  defp payload_size_from_header(header, state, header_size) do
    length_byte_offset = state.length_offset
    length_byte_size = div(state.length_bit_size, 8)

    if length_byte_offset + length_byte_size > header_size do
      {:error,
       "length field (offset #{length_byte_offset} + size #{length_byte_size}) extends beyond header (#{header_size} bytes)"}
    else
      <<_before::binary-size(length_byte_offset), length_bytes::binary-size(length_byte_size),
        _after::binary>> = header

      length_value = decode_length(length_bytes, state)
      payload_size = length_value * state.length_bytes_per_count + state.length_value_offset
      {:ok, payload_size}
    end
  end

  defp maybe_discard_leading(packet, state) do
    if state.discard_leading_bytes > 0 and byte_size(packet) > state.discard_leading_bytes do
      binary_part(
        packet,
        state.discard_leading_bytes,
        byte_size(packet) - state.discard_leading_bytes
      )
    else
      packet
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
  Returns :ccsds as this protocol is designed for CCSDS Space Packet Protocol.
  """
  def packet_format, do: :ccsds

  @doc """
  Encode outgoing packet with sync pattern and header.

  Builds header with length field, prepends sync pattern.
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

    # Build header
    # For CCSDS: we need to build the full 6-byte primary header
    # This is simplified - in reality, the header would be built by the
    # application layer (packet definition) and we'd just insert the length
    #
    # For now, we assume the length field is at the specified offset and
    # we'll pad the rest of the header with zeros
    header_before = String.duplicate(<<0>>, state.length_offset)
    header_after_size = state.header_length - state.length_offset - byte_size(length_bytes)
    header_after = String.duplicate(<<0>>, max(0, header_after_size))

    header = header_before <> length_bytes <> header_after

    # Build complete packet: [sync][header][payload]
    packet = state.sync_pattern <> header <> data

    {:ok, [packet], state}
  end
end
