defmodule Cadence.CCSDS.TC.Reassembly do
  @moduledoc """
  Stateful reassembly for CCSDS TC MAP service data units.

  Reassembly is isolated by spacecraft, virtual channel, and MAP identifier.
  Type-AD frame sequence numbers are checked modulo 256. Type-BD frames do not
  carry a usable sequence count, so their segment order is determined solely by
  arrival order and Segment Header flags.
  """

  @behaviour Cadence.CCSDS.SDLP.Reassembly

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}

  @default_max_sdu_octets 1_048_576

  @impl true
  def init(opts) do
    max_sdu_octets = Keyword.get(opts, :max_sdu_octets, @default_max_sdu_octets)

    if is_integer(max_sdu_octets) and max_sdu_octets > 0 do
      {:ok, %{buffers: %{}, max_sdu_octets: max_sdu_octets}}
    else
      raise ArgumentError, "max_sdu_octets must be a positive integer"
    end
  end

  @impl true
  def ingest(%LinkFrame{profile: :tc} = frame, ctx, state) do
    case Map.get(frame.meta, :segment_header_flag, 0) do
      0 ->
        {:ok, [build_sdu(frame.payload_octets, [frame.frame_seq], frame, ctx)], state}

      1 ->
        ingest_segment(frame, ctx, state)

      value ->
        {:error, {:invalid_segment_header_flag, value}, state}
    end
  end

  def ingest(_frame, _ctx, state), do: {:error, :invalid_profile, state}

  defp ingest_segment(%LinkFrame{} = frame, ctx, state) do
    key = {frame.scid, frame.vcid, frame.map_id}

    with :ok <- validate_map_id(frame.map_id),
         {:ok, sequence_flag} <- fetch_sequence_flag(frame) do
      handle_segment(sequence_flag, key, frame, ctx, state)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp handle_segment(:unsegmented, key, frame, ctx, state) do
    if Map.has_key?(state.buffers, key) do
      {:error, {:unexpected_unsegmented_sdu, key}, drop_buffer(state, key)}
    else
      sdu = build_sdu(frame.payload_octets, [frame.frame_seq], frame, ctx)
      {:ok, [sdu], state}
    end
  end

  defp handle_segment(:first, key, frame, _ctx, state) do
    if byte_size(frame.payload_octets) > state.max_sdu_octets do
      {:error, {:sdu_size_limit_exceeded, byte_size(frame.payload_octets), state.max_sdu_octets},
       drop_buffer(state, key)}
    else
      buffer = new_buffer(frame)
      next_state = put_buffer(state, key, buffer)

      if Map.has_key?(state.buffers, key) do
        {:error, {:reassembly_restarted, key}, next_state}
      else
        {:ok, [], next_state}
      end
    end
  end

  defp handle_segment(sequence_flag, key, frame, ctx, state)
       when sequence_flag in [:continuation, :last] do
    case Map.fetch(state.buffers, key) do
      :error ->
        {:error, {:unexpected_segment, sequence_flag, key}, state}

      {:ok, buffer} ->
        append_segment(sequence_flag, key, buffer, frame, ctx, state)
    end
  end

  defp append_segment(sequence_flag, key, buffer, frame, ctx, state) do
    with :ok <- validate_frame_sequence(buffer, frame),
         {:ok, next_buffer} <- append_payload(buffer, frame, state.max_sdu_octets) do
      complete_or_store(sequence_flag, key, next_buffer, frame, ctx, state)
    else
      {:error, reason} -> {:error, reason, drop_buffer(state, key)}
    end
  end

  defp complete_or_store(:continuation, key, buffer, _frame, _ctx, state) do
    {:ok, [], put_buffer(state, key, buffer)}
  end

  defp complete_or_store(:last, key, buffer, frame, ctx, state) do
    sdu = build_sdu(buffer.octets, buffer.source_frames, frame, ctx, buffer)
    {:ok, [sdu], drop_buffer(state, key)}
  end

  defp new_buffer(%LinkFrame{} = frame) do
    %{
      octets: frame.payload_octets,
      source_frames: [frame.frame_seq],
      last_frame_seq: frame.frame_seq,
      enforce_frame_sequence?: Map.get(frame.meta, :bypass_flag, 0) == 0,
      quality: frame.quality || :good,
      timestamp: frame.timestamp,
      meta: frame.meta
    }
  end

  defp append_payload(buffer, frame, max_sdu_octets) do
    octets = buffer.octets <> frame.payload_octets

    if byte_size(octets) <= max_sdu_octets do
      {:ok,
       %{
         buffer
         | octets: octets,
           source_frames: buffer.source_frames ++ [frame.frame_seq],
           last_frame_seq: frame.frame_seq,
           quality: merge_quality(buffer.quality, frame.quality)
       }}
    else
      {:error, {:sdu_size_limit_exceeded, byte_size(octets), max_sdu_octets}}
    end
  end

  defp validate_frame_sequence(%{enforce_frame_sequence?: false}, _frame), do: :ok

  defp validate_frame_sequence(buffer, frame) do
    expected = rem(buffer.last_frame_seq + 1, 256)

    cond do
      frame.frame_seq == expected ->
        :ok

      frame.frame_seq == buffer.last_frame_seq ->
        {:error, {:duplicate_frame, frame.frame_seq}}

      true ->
        {:error, {:unexpected_frame_sequence, frame.frame_seq, expected}}
    end
  end

  defp build_sdu(octets, source_frames, frame, ctx, buffer \\ nil) do
    %SDUOctets{
      profile: :tc,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: frame.map_id,
      direction: Map.get(ctx, :direction, :uplink),
      sdu_kind_hint: Map.get(ctx, :sdu_kind_hint),
      octets: octets,
      quality: buffer_value(buffer, :quality, frame.quality || :good),
      source_frames: source_frames,
      timestamp: buffer_value(buffer, :timestamp, frame.timestamp),
      meta:
        buffer_value(buffer, :meta, frame.meta)
        |> Map.put(:segment_count, length(source_frames))
    }
  end

  defp buffer_value(nil, _key, default), do: default
  defp buffer_value(buffer, key, _default), do: Map.fetch!(buffer, key)

  defp put_buffer(state, key, buffer) do
    %{state | buffers: Map.put(state.buffers, key, buffer)}
  end

  defp drop_buffer(state, key) do
    %{state | buffers: Map.delete(state.buffers, key)}
  end

  defp fetch_sequence_flag(%LinkFrame{} = frame) do
    case Map.fetch(frame.meta, :sequence_flag) do
      {:ok, sequence_flag}
      when sequence_flag in [:continuation, :first, :last, :unsegmented] ->
        {:ok, sequence_flag}

      {:ok, sequence_flag} ->
        {:error, {:invalid_sequence_flag, sequence_flag}}

      :error ->
        {:error, :missing_sequence_flag}
    end
  end

  defp validate_map_id(map_id)
       when is_integer(map_id) and map_id >= 0 and map_id <= 63,
       do: :ok

  defp validate_map_id(map_id), do: {:error, {:invalid_map_id, map_id}}

  defp merge_quality(:invalid, _quality), do: :invalid
  defp merge_quality(_quality, :invalid), do: :invalid
  defp merge_quality(:suspect, _quality), do: :suspect
  defp merge_quality(_quality, :suspect), do: :suspect
  defp merge_quality(_left, _right), do: :good
end
