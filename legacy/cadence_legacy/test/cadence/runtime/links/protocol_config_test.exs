defmodule Cadence.Runtime.Links.ProtocolConfigTest do
  use Cadence.PureCase, async: true

  alias Cadence.CCSDS.SDU.Mapping
  alias Cadence.Runtime.Links.ProtocolConfig

  test "deep merges overrides and ignores nil" do
    defaults = %{
      "cop1" => %{"mode" => "fop", "window_size" => 4},
      "sdlp" => %{"default_sdu_type" => "space_packet", "uplink_vcid" => 0}
    }

    overrides = %{
      "cop1" => %{"window_size" => 8},
      "sdlp" => %{"default_sdu_type" => nil, "uplink_vcid" => 2}
    }

    merged = ProtocolConfig.effective_raw_config(defaults, overrides)

    assert get_in(merged, ["cop1", "mode"]) == "fop"
    assert get_in(merged, ["cop1", "window_size"]) == 8
    assert get_in(merged, ["sdlp", "default_sdu_type"]) == "space_packet"
    assert get_in(merged, ["sdlp", "uplink_vcid"]) == 2
  end

  test "effective config drops transport_id" do
    defaults = %{
      "cop1" => %{"mode" => "fop"},
      "transport_id" => "transport-legacy"
    }

    overrides = %{
      :transport_id => "transport-override"
    }

    effective = ProtocolConfig.effective_config(defaults, overrides)

    refute Map.has_key?(effective, :transport_id)
    refute Map.has_key?(effective, "transport_id")
  end

  test "binds scid for scid-less SDU mappings" do
    defaults = %{
      "framing" => "sdlp",
      "sdlp" => %{
        "framing" => "sdlp",
        "profile" => "tm",
        "sdu_mapping" => [
          %{"vcid" => 0, "direction" => "downlink", "type" => "space_packet"}
        ]
      }
    }

    effective = ProtocolConfig.effective_config(defaults, %{}, scid: 42)

    assert {:ok, %{mapping: mapping}} = effective.sdlp
    assert {:ok, :space_packet} = Mapping.fetch(mapping, 42, 0, nil, :downlink)
  end
end
