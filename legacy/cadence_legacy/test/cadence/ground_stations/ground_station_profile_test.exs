defmodule Cadence.GroundStations.GroundStationProfileTest do
  use Cadence.DataCase, async: true

  alias Cadence.GroundStations.GroundStationProfile

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.TargetsFixtures

  test "changeset validates resources antennas list" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    attrs = %{
      organization_id: org.id,
      mission_id: mission.id,
      ground_station_target_id: ground_station.id,
      name: "Primary Station",
      enabled: true,
      resources: %{
        "antennas" => [
          %{
            "id" => "ant-1",
            "name" => "ANT-1",
            "activation" => %{
              "uplink_transport_id" => Ecto.UUID.generate(),
              "downlink_transport_id" => Ecto.UUID.generate()
            }
          }
        ]
      }
    }

    assert %Ecto.Changeset{valid?: true} =
             GroundStationProfile.changeset(%GroundStationProfile{}, attrs)

    invalid_attrs = Map.put(attrs, :resources, %{"antennas" => %{}})

    assert %Ecto.Changeset{valid?: false} =
             GroundStationProfile.changeset(%GroundStationProfile{}, invalid_attrs)
  end
end
