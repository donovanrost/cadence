defmodule Cadence.CCSDS.TC.SegmentationTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.TC.{FrameCodec, Segmentation, TransferFrame}

  test "segments SDU octets into padded TC transfer frames" do
    payload = <<1, 2, 3, 4, 5, 6, 7, 8, 9>>
    frame_size = 10

    sdu = %SDUOctets{
      profile: :tc,
      scid: 19,
      vcid: 3,
      map_id: nil,
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
                 control_command_flag: 1,
                 segment_header_flag: 0
               },
               state
             )

    assert length(frames) == 2
    assert Enum.map(frames, & &1.frame_seq) == [200, 201]
    assert next_state.frame_seq == 202

    [first_frame, second_frame] = frames

    assert {:ok, encoded_first_frame} = FrameCodec.encode(first_frame, frame_size: frame_size)
    assert {:ok, encoded_second_frame} = FrameCodec.encode(second_frame, frame_size: frame_size)

    assert {:ok, [decoded_first_frame], <<>>} =
             TransferFrame.decode(encoded_first_frame, frame_size: frame_size)

    assert {:ok, [decoded_second_frame], <<>>} =
             TransferFrame.decode(encoded_second_frame, frame_size: frame_size)

    assert decoded_first_frame.scid == 19
    assert decoded_first_frame.vcid == 3
    assert decoded_first_frame.control_command_flag == 1
    assert byte_size(decoded_first_frame.payload) == frame_size - 5
    assert byte_size(decoded_second_frame.payload) == frame_size - 5
  end
end
