defmodule Cadence.SpacecraftType.SchemaTest do
  use ExUnit.Case, async: true

  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftType.Schema

  test "framing and catalog sections list only model-backed fields" do
    paths = Schema.sections() |> Enum.flat_map(& &1.fields) |> Enum.map(& &1.path)

    assert "frame_parameters.frame_size" in paths
    assert "catalog_revision_id" in paths
    assert "frame_parameters.fecf" in paths

    refute Enum.any?(
             paths,
             &String.contains?(&1, ["virtual_channel", "reed_solomon", "randomizer", "segment"])
           )
  end

  test "reads current values by path" do
    profile = %SpacecraftType{
      downlink_protocol: :aos,
      uplink_protocol: :tc,
      packet_protocol: :space_packet,
      frame_parameters: %{"frame_size" => 1115}
    }

    assert Schema.value(profile, "downlink_protocol") == "aos"
    assert Schema.value(profile, "frame_parameters.frame_size") == 1115
    assert Schema.value(profile, "frame_parameters.ocf_length") == nil
    assert Schema.value(profile, "catalog_revision_id") == nil
  end
end
