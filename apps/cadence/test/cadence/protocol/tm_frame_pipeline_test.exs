defmodule Cadence.Protocol.TMFramePipelineTest do
  use Cadence.UnitCase, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias Cadence.Protocol.TMFramePipeline

  test "decodes a packet-carrying TM frame into reassembled space packets" do
    frame_size = 32
    packet = build_space_packet(42, 7, <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init([])

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, fecf: true},
        segmentation_state,
        []
      )

    {:ok, pipeline_state} = TMFramePipeline.init(default_sdu_type: :space_packet)

    assert {:ok, [decoded_packet], <<>>, _pipeline_state} =
             TMFramePipeline.decode_space_packets(
               encoded_frames,
               [frame_size: frame_size, fecf: true],
               pipeline_state
             )

    assert decoded_packet == packet
  end

  test "reports dropped invalid TM frames as detailed anomalies" do
    frame_size = 14
    frame = build_tm_single_frame(42, 1, <<0, 21>>, frame_size)
    invalid_frame = put_packet_order_flag(frame, 1)

    {:ok, pipeline_state} = TMFramePipeline.init(default_sdu_type: :space_packet)

    assert {:ok, [], [], [anomaly], <<>>, _pipeline_state} =
             TMFramePipeline.decode_sdu_octets_detailed(
               invalid_frame,
               [frame_size: frame_size, ocf_length: 0],
               pipeline_state
             )

    assert anomaly.anomaly_kind == :frame_decode_dropped
    assert anomaly.metadata.reason == :packet_order_flag_reserved
    assert anomaly.metadata.vcid == 2
    assert anomaly.raw_frame_offset_bytes == 0
  end

  defp build_space_packet(apid, sequence_count, payload) do
    packet_length = byte_size(payload) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      payload::binary
    >>
  end

  defp build_tm_single_frame(apid, sequence_count, payload, frame_size) do
    packet = build_space_packet(apid, sequence_count, payload)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init(vcfc: 1)

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, ocf_length: 0},
        segmentation_state,
        []
      )

    encoded_frames
  end

  defp put_packet_order_flag(
         <<version::2, scid::10, vcid::3, ocf_flag::1, mcfc::8, vcfc::8, sec_hdr_flag::1,
           sync_flag::1, _packet_order_flag::1, segment_length_id::2, fhp::11, rest::binary>>,
         packet_order_flag
       ) do
    <<
      version::2,
      scid::10,
      vcid::3,
      ocf_flag::1,
      mcfc::8,
      vcfc::8,
      sec_hdr_flag::1,
      sync_flag::1,
      packet_order_flag::1,
      segment_length_id::2,
      fhp::11,
      rest::binary
    >>
  end
end
