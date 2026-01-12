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

    max_payload = frame_size - @primary_header_size
    segments = split_segments(sdu.octets, max_payload)
    last_index = length(segments) - 1

    {frames, next_state} =
      Enum.reduce(Enum.with_index(segments), {[], state}, fn {segment, index}, {acc, st} ->
        fhp = if index == 0, do: 0, else: 2047

        payload =
          if index == last_index do
            padding_size = max_payload - byte_size(segment)
            segment <> build_idle_padding(padding_size)
          else
            segment
          end

        frame = %LinkFrame{
          profile: :tm,
          scid: scid,
          vcid: vcid,
          map_id: nil,
          frame_seq: st.vcfc,
          payload_octets: payload,
          quality: :good,
          ocf: nil,
          timestamp: sdu.timestamp,
          meta: %{
            mcfc: st.mcfc,
            vcfc: st.vcfc,
            fhp: fhp,
            ocf_flag: 0,
            secondary_header_flag: 0,
            sync_flag: 0,
            packet_order_flag: 0,
            segment_length_id: 3
          }
        }

        next = %{st | mcfc: increment_counter(st.mcfc), vcfc: increment_counter(st.vcfc)}
        {[frame | acc], next}
      end)

    {:ok, Enum.reverse(frames), next_state}
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
end
