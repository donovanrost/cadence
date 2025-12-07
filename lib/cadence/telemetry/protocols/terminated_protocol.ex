defmodule Cadence.Telemetry.Protocols.TerminatedProtocol do
  @moduledoc """
  Terminated packet protocol with configurable delimiter.

  Delineates packets by searching for a terminator sequence. Common for
  text-based protocols or simple binary protocols with known delimiters.

  ## COSMOS Parameters

  Based on OpenC3 COSMOS TerminatedProtocol:

  - `terminator` - Binary termination sequence (required)
  - `strip_terminator` - Remove terminator from returned packets (default: true)
  - `sync_pattern` - Optional sync pattern before each packet (default: nil)
  - `fill_sync_pattern` - Include sync in returned packet (default: false)

  ## Examples

      # Newline-terminated text protocol
      TerminatedProtocol.new(
        terminator: "\n"
      )

      # CRLF-terminated
      TerminatedProtocol.new(
        terminator: "\r\n",
        strip_terminator: true
      )

      # Binary protocol with custom delimiter
      TerminatedProtocol.new(
        terminator: <<0xFF, 0xFF>>,
        strip_terminator: false
      )

      # With sync pattern
      TerminatedProtocol.new(
        sync_pattern: <<0xAA, 0xAA>>,
        terminator: <<0x00>>,
        fill_sync_pattern: true
      )

  ## Read Flow

  1. Optionally search for sync pattern
  2. Search for terminator sequence
  3. Extract packet up to (and optionally including) terminator
  4. Continue extracting more packets or buffer if incomplete

  ## Write Flow

  1. Optionally prepend sync pattern
  2. Append terminator to data
  3. Return framed packet
  """

  use Cadence.Telemetry.Protocol

  defstruct [
    :terminator,
    :strip_terminator,
    :sync_pattern,
    :fill_sync_pattern,
    buffer: <<>>,
    packets_extracted: 0
  ]

  @doc """
  Create new TerminatedProtocol instance.

  ## Options

  See moduledoc for parameter descriptions.
  """
  def new(opts \\ []) do
    terminator = Keyword.fetch!(opts, :terminator)

    unless is_binary(terminator) and byte_size(terminator) > 0 do
      raise ArgumentError, "terminator must be a non-empty binary"
    end

    %__MODULE__{
      terminator: terminator,
      strip_terminator: Keyword.get(opts, :strip_terminator, true),
      sync_pattern: Keyword.get(opts, :sync_pattern),
      fill_sync_pattern: Keyword.get(opts, :fill_sync_pattern, false)
    }
  end

  @doc """
  Extract packets from incoming data stream.

  Searches for terminator, extracts complete packets.
  Returns :stop when more data needed.
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
          <<_skip::binary-size(offset), sync::binary-size(sync_len), rest::binary>> = buffer

          sync_data =
            if state.fill_sync_pattern do
              sync
            else
              <<>>
            end

          extract_packets_after_sync(rest, sync_data, state, acc)

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
      extract_packets_after_sync(buffer, <<>>, state, acc)
    end
  end

  # Continue extraction after sync pattern found (or no sync configured)
  defp extract_packets_after_sync(buffer, sync_data, state, acc) do
    # Search for terminator
    case find_terminator(buffer, state.terminator) do
      {:ok, term_offset} ->
        term_len = byte_size(state.terminator)

        # Extract packet data before terminator
        packet_data = binary_part(buffer, 0, term_offset)

        # Build complete packet
        packet =
          if state.strip_terminator do
            # Return packet without terminator
            sync_data <> packet_data
          else
            # Include terminator in packet
            <<_before::binary-size(term_offset), term::binary-size(term_len), _rest::binary>> =
              buffer

            sync_data <> packet_data <> term
          end

        # Calculate remaining buffer (always skip terminator from buffer)
        skip_bytes = term_offset + term_len
        remaining = binary_part(buffer, skip_bytes, byte_size(buffer) - skip_bytes)

        new_state = %{state | packets_extracted: state.packets_extracted + 1}

        # Continue extracting more packets
        extract_packets(remaining, new_state, [packet | acc])

      :not_found ->
        # No terminator found - buffer for more data
        # If we extracted sync data, restore it to buffer for next read
        buffer_to_keep =
          if byte_size(sync_data) > 0 do
            sync_data <> buffer
          else
            buffer
          end

        return_packets(acc, %{state | buffer: buffer_to_keep})
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

  # Find terminator in buffer
  defp find_terminator(buffer, terminator) do
    case :binary.match(buffer, terminator) do
      {offset, _length} -> {:ok, offset}
      :nomatch -> :not_found
    end
  end

  @doc """
  Encode outgoing packet with terminator.

  Appends terminator to data and optionally prepends sync pattern.
  """
  def write_data(data, state) do
    # Build packet: [optional sync][data][terminator]
    packet =
      if state.sync_pattern do
        state.sync_pattern <> data <> state.terminator
      else
        data <> state.terminator
      end

    {:ok, [packet], state}
  end
end
