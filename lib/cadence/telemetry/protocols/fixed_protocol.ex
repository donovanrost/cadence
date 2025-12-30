defmodule Cadence.Telemetry.Protocols.FixedProtocol do
  @moduledoc """
  Fixed-length packet protocol.

  Delineates packets by extracting chunks of a fixed byte size. Simplest
  protocol type, useful for telemetry streams with constant packet sizes.

  ## COSMOS Parameters

  Based on OpenC3 COSMOS FixedProtocol:

  - `packet_size` - Fixed packet length in bytes (required)
  - `sync_pattern` - Optional sync pattern before each packet (default: nil)
  - `fill_sync_pattern` - Include sync in returned packet (default: false)
  - `discard_leading_bytes` - Bytes to discard from each packet (default: 0)

  ## Examples

      # Simple 128-byte fixed packets
      FixedProtocol.new(
        packet_size: 128
      )

      # Fixed size with sync pattern
      FixedProtocol.new(
        packet_size: 256,
        sync_pattern: <<0xAA, 0xBB>>,
        fill_sync_pattern: true
      )

      # Fixed size, discard header
      FixedProtocol.new(
        packet_size: 100,
        discard_leading_bytes: 4  # Skip 4-byte header
      )

  ## Read Flow

  1. Optionally search for sync pattern
  2. Extract packet_size bytes
  3. Optionally discard leading bytes
  4. Continue extracting more packets or buffer if incomplete

  ## Write Flow

  1. Validate data is correct size
  2. Optionally prepend sync pattern
  3. Return framed packet
  """

  use Cadence.Telemetry.Protocol

  defstruct [
    :packet_size,
    :sync_pattern,
    :fill_sync_pattern,
    :discard_leading_bytes,
    buffer: <<>>,
    packets_extracted: 0
  ]

  @doc """
  Create new FixedProtocol instance.

  ## Options

  See moduledoc for parameter descriptions.
  """
  def new(opts \\ []) do
    packet_size = Keyword.fetch!(opts, :packet_size)

    unless is_integer(packet_size) and packet_size > 0 do
      raise ArgumentError, "packet_size must be a positive integer"
    end

    discard = Keyword.get(opts, :discard_leading_bytes, 0)

    if discard >= packet_size do
      raise ArgumentError,
            "discard_leading_bytes (#{discard}) must be less than packet_size (#{packet_size})"
    end

    %__MODULE__{
      packet_size: packet_size,
      sync_pattern: Keyword.get(opts, :sync_pattern),
      fill_sync_pattern: Keyword.get(opts, :fill_sync_pattern, false),
      discard_leading_bytes: discard
    }
  end

  @doc """
  Extract packets from incoming data stream.

  Extracts fixed-size chunks from buffer.
  Returns :stop when more data needed.
  """
  def read_data(data, state) when is_binary(data) do
    new_buffer = state.buffer <> data
    extract_packets(new_buffer, state, [])
  end

  # Recursive packet extraction
  defp extract_packets(buffer, state, acc) do
    case locate_sync(buffer, state) do
      {:ok, synced_buffer, sync_offset} ->
        case extract_packets_after_sync(synced_buffer, sync_offset, state) do
          {:emit, packet, remaining, new_state} ->
            extract_packets(remaining, new_state, [packet | acc])

          {:need_more, keep} ->
            return_packets(acc, %{state | buffer: keep})
        end

      {:need_more, keep} ->
        return_packets(acc, %{state | buffer: keep})
    end
  end

  # Continue extraction after sync pattern found (or no sync configured)
  defp extract_packets_after_sync(buffer, sync_offset, state) do
    # Calculate total bytes needed
    total_needed = sync_offset + state.packet_size

    # Check if we have enough data for a complete packet
    if byte_size(buffer) >= total_needed do
      # Extract fixed-size packet
      <<packet::binary-size(total_needed), remaining::binary>> = buffer

      # Optionally discard leading bytes
      packet = maybe_discard_leading(packet, sync_offset, total_needed, state)

      new_state = %{state | packets_extracted: state.packets_extracted + 1}

      {:emit, packet, remaining, new_state}
    else
      # Need more data
      {:need_more, buffer}
    end
  end

  defp locate_sync(buffer, %{sync_pattern: nil}), do: {:ok, buffer, 0}

  defp locate_sync(buffer, %{sync_pattern: sync_pattern} = state) do
    case find_sync_pattern(buffer, sync_pattern) do
      {:ok, offset} ->
        sync_len = byte_size(sync_pattern)

        if state.fill_sync_pattern do
          synced_buffer = binary_part(buffer, offset, byte_size(buffer) - offset)
          {:ok, synced_buffer, sync_len}
        else
          <<_skip::binary-size(offset), _sync::binary-size(sync_len), rest::binary>> = buffer
          {:ok, rest, 0}
        end

      :not_found ->
        keep_tail(buffer, sync_pattern)
    end
  end

  defp keep_tail(buffer, sync_pattern) do
    keep_bytes = max(0, byte_size(sync_pattern) - 1)

    keep =
      if byte_size(buffer) > keep_bytes do
        binary_part(buffer, byte_size(buffer) - keep_bytes, keep_bytes)
      else
        buffer
      end

    {:need_more, keep}
  end

  defp maybe_discard_leading(packet, sync_offset, total_needed, state) do
    if state.discard_leading_bytes > 0 do
      discard_offset = sync_offset + state.discard_leading_bytes
      keep_size = total_needed - discard_offset

      if keep_size > 0 do
        binary_part(packet, discard_offset, keep_size)
      else
        <<>>
      end
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

  # Find sync pattern in buffer
  defp find_sync_pattern(buffer, pattern) do
    case :binary.match(buffer, pattern) do
      {offset, _length} -> {:ok, offset}
      :nomatch -> :not_found
    end
  end

  @doc """
  Encode outgoing packet.

  Validates packet size and optionally prepends sync pattern.
  """
  def write_data(data, state) do
    # Validate packet size
    if byte_size(data) != state.packet_size do
      {:disconnect,
       "packet size mismatch: expected #{state.packet_size} bytes, got #{byte_size(data)} bytes"}
    else
      # Build packet: [optional sync][data]
      packet =
        if state.sync_pattern do
          state.sync_pattern <> data
        else
          data
        end

      {:ok, [packet], state}
    end
  end
end
