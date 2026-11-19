defmodule Cadence.Comms.StationRefsTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.GroundStation
  alias Cadence.Comms.StationRefs

  defp station(id, name, metadata),
    do: %GroundStation{ground_station_id: id, display_name: name, metadata: metadata}

  test "a provider ref resolves by id, code or provider station ref; nulls otherwise" do
    index =
      StationRefs.build([
        station("gs_1", "Fairbanks", %{
          "code" => "FAI",
          "provider_station_ref" => "earendil-fairbanks"
        }),
        station("gs_2", "Svalbard", %{"code" => "SVA"}),
        %GroundStation{
          ground_station_id: "gs_3",
          display_name: "Perth",
          code: "PER",
          metadata: %{}
        }
      ])

    fai = %{id: "gs_1", code: "FAI", name: "Fairbanks"}

    assert StationRefs.resolve("earendil-fairbanks", index) ==
             Map.put(fai, :ref, "earendil-fairbanks")

    assert StationRefs.resolve("FAI", index) == Map.put(fai, :ref, "FAI")
    assert StationRefs.resolve("gs_2", index).code == "SVA"
    # The model's code field (what Setup shows) wins over legacy metadata.
    assert StationRefs.resolve("PER", index) == %{
             ref: "PER",
             id: "gs_3",
             code: "PER",
             name: "Perth"
           }

    assert StationRefs.resolve("other", index) == %{ref: "other", id: nil, code: nil, name: nil}
    assert StationRefs.resolve(nil, index) == %{ref: nil, id: nil, code: nil, name: nil}

    snapshot = %{normalized_opportunity_document: %{"ground_station_ref" => "SVA"}}
    assert StationRefs.of_snapshot(snapshot, index).name == "Svalbard"
    assert StationRefs.of_snapshot(%{normalized_opportunity_document: nil}, index).ref == nil
  end
end
