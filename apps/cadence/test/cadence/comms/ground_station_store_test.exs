defmodule Cadence.Comms.GroundStationStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.GroundStation

  test "persists, fetches, lists, and archives mission ground stations" do
    persist_mission_scope("org-ground-station", "mission-ground-station")

    ground_station =
      GroundStation.new(%{
        mission_id: "mission-ground-station",
        ground_station_id: "dss-14",
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "goldstone",
        metadata: %{"antenna_diameter_m" => 70}
      })

    assert {:ok, persisted} = Cadence.persist_ground_station("org-ground-station", ground_station)
    assert persisted.organization_id == "org-ground-station"
    assert persisted.lifecycle_state == :active
    assert persisted.metadata["antenna_diameter_m"] == 70

    assert {:ok, fetched} =
             Cadence.fetch_ground_station(
               "org-ground-station",
               "mission-ground-station",
               "dss-14"
             )

    assert fetched.display_name == "Goldstone DSS-14"

    assert {:ok, updated} =
             Cadence.update_ground_station(
               "org-ground-station",
               "mission-ground-station",
               "dss-14",
               %{
                 display_name: "Goldstone DSS-14 Prime",
                 provider: "DSN",
                 region: "california",
                 metadata: %{"antenna_diameter_m" => 70, "network" => "deep-space"}
               }
             )

    assert updated.display_name == "Goldstone DSS-14 Prime"
    assert updated.region == "california"
    assert updated.metadata["network"] == "deep-space"

    assert [listed] = Cadence.list_ground_stations("org-ground-station", "mission-ground-station")
    assert listed.ground_station_id == "dss-14"
    assert listed.display_name == "Goldstone DSS-14 Prime"

    assert {:ok, archived} =
             Cadence.archive_ground_station(
               "org-ground-station",
               "mission-ground-station",
               "dss-14",
               %{"reason" => "retired"}
             )

    assert archived.lifecycle_state == :archived
    assert archived.metadata["reason"] == "retired"

    assert [] = Cadence.list_ground_stations("org-ground-station", "mission-ground-station")

    assert {:error, :ground_station_not_found} =
             Cadence.fetch_ground_station(
               "org-ground-station",
               "mission-ground-station",
               "dss-14"
             )
  end
end
