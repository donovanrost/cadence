defmodule Cadence.Reads.StationRefsTest do
  use ExUnit.Case, async: true

  alias Cadence.Comms.GroundStation
  alias Cadence.Reads.StationRefs

  defp station(id, name, metadata),
    do: %GroundStation{ground_station_id: id, display_name: name, metadata: metadata}

  test "a provider ref resolves by id, code or provider station ref; nulls otherwise" do
    index =
      StationRefs.build([
        station("gs_1", "Fairbanks", %{
          "code" => "FAI",
          "provider_station_ref" => "earendil-fairbanks"
        }),
        station("gs_2", "Svalbard", %{"code" => "SVA"})
      ])

    fai = %{id: "gs_1", code: "FAI", name: "Fairbanks"}

    assert StationRefs.resolve("earendil-fairbanks", index) ==
             Map.put(fai, :ref, "earendil-fairbanks")

    assert StationRefs.resolve("FAI", index) == Map.put(fai, :ref, "FAI")
    assert StationRefs.resolve("gs_2", index).code == "SVA"
    assert StationRefs.resolve("other", index) == %{ref: "other", id: nil, code: nil, name: nil}
    assert StationRefs.resolve(nil, index) == %{ref: nil, id: nil, code: nil, name: nil}

    snapshot = %{normalized_opportunity_document: %{"ground_station_ref" => "SVA"}}
    assert StationRefs.of_snapshot(snapshot, index).name == "Svalbard"
    assert StationRefs.of_snapshot(%{normalized_opportunity_document: nil}, index).ref == nil
  end
end
