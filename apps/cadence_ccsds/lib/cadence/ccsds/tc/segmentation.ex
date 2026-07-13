defmodule Cadence.CCSDS.TC.Segmentation do
  @moduledoc """
  TC transfer frame segmentation service.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}

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
    frame_size = Map.fetch!(ctx, :frame_size)
    scid = sdu.scid || Map.get(ctx, :scid, 0)
    vcid = sdu.vcid || Map.get(ctx, :vcid, 0)
    max_payload = frame_size - @primary_header_size

    if max_payload <= 0 do
      {:error, :frame_size_too_small, state}
    else
      {frames, next_state} = build_frames(sdu, scid, vcid, max_payload, ctx, state)
      {:ok, Enum.reverse(frames), next_state}
    end
  rescue
    KeyError ->
      {:error, :missing_frame_size, state}
  end

  def segment(_sdu, _ctx, state), do: {:error, :invalid_profile, state}

  defp build_frames(%SDUOctets{} = sdu, scid, vcid, max_payload, ctx, state) do
    segments = split_segments(sdu.octets, max_payload)

    Enum.reduce(segments, {[], state}, fn segment, {acc, st} ->
      payload = pad_payload(segment, max_payload)
      frame = build_frame(payload, scid, vcid, sdu.timestamp, ctx, st)
      next = %{st | frame_seq: increment_counter(st.frame_seq)}
      {[frame | acc], next}
    end)
  end

  defp split_segments(packet, max_payload) do
    if byte_size(packet) <= max_payload do
      [packet]
    else
      do_split_segments(packet, max_payload, [])
    end
  end

  defp do_split_segments(<<>>, _max_payload, acc), do: Enum.reverse(acc)

  defp do_split_segments(packet, max_payload, acc) when byte_size(packet) > max_payload do
    <<chunk::binary-size(^max_payload), rest::binary>> = packet
    do_split_segments(rest, max_payload, [chunk | acc])
  end

  defp do_split_segments(packet, _max_payload, acc) do
    Enum.reverse([packet | acc])
  end

  defp pad_payload(segment, max_payload) do
    padding_size = max_payload - byte_size(segment)

    if padding_size > 0 do
      segment <> :binary.copy(<<0>>, padding_size)
    else
      segment
    end
  end

  defp build_frame(segment, scid, vcid, timestamp, ctx, state) do
    %LinkFrame{
      profile: :tc,
      scid: scid,
      vcid: vcid,
      map_id: nil,
      frame_seq: state.frame_seq,
      payload_octets: segment,
      quality: :good,
      ocf: nil,
      timestamp: timestamp,
      meta: %{
        bypass_flag: Map.get(ctx, :bypass_flag, 0),
        control_command_flag: Map.get(ctx, :control_command_flag, 0),
        segment_header_flag: Map.get(ctx, :segment_header_flag, 0)
      }
    }
  end

  defp increment_counter(value), do: rem(value + 1, 256)
end
