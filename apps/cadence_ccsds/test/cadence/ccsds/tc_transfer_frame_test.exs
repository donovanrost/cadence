defmodule Cadence.CCSDS.TC.TransferFrameTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.TC.TransferFrame

  test "decodes TC frame header fields" do
    frame_size = 12
    payload = :binary.copy(<<0xAA>>, frame_size - 5)

    frame =
      <<
        0::2,
        0::1,
        0::1,
        42::10,
        5::6,
        frame_size - 1::10,
        77::8,
        1::1,
        0::1,
        payload::binary
      >>

    assert {:ok, [decoded], <<>>} = TransferFrame.decode(frame, frame_size: frame_size)
    assert decoded.scid == 42
    assert decoded.vcid == 5
    assert decoded.frame_seq == 77
    assert decoded.frame_length == frame_size - 1
    assert decoded.segment_header_flag == 1
    assert decoded.payload == payload
  end

  test "encodes TC frame header fields" do
    frame_size = 12
    payload = :binary.copy(<<0xAA>>, frame_size - 5)

    frame = %TransferFrame{
      version: 0,
      bypass_flag: 1,
      control_command_flag: 0,
      scid: 42,
      vcid: 5,
      frame_length: nil,
      frame_seq: 77,
      segment_header_flag: 1,
      spare: 0,
      payload: payload
    }

    assert {:ok, encoded} = TransferFrame.encode(frame, frame_size: frame_size)
    assert {:ok, [decoded], <<>>} = TransferFrame.decode(encoded, frame_size: frame_size)
    assert decoded.bypass_flag == 1
    assert decoded.frame_seq == 77
    assert decoded.frame_length == frame_size - 1
    assert decoded.payload == payload
  end
end
