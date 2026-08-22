defmodule Cadence.CCSDS.Transport.COP1.FARMTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Transport.COP1.FARM

  test "ingest updates report value and vcid" do
    {:ok, farm} = FARM.init(vcid: 1)
    {:ok, updated} = FARM.ingest(farm, %{frame_seq: 42, vcid: 5})

    assert updated.report_value == 42
    assert updated.vcid == 5
  end

  test "encode_clcw reflects FARM state" do
    {:ok, farm} = FARM.init(vcid: 3)
    {:ok, updated} = FARM.ingest(farm, 7)
    assert {:ok, ocf} = FARM.encode_clcw(updated)
    assert byte_size(ocf) == 4
  end
end
