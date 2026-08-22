defmodule CCSDS.TC.ReassemblyTest do
  use ExUnit.Case, async: true

  alias CCSDS.Core.{LinkFrame, SDUOctets}
  alias CCSDS.TC.{FrameCodec, Reassembly, Segmentation}

  test "reassembles a multi-frame MAP SDU after a wire round trip" do
    payload = :binary.list_to_bin(Enum.to_list(1..17))
    sdu = sdu(payload, 12)

    assert {:ok, segmentation_state} = Segmentation.init(frame_seq: 254)

    assert {:ok, frames, _next_segmentation_state} =
             Segmentation.segment(
               sdu,
               %{
                 frame_size: 12,
                 bypass_flag: 0,
                 control_command_flag: 0,
                 segment_header_flag: 1
               },
               segmentation_state
             )

    wire =
      frames
      |> Enum.map(fn frame ->
        {:ok, encoded} = FrameCodec.encode(frame, frame_size: 12)
        encoded
      end)
      |> IO.iodata_to_binary()

    assert {:ok, decoded_frames, <<>>} =
             FrameCodec.decode(wire, frame_size: 12, segment_header_flag: 1)

    assert Enum.map(decoded_frames, & &1.frame_seq) == [254, 255, 0]
    assert {:ok, reassembly_state} = Reassembly.init([])

    {emitted, final_state} =
      Enum.reduce(decoded_frames, {[], reassembly_state}, fn frame, {sdus, state} ->
        assert {:ok, next_sdus, next_state} =
                 Reassembly.ingest(
                   frame,
                   %{direction: :uplink, sdu_kind_hint: :command},
                   state
                 )

        {sdus ++ next_sdus, next_state}
      end)

    assert final_state.buffers == %{}
    assert [%SDUOctets{} = reassembled] = emitted
    assert reassembled.octets == payload
    assert reassembled.map_id == 12
    assert reassembled.source_frames == [254, 255, 0]
    assert reassembled.meta.segment_count == 3
  end

  test "isolates interleaved reassembly by MAP ID" do
    assert {:ok, state} = Reassembly.init([])

    assert {:ok, [], state} =
             Reassembly.ingest(frame(:first, 1, 10, <<"A">>), %{}, state)

    assert {:ok, [], state} =
             Reassembly.ingest(frame(:first, 2, 40, <<"B">>), %{}, state)

    assert {:ok, [map_1_sdu], state} =
             Reassembly.ingest(frame(:last, 1, 11, <<"1">>), %{}, state)

    assert {:ok, [map_2_sdu], final_state} =
             Reassembly.ingest(frame(:last, 2, 41, <<"2">>), %{}, state)

    assert map_1_sdu.octets == <<"A1">>
    assert map_2_sdu.octets == <<"B2">>
    assert final_state.buffers == %{}
  end

  test "drops an assembly when a Type-AD frame is missing" do
    assert {:ok, state} = Reassembly.init([])

    assert {:ok, [], state} =
             Reassembly.ingest(frame(:first, 1, 10, <<"A">>), %{}, state)

    assert {:error, {:unexpected_frame_sequence, 12, 11}, final_state} =
             Reassembly.ingest(frame(:last, 1, 12, <<"B">>), %{}, state)

    assert final_state.buffers == %{}
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

  defp frame(sequence_flag, map_id, frame_seq, payload) do
    %LinkFrame{
      profile: :tc,
      scid: 19,
      vcid: 3,
      map_id: map_id,
      frame_seq: frame_seq,
      payload_octets: payload,
      quality: :good,
      ocf: nil,
      timestamp: nil,
      meta: %{
        bypass_flag: 0,
        control_command_flag: 0,
        segment_header_flag: 1,
        sequence_flag: sequence_flag
      }
    }
  end
end
