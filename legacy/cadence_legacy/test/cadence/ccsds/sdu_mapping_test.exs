defmodule Cadence.CCSDS.SDU.MappingTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.SDU.Mapping

  test "fetch returns exact match" do
    mapping = Mapping.new(%{{1, 2, nil, :downlink} => :space_packet})

    assert {:ok, :space_packet} = Mapping.fetch(mapping, 1, 2, nil, :downlink)
  end

  test "fetch falls back to map_id nil" do
    mapping = Mapping.new(%{{1, 2, nil, :downlink} => :encap})

    assert {:ok, :encap} = Mapping.fetch(mapping, 1, 2, 7, :downlink)
  end

  test "fetch falls back to default" do
    mapping = Mapping.new(%{}, :space_packet)

    assert {:ok, :space_packet} = Mapping.fetch(mapping, 99, 1, nil, :downlink)
  end
end
