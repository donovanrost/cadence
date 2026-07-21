defmodule Cadence.CCSDS.TC.SegmentationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.TC.{FrameCodec, Segmentation}

  test "segments SDU octets with CCSDS sequence flags and MAP identity" do
    payload = <<1, 2, 3, 4, 5, 6, 7, 8, 9>>
    frame_size = 10

    sdu = %SDUOctets{
      profile: :tc,
      scid: 19,
      vcid: 3,
      map_id: 7,
      direction: :uplink,
      sdu_kind_hint: :command,
      octets: payload,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    assert {:ok, state} = Segmentation.init(frame_seq: 200)

    assert {:ok, frames, next_state} =
             Segmentation.segment(
               sdu,
               %{
                 frame_size: frame_size,
                 scid: 19,
                 vcid: 3,
                 bypass_flag: 0,
                 control_command_flag: 0,
                 segment_header_flag: 1
               },
               state
             )

    assert length(frames) == 3
    assert Enum.map(frames, & &1.frame_seq) == [200, 201, 202]
    assert Enum.map(frames, & &1.meta.sequence_flag) == [:first, :continuation, :last]
    assert Enum.map(frames, & &1.map_id) == [7, 7, 7]
    assert next_state.frame_seq == 203

    encoded_frames =
      Enum.map(frames, fn frame ->
        assert {:ok, encoded} = FrameCodec.encode(frame, frame_size: frame_size)
        encoded
      end)

    assert Enum.map(encoded_frames, &byte_size/1) == [10, 10, 7]

    assert {:ok, decoded_frames, <<>>} =
             FrameCodec.decode(
               IO.iodata_to_binary(encoded_frames),
               frame_size: frame_size,
               segment_header_flag: 1
             )

    assert Enum.map(decoded_frames, & &1.payload_octets) == [
             <<1, 2, 3, 4>>,
             <<5, 6, 7, 8>>,
             <<9>>
           ]

    assert Enum.map(decoded_frames, & &1.meta.sequence_flag) == [
             :first,
             :continuation,
             :last
           ]
  end

  test "rejects a multi-frame SDU when the managed VC omits segment headers" do
    sdu = sdu(<<1, 2, 3, 4, 5, 6>>, nil)
    assert {:ok, state} = Segmentation.init([])

    assert {:error, :segment_header_required, ^state} =
             Segmentation.segment(
               sdu,
               %{
                 frame_size: 10,
                 scid: 19,
                 vcid: 3,
                 segment_header_flag: 0
               },
               state
             )
  end

  test "marks a single MAP SDU as unsegmented" do
    sdu = sdu(<<1, 2, 3>>, 4)
    assert {:ok, state} = Segmentation.init([])

    assert {:ok, [frame], next_state} =
             Segmentation.segment(
               sdu,
               %{
                 frame_size: 10,
                 scid: 19,
                 vcid: 3,
                 segment_header_flag: 1
               },
               state
             )

    assert frame.map_id == 4
    assert frame.meta.sequence_flag == :unsegmented
    assert next_state.frame_seq == 1
  end

  defp sdu(payload, map_id) do
    %SDUOctets{
      profile: :tc,
      scid: 19,
      vcid: 3,
      map_id: map_id,
      direction: :uplink,
      sdu_kind_hint: :command,
      octets: payload,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }
  end
end
