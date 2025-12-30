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
    case locate_sync(buffer, state) do
      {:ok, synced_buffer, sync_data} ->
        case extract_packets_after_sync(synced_buffer, sync_data, state) do
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
  defp extract_packets_after_sync(buffer, sync_data, state) do
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

        {:emit, packet, remaining, new_state}

      :not_found ->
        buffer_to_keep = restore_sync(sync_data, buffer)
        {:need_more, buffer_to_keep}
    end
  end

  defp locate_sync(buffer, %{sync_pattern: nil}), do: {:ok, buffer, <<>>}

  defp locate_sync(buffer, %{sync_pattern: sync_pattern} = state) do
    case find_sync_pattern(buffer, sync_pattern) do
      {:ok, offset} ->
        sync_len = byte_size(sync_pattern)
        <<_skip::binary-size(offset), sync::binary-size(sync_len), rest::binary>> = buffer
        sync_data = if state.fill_sync_pattern, do: sync, else: <<>>
        {:ok, rest, sync_data}

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

  defp restore_sync(<<>>, buffer), do: buffer
  defp restore_sync(sync_data, buffer), do: sync_data <> buffer

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
