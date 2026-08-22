defmodule CCSDS.TC.TransferFrameTest do
  use ExUnit.Case, async: true

  alias CCSDS.TC.TransferFrame

  test "decodes TC frame header fields" do
    frame_size = 12
    payload = :binary.copy(<<0xAA>>, frame_size - 5)

    frame =
      <<
        0::2,
        0::1,
        0::1,
        0::2,
        42::10,
        5::6,
        frame_size - 1::10,
        77::8,
        payload::binary
      >>

    assert {:ok, [decoded], <<>>} = TransferFrame.decode(frame, frame_size: frame_size)
    assert decoded.scid == 42
    assert decoded.vcid == 5
    assert decoded.frame_seq == 77
    assert decoded.frame_length == frame_size - 1
    assert decoded.spare == 0
    assert decoded.payload == payload
  end

  test "encodes the standard primary-header layout without padding to the managed maximum" do
    maximum_frame_size = 12
    payload = <<0xAA, 0xBB, 0xCC>>

    frame = %TransferFrame{
      version: 0,
      bypass_flag: 1,
      control_command_flag: 0,
      scid: 42,
      vcid: 5,
      frame_length: nil,
      frame_seq: 77,
      spare: 0,
      payload: payload
    }

    assert {:ok, encoded} = TransferFrame.encode(frame, frame_size: maximum_frame_size)
    assert byte_size(encoded) == 8

    assert <<
             0::2,
             1::1,
             0::1,
             0::2,
             42::10,
             5::6,
             7::10,
             77::8,
             ^payload::binary
           >> = encoded

    assert {:ok, [decoded], <<>>} =
             TransferFrame.decode(encoded, frame_size: maximum_frame_size)

    assert decoded.bypass_flag == 1
    assert decoded.frame_seq == 77
    assert decoded.frame_length == 7
    assert decoded.payload == payload
  end

  test "includes, validates, and strips the managed FECF" do
    payload = <<0xAA, 0xBB, 0xCC>>

    frame = %TransferFrame{
      version: 0,
      bypass_flag: 0,
      control_command_flag: 0,
      spare: 0,
      scid: 42,
      vcid: 5,
      frame_seq: 77,
      payload: payload
    }

    assert {:ok, encoded} = TransferFrame.encode(frame, frame_size: 12, fecf: true)
    assert byte_size(encoded) == 10

    assert <<_prefix::22, 9::10, _rest::binary>> = encoded

    assert {:ok, [decoded], <<>>} =
             TransferFrame.decode(encoded, frame_size: 12, fecf: true)

    assert decoded.payload == payload
    assert is_integer(decoded.fecf)

    <<prefix::binary-size(5), byte, suffix::binary>> = encoded
    corrupted = prefix <> <<Bitwise.bxor(byte, 0x01)>> <> suffix

    assert {:error, {:invalid_fecf, expected, received}} =
             TransferFrame.decode(corrupted, frame_size: 12, fecf: true)

    assert expected != received
  end

  test "decodes concatenated variable-length frames and preserves an incomplete tail" do
    first = transfer_frame_bytes(1, <<1, 2>>)
    second = transfer_frame_bytes(2, <<3, 4, 5, 6>>)
    <<second_prefix::binary-size(4), second_rest::binary>> = second

    assert {:ok, [decoded_first], ^second_prefix} =
             TransferFrame.decode(first <> second_prefix, frame_size: 32)

    assert decoded_first.payload == <<1, 2>>

    assert {:ok, [decoded_second], <<>>} =
             TransferFrame.decode(second_prefix <> second_rest, frame_size: 32)

    assert decoded_second.payload == <<3, 4, 5, 6>>
  end

  test "rejects non-zero reserved spare bits" do
    frame =
      %TransferFrame{
        version: 0,
        bypass_flag: 0,
        control_command_flag: 0,
        spare: 1,
        scid: 1,
        vcid: 1,
        frame_seq: 1,
        payload: <<1>>
      }

    assert {:error, {:reserved_spare_not_zero, 1}} =
             TransferFrame.encode(frame, frame_size: 32)
  end

  defp transfer_frame_bytes(sequence, payload) do
    frame = %TransferFrame{
      version: 0,
      bypass_flag: 0,
      control_command_flag: 0,
      spare: 0,
      scid: 42,
      vcid: 5,
      frame_seq: sequence,
      payload: payload
    }

    {:ok, encoded} = TransferFrame.encode(frame, frame_size: 32)
    encoded
  end
end
