defmodule CadenceSimulator.Provider.StationLocationsTest do
  @moduledoc "The simulator reports a WGS84 location for its stations (#890)."
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.Store

  setup do
    :ok = Store.clear()
    :ok
  end

  test "the default stations report their sites' locations" do
    {:ok, scenario} = Provider.create_scenario(%{"spacecraft_count" => 1})
    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 1})
    {:ok, stations} = Provider.ground_stations(run["id"])
    by_id = Map.new(stations, &{&1["id"], &1["location"]})

    assert %{"latitude_deg" => 78.2297, "longitude_deg" => 15.4078, "height_m" => 500.0} =
             by_id["station-svalbard"]

    assert %{"latitude_deg" => -72.0117} = by_id["station-troll"]
    assert %{"longitude_deg" => -155.663} = by_id["station-hawaii"]
  end

  test "a scenario station keeps a location of two numbers and leaves out anything else" do
    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 1,
        "ground_stations" => [
          %{"id" => "gs-a", "location" => %{"latitude_deg" => 10, "longitude_deg" => 20}},
          %{"id" => "gs-b", "location" => %{"latitude_deg" => "north", "longitude_deg" => 20}},
          %{"id" => "gs-c"}
        ]
      })

    stations = Map.new(scenario["ground_stations"], &{&1["id"], &1})

    assert stations["gs-a"]["location"] ==
             %{"latitude_deg" => 10, "longitude_deg" => 20, "height_m" => 0.0}

    refute Map.has_key?(stations["gs-b"], "location")
    refute Map.has_key?(stations["gs-c"], "location")
  end
end
