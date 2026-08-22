defmodule Cadence.CCSDS.TC.Segmentation do
  @moduledoc """
  TC transfer frame segmentation service.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}
  alias Cadence.CCSDS.FrameErrorControl

  @primary_header_size 5

  @impl true
  def init(opts) do
    {:ok,
     %{
       frame_seq: Keyword.get(opts, :frame_seq, 0)
     }}
  end

  @impl true
  def segment(%SDUOctets{profile: :tc} = sdu, ctx, state) do
    with {:ok, frame_ctx} <- build_frame_context(sdu, ctx),
         :ok <- validate_payload(sdu.octets, frame_ctx),
         {:ok, segments} <- split_segments(sdu.octets, frame_ctx) do
      {frames, next_state} = build_frames(segments, sdu.timestamp, frame_ctx, state)
      {:ok, frames, next_state}
    else
      {:error, reason} -> {:error, reason, state}
    end
  rescue
    KeyError ->
      {:error, :missing_frame_size, state}
  end

  def segment(_sdu, _ctx, state), do: {:error, :invalid_profile, state}

  defp build_frame_context(%SDUOctets{} = sdu, ctx) do
    frame_size = Map.fetch!(ctx, :frame_size)
    segment_header_flag = Map.get(ctx, :segment_header_flag, 0)
    bypass_flag = Map.get(ctx, :bypass_flag, 0)
    control_command_flag = Map.get(ctx, :control_command_flag, 0)
    fecf? = Map.get(ctx, :fecf, false)
    segment_header_size = if segment_header_flag == 1, do: 1, else: 0

    max_payload =
      frame_size - @primary_header_size - segment_header_size - fecf_length_bytes(fecf?)

    map_id = sdu.map_id || Map.get(ctx, :map_id, 0)

    with :ok <- validate_fecf_presence(fecf?),
         :ok <- validate_flag(segment_header_flag, :segment_header_flag),
         :ok <- validate_flag(bypass_flag, :bypass_flag),
         :ok <- validate_flag(control_command_flag, :control_command_flag),
         :ok <- validate_frame_type(bypass_flag, control_command_flag),
         :ok <-
           validate_segment_header_for_frame_type(
             segment_header_flag,
             control_command_flag
           ),
         :ok <- validate_map_id(map_id, segment_header_flag),
         :ok <- validate_max_payload(max_payload) do
      {:ok,
       %{
         scid: sdu.scid || Map.get(ctx, :scid, 0),
         vcid: sdu.vcid || Map.get(ctx, :vcid, 0),
         map_id: if(segment_header_flag == 1, do: map_id),
         max_payload: max_payload,
         bypass_flag: bypass_flag,
         control_command_flag: control_command_flag,
         fecf: fecf?,
         segment_header_flag: segment_header_flag,
         spare: Map.get(ctx, :spare, 0)
       }}
    end
  end

  defp validate_payload(<<>>, _frame_ctx), do: {:error, :empty_sdu}

  defp validate_payload(payload, %{segment_header_flag: 0, max_payload: max_payload})
       when byte_size(payload) > max_payload do
    {:error, :segment_header_required}
  end

  defp validate_payload(_payload, _frame_ctx), do: :ok

  defp split_segments(packet, %{max_payload: max_payload}) do
    {:ok, do_split_segments(packet, max_payload, [])}
  end

  defp do_split_segments(<<>>, _max_payload, acc), do: Enum.reverse(acc)

  defp do_split_segments(packet, max_payload, acc) when byte_size(packet) > max_payload do
    <<chunk::binary-size(^max_payload), rest::binary>> = packet
    do_split_segments(rest, max_payload, [chunk | acc])
  end

  defp do_split_segments(packet, _max_payload, acc) do
    Enum.reverse([packet | acc])
  end

  defp build_frames(segments, timestamp, frame_ctx, state) do
    segment_count = length(segments)

    segments
    |> Enum.with_index()
    |> Enum.reduce({[], state}, fn {segment, index}, {acc, current_state} ->
      sequence_flag = sequence_flag(index, segment_count, frame_ctx.segment_header_flag)
      frame = build_frame(segment, sequence_flag, timestamp, frame_ctx, current_state)
      {[frame | acc], increment_state(current_state, frame_ctx.bypass_flag)}
    end)
    |> then(fn {frames, next_state} -> {Enum.reverse(frames), next_state} end)
  end

  defp build_frame(segment, sequence_flag, timestamp, frame_ctx, state) do
    %LinkFrame{
      profile: :tc,
      scid: frame_ctx.scid,
      vcid: frame_ctx.vcid,
      map_id: frame_ctx.map_id,
      frame_seq: if(frame_ctx.bypass_flag == 1, do: 0, else: state.frame_seq),
      payload_octets: segment,
      quality: :good,
      ocf: nil,
      timestamp: timestamp,
      meta: %{
        bypass_flag: frame_ctx.bypass_flag,
        control_command_flag: frame_ctx.control_command_flag,
        segment_header_flag: frame_ctx.segment_header_flag,
        sequence_flag: sequence_flag,
        spare: frame_ctx.spare,
        fecf_present: frame_ctx.fecf
      }
    }
  end

  defp sequence_flag(_index, _count, 0), do: nil
  defp sequence_flag(_index, 1, 1), do: :unsegmented
  defp sequence_flag(0, _count, 1), do: :first
  defp sequence_flag(index, count, 1) when index == count - 1, do: :last
  defp sequence_flag(_index, _count, 1), do: :continuation

  defp increment_state(state, 1), do: state

  defp increment_state(state, 0) do
    %{state | frame_seq: increment_counter(state.frame_seq)}
  end

  defp increment_counter(value), do: rem(value + 1, 256)

  defp validate_flag(value, _field) when value in [0, 1], do: :ok
  defp validate_flag(value, field), do: {:error, {:invalid_flag, field, value}}

  defp validate_frame_type(0, 1), do: {:error, :reserved_frame_type}
  defp validate_frame_type(_bypass_flag, _control_command_flag), do: :ok

  defp validate_segment_header_for_frame_type(1, 1),
    do: {:error, :segment_header_forbidden_on_control_command}

  defp validate_segment_header_for_frame_type(_segment_header_flag, _control_command_flag),
    do: :ok

  defp validate_map_id(_map_id, 0), do: :ok

  defp validate_map_id(map_id, 1)
       when is_integer(map_id) and map_id >= 0 and map_id <= 63,
       do: :ok

  defp validate_map_id(map_id, 1), do: {:error, {:invalid_map_id, map_id}}

  defp validate_max_payload(max_payload) when max_payload > 0, do: :ok
  defp validate_max_payload(_max_payload), do: {:error, :frame_size_too_small}

  defp fecf_length_bytes(true), do: FrameErrorControl.size()
  defp fecf_length_bytes(false), do: 0
  defp fecf_length_bytes(_other), do: 0

  defp validate_fecf_presence(value) when is_boolean(value), do: :ok
  defp validate_fecf_presence(value), do: {:error, {:invalid_fecf_presence, value}}
end
