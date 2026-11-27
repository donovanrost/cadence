defmodule CadenceSimulator.Provider.PassOpportunitiesTest do
  @moduledoc """
  Opportunities from real passes (#893): under `orbit_readiness.source_kind: "uploaded"` the
  simulator offers each spacecraft's passes, computed with `packages/sgp4` from the element set
  Cadence uploaded, over the scenario's located stations. Offers are deterministic and restorable
  from their ids; synthetic scenarios keep the hash model.
  """
  use CadenceSimulator.Case, async: false

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Ephemeris, Opportunities, PassCache, ServiceProfiles, Store}

  @epoch ~U[2026-11-27 00:00:00Z]
  @from ~U[2026-11-27 00:00:00Z]
  @to ~U[2026-11-28 00:00:00Z]
  @boulder {40.0, -105.0}

  setup do
    :ok = Store.clear()

    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 2,
        "spacecraft_prefix" => "EARENDIL",
        "ground_stations" => [
          %{
            "id" => "station-boulder",
            "antenna_count" => 1,
            "location" => %{"latitude_deg" => 40.0, "longitude_deg" => -105.0}
          },
          %{"id" => "station-nowhere", "antenna_count" => 1}
        ],
        "orbit_readiness" => %{"source_kind" => "uploaded"}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 7})
    {:ok, _stored, _status} = Ephemeris.put(run, "EARENDIL-001", upload())
    %{run: run}
  end

  test "offers the uploaded orbit's real passes over located stations, AOS to LOS", c do
    expected = expected_passes()
    assert expected != []

    offers = search(c.run, ["EARENDIL-001"])

    assert Enum.map(offers, &{unix(&1["starts_at"]), unix(&1["ends_at"])}) ==
             Enum.map(
               expected,
               &{DateTime.to_unix(&1.aos), min(DateTime.to_unix(&1.los), DateTime.to_unix(@to))}
             )

    assert Enum.all?(offers, &(&1["ground_station_id"] == "station-boulder"))
    assert Enum.all?(offers, &(&1["model"] == "sgp4_pass_v1"))

    for {offer, pass} <- Enum.zip(offers, expected) do
      assert_in_delta offer["max_elevation_deg"], pass.max_elevation_deg, 0.01
      assert offer["tca"] == pass.tca |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    end
  end

  test "a spacecraft with no upload has no passes, and the contract search refuses it", c do
    assert search(c.run, ["EARENDIL-002"]) == []

    assert {:error, {:orbit_not_ready, %{"status" => "missing"}}} =
             Opportunities.search(c.run, contract_params(c.run, ["EARENDIL-002"]))
  end

  test "offers are deterministic, carry geometry, and restore from their ids", c do
    params = contract_params(c.run, ["EARENDIL-001"])
    assert {:ok, %{data: [first | _] = page}} = Opportunities.search(c.run, params)
    assert {:ok, %{data: ^page}} = Opportunities.search(c.run, params)

    assert %{"max_elevation_deg" => elevation, "tca" => tca, "model" => "sgp4_pass_v1"} =
             first["extensions"]

    assert is_number(elevation) and is_binary(tca)

    assert {:ok, restored} = Opportunities.fetch(c.run, first["id"])
    assert {restored["starts_at"], restored["ends_at"]} == {first["starts_at"], first["ends_at"]}
    assert restored["extensions"]["max_elevation_deg"] == elevation

    # A window one second off any pass was never offered.
    assert {:error, :not_found} =
             Provider.restore_opportunity(
               c.run,
               1,
               0,
               unix(first["starts_at"]) + 1,
               unix(first["ends_at"])
             )
  end

  test "a repeated search reads the cached passes instead of propagating again", c do
    search(c.run, ["EARENDIL-001"])
    computed = PassCache.computed()
    search(c.run, ["EARENDIL-001"])
    assert PassCache.computed() == computed
  end

  test "a synthetic scenario keeps the hash model" do
    {:ok, scenario} =
      Provider.create_scenario(%{"spacecraft_count" => 1, "spacecraft_prefix" => "SYN"})

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 7})
    offers = search(run, ["SYN-001"])
    assert offers != []
    assert Enum.all?(offers, &(&1["model"] == "deterministic_pass_v1"))
    refute Enum.any?(offers, &Map.has_key?(&1, "max_elevation_deg"))
  end

  defp search(run, spacecraft) do
    {:ok, %{"data" => data}} =
      Provider.search_opportunities(%{
        "run_id" => run["id"],
        "spacecraft_ids" => spacecraft,
        "starts_at" => DateTime.to_iso8601(@from),
        "ends_at" => DateTime.to_iso8601(@to),
        "limit" => 500
      })

    data
  end

  defp contract_params(run, refs) do
    %{
      "service_profile_ref" => hd(ServiceProfiles.for_run(run))["id"],
      "spacecraft_refs" => refs,
      "ground_station_refs" => [],
      "starts_at" => DateTime.to_iso8601(@from),
      "ends_at" => DateTime.to_iso8601(@to),
      "page_size" => 50
    }
  end

  # The same passes straight from packages/sgp4: AOS in the window, over the one located station.
  defp expected_passes do
    {:ok, sat} =
      Sgp4.init(%{
        epoch: @epoch,
        mean_motion: 15.2,
        eccentricity: 0.0005,
        inclination_deg: 53.0,
        raan_deg: 10.0,
        arg_perigee_deg: 20.0,
        mean_anomaly_deg: 30.0,
        bstar: 2.0e-5
      })

    {lat, lon} = @boulder
    {:ok, station} = Sgp4.Station.new(0, lat, lon, 0.0, 5.0)
    {:ok, %{passes: passes}} = Sgp4.Passes.search(sat, [station], @from, @to)

    Enum.filter(passes, fn pass ->
      DateTime.compare(pass.aos, @from) != :lt and
        DateTime.to_unix(pass.los) > DateTime.to_unix(pass.aos)
    end)
  end

  defp upload do
    %{
      "omm" => %{
        "OBJECT_NAME" => "EARENDIL 1",
        "EPOCH" => DateTime.to_iso8601(@epoch),
        "MEAN_MOTION" => 15.2,
        "ECCENTRICITY" => 0.0005,
        "INCLINATION" => 53.0,
        "RA_OF_ASC_NODE" => 10.0,
        "ARG_OF_PERICENTER" => 20.0,
        "MEAN_ANOMALY" => 30.0,
        "BSTAR" => 2.0e-5
      },
      "epoch" => DateTime.to_iso8601(@epoch),
      "content_sha256" => :sha256 |> :crypto.hash("orbit") |> Base.encode16(case: :lower)
    }
  end

  defp unix(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    DateTime.to_unix(at)
  end
end
