defmodule Cadence.CCSDS.SDLP.TM.Segmentation do
  @moduledoc """
  TM profile segmentation service.
  """

  @behaviour Cadence.CCSDS.SDLP.Segmentation

  alias Cadence.CCSDS.Core.{LinkFrame, SDUOctets}

  @primary_header_size 6
  @min_idle_packet_size @primary_header_size + 1
  @idle_apid 0x7FF

  @impl true
  def init(opts) do
    {:ok,
     %{
       mcfc: Keyword.get(opts, :mcfc, 0),
       vcfc: Keyword.get(opts, :vcfc, 0)
     }}
  end

  @impl true
  def segment(%SDUOctets{profile: :tm} = sdu, ctx, state) do
    frame_size = Map.fetch!(ctx, :frame_size)
    scid = sdu.scid || Map.get(ctx, :scid, 0)
    vcid = sdu.vcid || Map.get(ctx, :vcid, 0)

    with {:ok, ocf, ocf_len} <- normalize_ocf(ctx),
         max_payload when max_payload > 0 <- frame_size - @primary_header_size - ocf_len do
      ocf_flag = if ocf_len > 0, do: 1, else: 0
      {frames, next_state} = build_frames(sdu, scid, vcid, max_payload, ocf, ocf_flag, state)
      {:ok, Enum.reverse(frames), next_state}
    else
      {:error, reason} -> {:error, reason, state}
      _ -> {:error, :frame_size_too_small, state}
    end
  end

  def segment(_sdu, _ctx, state), do: {:error, :invalid_profile, state}

  defp split_segments(packet, max_payload) do
    if byte_size(packet) <= max_payload do
      [packet]
    else
      do_split_segments(packet, max_payload, [])
    end
  end

  defp do_split_segments(<<>>, _max_payload, acc), do: Enum.reverse(acc)

  defp do_split_segments(packet, max_payload, acc) when byte_size(packet) > max_payload do
    <<chunk::binary-size(max_payload), rest::binary>> = packet
    do_split_segments(rest, max_payload, [chunk | acc])
  end

  defp do_split_segments(packet, _max_payload, acc) do
    Enum.reverse([packet | acc])
  end

  defp build_frames(sdu, scid, vcid, max_payload, ocf, ocf_flag, state) do
    segments = split_segments(sdu.octets, max_payload)
    last_index = length(segments) - 1
    frame_ctx = %{scid: scid, vcid: vcid, ocf: ocf, ocf_flag: ocf_flag, timestamp: sdu.timestamp}

    Enum.reduce(Enum.with_index(segments), {[], state}, fn {segment, index}, {acc, st} ->
      frame = build_frame(segment, index, last_index, max_payload, frame_ctx, st)

      next = %{st | mcfc: increment_counter(st.mcfc), vcfc: increment_counter(st.vcfc)}
      {[frame | acc], next}
    end)
  end

  defp build_frame(
         segment,
         index,
         last_index,
         max_payload,
         %{scid: scid, vcid: vcid, ocf: ocf, ocf_flag: ocf_flag, timestamp: timestamp},
         st
       ) do
    fhp = if index == 0, do: 0, else: 2047
    payload = build_payload(segment, index, last_index, max_payload)

    %LinkFrame{
      profile: :tm,
      scid: scid,
      vcid: vcid,
      map_id: nil,
      frame_seq: st.vcfc,
      payload_octets: payload,
      quality: :good,
      ocf: ocf,
      timestamp: timestamp,
      meta: %{
        mcfc: st.mcfc,
        vcfc: st.vcfc,
        fhp: fhp,
        ocf_flag: ocf_flag,
        secondary_header_flag: 0,
        sync_flag: 0,
        packet_order_flag: 0,
        segment_length_id: 3
      }
    }
  end

  defp build_payload(segment, index, last_index, max_payload) when index == last_index do
    padding_size = max_payload - byte_size(segment)
    segment <> build_idle_padding(padding_size)
  end

  defp build_payload(segment, _index, _last_index, _max_payload), do: segment

  defp build_idle_padding(0), do: <<>>

  defp build_idle_padding(padding_size) when padding_size < @min_idle_packet_size do
    raise ArgumentError,
          "TM frame padding #{padding_size} bytes is too small for an idle packet"
  end

  defp build_idle_padding(padding_size) do
    build_idle_packet(padding_size)
  end

  defp build_idle_packet(size) do
    payload_size = size - @primary_header_size
    packet_length = payload_size - 1
    payload = :binary.copy(<<0>>, payload_size)

    <<
      0::3,
      0::1,
      0::1,
      @idle_apid::11,
      3::2,
      0::14,
      packet_length::16,
      payload::binary
    >>
  end

  defp increment_counter(value), do: rem(value + 1, 256)

  defp normalize_ocf(ctx) do
    case Map.get(ctx, :ocf) do
      nil ->
        {:ok, nil, 0}

      ocf when is_binary(ocf) ->
        ocf_len = Map.get(ctx, :ocf_length, byte_size(ocf))

        if ocf_len == byte_size(ocf) do
          {:ok, ocf, ocf_len}
        else
          {:error, :invalid_ocf_length}
        end

      _ ->
        {:error, :invalid_ocf}
    end
  end
end
