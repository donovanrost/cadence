defmodule Cadence.CCSDS.SDLP.AOS.FrameHeaderErrorControlTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDLP.AOS.FrameHeaderErrorControl

  test "matches independently generated RS(10,6) vectors" do
    assert {:ok, 0x94DC} = FrameHeaderErrorControl.encode(0x1234, 0x56)
    assert {:ok, 0x457C} = FrameHeaderErrorControl.encode(0x369C, 0xFA)
  end

  test "corrects up to two four-bit symbols and rejects larger corruption" do
    assert {:ok, %{protected_header: 0x1234, signaling: 0x56, status: :corrected}} =
             FrameHeaderErrorControl.decode(0x1211, 0x56, 0x94DC)

    assert {:ok, %{protected_header: 0x1234, signaling: 0x56, status: :corrected}} =
             FrameHeaderErrorControl.decode(0x1234, 0xAA, 0x94DC)

    assert {:error, {:uncorrectable_aos_frame_header, _syndrome}} =
             FrameHeaderErrorControl.decode(0x1230, 0x00, 0x94DC)
  end
end
