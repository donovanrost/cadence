defmodule Cadence.Application.Missions.MissionConfigContactsTest do
  use Cadence.DataCase, async: true

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Contacts
  alias Cadence.GroundStations

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.TargetsFixtures

  test "load includes planned contacts and enabled ground station profiles" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    {:ok, planned_contact} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 00:10:00Z],
        direction: :uplink,
        state: :planned
      })

    {:ok, _cancelled_contact} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-2",
        start_time: ~U[2024-01-02 00:00:00Z],
        end_time: ~U[2024-01-02 00:10:00Z],
        direction: :downlink,
        state: :cancelled
      })

    {:ok, enabled_profile} =
      GroundStations.create_profile(org.id, mission.id, %{
        ground_station_target_id: ground_station.id,
        name: "Primary",
        enabled: true,
        resources: %{
          "antennas" => [
            %{
              "id" => "ant-1",
              "activation" => %{
                "uplink_transport_id" => Ecto.UUID.generate(),
                "downlink_transport_id" => Ecto.UUID.generate()
              }
            }
          ]
        }
      })

    {:ok, _disabled_profile} =
      GroundStations.create_profile(org.id, mission.id, %{
        ground_station_target_id: ground_station.id,
        name: "Backup",
        enabled: false,
        resources: %{"antennas" => []}
      })

    {:ok, config} = MissionConfig.load(mission.id)

    assert Enum.map(config.contacts, & &1.id) == [planned_contact.id]
    assert Enum.map(config.ground_station_profiles, & &1.id) == [enabled_profile.id]
  end
end
