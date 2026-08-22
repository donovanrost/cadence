defmodule Cadence.CCSDS.USLPTFDFTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDLP.USLP.TFDF

  test "encodes the fixed-length packet header and first header pointer" do
    assert {:ok, <<0::3, 0::5, 42::16>>} =
             TFDF.encode(:packets_spanning_frames, TFDF.upid(:packets), 42)

    assert {:ok, %{construction_rule: :packets_spanning_frames, upid: 0, pointer: 42}, "data"} =
             TFDF.decode(<<0::3, 0::5, 42::16, "data">>)
  end

  test "encodes every variable-length construction rule without a pointer" do
    for {rule, encoded} <- [
          octet_stream: 3,
          start_segment: 4,
          continue_segment: 5,
          last_segment: 6,
          unsegmented: 7
        ] do
      assert {:ok, <<^encoded::3, 5::5>>} = TFDF.encode(rule, 5, nil)
      assert :ok = TFDF.validate_for_frame_type(rule, :variable)
    end
  end

  test "rejects pointer and frame-type mismatches" do
    assert {:error, {:invalid_uslp_tfdf_pointer, :unsegmented, 0}} =
             TFDF.encode(:unsegmented, 5, 0)

    assert {:error, {:construction_rule_frame_type_mismatch, :unsegmented, :fixed}} =
             TFDF.validate_for_frame_type(:unsegmented, :fixed)
  end
end
