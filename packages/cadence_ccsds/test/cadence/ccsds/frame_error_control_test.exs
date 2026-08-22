defmodule Cadence.CCSDS.FrameErrorControlTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.FrameErrorControl

  test "calculates the standard CRC-16/CCITT-FALSE check value" do
    assert FrameErrorControl.calculate("123456789") == 0x29B1
    assert FrameErrorControl.encode("123456789") == <<0x29, 0xB1>>
  end

  test "appends, validates, and strips a FECF" do
    frame = <<0x01, 0x02, 0x03, 0x04>>
    encoded = FrameErrorControl.append(frame)

    assert byte_size(encoded) == byte_size(frame) + FrameErrorControl.size()
    assert {:ok, ^frame, 0x89C3} = FrameErrorControl.validate_and_strip(encoded)
  end

  test "rejects a corrupted frame" do
    encoded = FrameErrorControl.append(<<0x01, 0x02, 0x03, 0x04>>)
    <<first, rest::binary>> = encoded
    corrupted = <<Bitwise.bxor(first, 0x01), rest::binary>>

    assert {:error, {:invalid_fecf, expected, received}} =
             FrameErrorControl.validate_and_strip(corrupted)

    assert expected != received
  end

  test "rejects input too short to contain a FECF" do
    assert {:error, :frame_too_short_for_fecf} =
             FrameErrorControl.validate_and_strip(<<0x01>>)
  end
end
