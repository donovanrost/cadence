defmodule CadenceSimulator.TMFramePlanTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.TMFramePlan
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  test "planned tm frames encode identically to segmentation" do
    frame = %{format: :tm, frame_size: 32, scid: 11, vcid: 2, fecf: true}

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
        %{
          frame_size: frame.frame_size,
          scid: frame.scid,
          vcid: frame.vcid,
          ocf_length: 0,
          fecf: true
        },
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

  test "planned tm frames preserve multi-packet sequencing identically to segmentation" do
    frame = %{format: :tm, frame_size: 32, scid: 11, vcid: 2}

    packets = [
      <<0x08, 0x01, 0xC0, 0x01, 0x00, 0x09, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>,
      <<0x08, 0x01, 0xC0, 0x02, 0x00, 0x0B, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22>>
    ]

    {:ok, segmentation_state} = Segmentation.init(mcfc: 7, vcfc: 7)

    {direct_outputs, next_segmentation_state} =
      Enum.reduce(packets, {[], segmentation_state}, fn packet, {outputs_acc, acc_state} ->
        {:ok, direct_output, next_state} =
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
            acc_state,
            []
          )

        {[direct_output | outputs_acc], next_state}
      end)

    {plans, cache} =
      Enum.reduce(packets, {[], %{}}, fn packet, {plans_acc, cache} ->
        {:ok, packet_plans, next_cache} = TMFramePlan.plan(packet, frame, cache)
        {plans_acc ++ packet_plans, next_cache}
      end)

    {planned_output, output_bytes, next_plan_state} =
      TMFramePlan.encode_many(plans, frame, %{mcfc: 7, vcfc: 7, idle_padding_cache: cache})

    direct_output = direct_outputs |> Enum.reverse() |> IO.iodata_to_binary()

    assert IO.iodata_to_binary(planned_output) == direct_output
    assert output_bytes == byte_size(direct_output)
    assert next_plan_state.mcfc == next_segmentation_state.mcfc
    assert next_plan_state.vcfc == next_segmentation_state.vcfc
  end
end
