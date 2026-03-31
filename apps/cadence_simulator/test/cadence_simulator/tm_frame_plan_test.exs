defmodule CadenceSimulator.TMFramePlanTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias CadenceSimulator.TMFramePlan

  test "planned tm frames encode identically to segmentation" do
    frame = %{format: :tm, frame_size: 32, scid: 11, vcid: 2}

    packet =
      <<0x08, 0x01, 0xC0, 0x01, 0x00, 0x09, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

    {:ok, segmentation_state} = Segmentation.init(mcfc: 7, vcfc: 7)

    {:ok, direct_output, next_segmentation_state} =
      Segmentation.segment_encode(
        %SDUOctets{
          profile: :tm,
          scid: frame.scid,
          vcid: frame.vcid,
          map_id: nil,
          direction: :downlink,
          sdu_kind_hint: :space_packet,
          octets: packet,
          quality: :good,
          source_frames: [],
          timestamp: nil,
          meta: %{}
        },
        %{frame_size: frame.frame_size, scid: frame.scid, vcid: frame.vcid, ocf_length: 0},
        segmentation_state,
        []
      )

    {:ok, plans, cache} = TMFramePlan.plan(packet, frame, %{})
    assert cache != %{}

    {planned_output, output_bytes, next_plan_state} =
      TMFramePlan.encode_many(plans, frame, %{mcfc: 7, vcfc: 7, idle_padding_cache: cache})

    assert IO.iodata_to_binary(planned_output) == direct_output
    assert output_bytes == byte_size(direct_output)
    assert next_plan_state.mcfc == next_segmentation_state.mcfc
    assert next_plan_state.vcfc == next_segmentation_state.vcfc
  end
end
