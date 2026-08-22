defmodule Cadence.CCSDS.TC.SegmentHeaderTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.TC.SegmentHeader

  test "round trips every sequence flag" do
    flags = [:continuation, :first, :last, :unsegmented]

    Enum.each(flags, fn sequence_flag ->
      header = %SegmentHeader{sequence_flag: sequence_flag, map_id: 37}

      assert {:ok, encoded} = SegmentHeader.encode(header)
      assert byte_size(encoded) == 1
      assert {:ok, ^header, <<0xAA>>} = SegmentHeader.decode(encoded <> <<0xAA>>)
    end)
  end

  test "uses the CCSDS bit assignments" do
    assert {:ok, <<0::2, 1::6>>} =
             SegmentHeader.encode(%SegmentHeader{sequence_flag: :continuation, map_id: 1})

    assert {:ok, <<1::2, 2::6>>} =
             SegmentHeader.encode(%SegmentHeader{sequence_flag: :first, map_id: 2})

    assert {:ok, <<2::2, 3::6>>} =
             SegmentHeader.encode(%SegmentHeader{sequence_flag: :last, map_id: 3})

    assert {:ok, <<3::2, 4::6>>} =
             SegmentHeader.encode(%SegmentHeader{sequence_flag: :unsegmented, map_id: 4})
  end
end
