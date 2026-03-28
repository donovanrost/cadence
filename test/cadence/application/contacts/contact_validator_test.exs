defmodule Cadence.Application.Contacts.ContactValidatorTest do
  use Cadence.DataCase, async: true

  alias Cadence.Application.Contacts.ContactValidator
  alias Cadence.Contacts
  alias Cadence.GroundStations
  alias Cadence.Transports

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.TargetsFixtures

  test "detects antenna conflicts for overlapping contacts" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft_one = spacecraft_fixture(organization: org, mission: mission)
    spacecraft_two = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    transport = create_transport(org.id, mission.id)
    _profile = create_profile(org.id, mission.id, ground_station.id, ["ant-1"], transport.id)

    {:ok, contact_one} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft_one.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 00:10:00Z],
        direction: :uplink,
        state: :planned
      })

    {:ok, contact_two} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft_two.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:05:00Z],
        end_time: ~U[2024-01-01 00:15:00Z],
        direction: :uplink,
        state: :planned
      })

    validation = ContactValidator.validate(org.id, mission.id)

    contact_one_id = contact_one.id
    contact_two_id = contact_two.id

    assert Map.has_key?(validation.conflicts, contact_one_id)
    assert Map.has_key?(validation.conflicts, contact_two_id)

    conflicts_one = Map.get(validation.conflicts, contact_one_id, [])
    conflicts_two = Map.get(validation.conflicts, contact_two_id, [])

    assert Enum.any?(conflicts_one, &(&1.with == contact_two_id))
    assert Enum.any?(conflicts_two, &(&1.with == contact_one_id))
  end

  test "does not flag conflicts for different antennas" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft_one = spacecraft_fixture(organization: org, mission: mission)
    spacecraft_two = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    transport = create_transport(org.id, mission.id)

    _profile =
      create_profile(org.id, mission.id, ground_station.id, ["ant-1", "ant-2"], transport.id)

    {:ok, _contact_one} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft_one.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 00:10:00Z],
        direction: :uplink,
        state: :planned
      })

    {:ok, _contact_two} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft_two.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-2",
        start_time: ~U[2024-01-01 00:05:00Z],
        end_time: ~U[2024-01-01 00:15:00Z],
        direction: :uplink,
        state: :planned
      })

    validation = ContactValidator.validate(org.id, mission.id)
    assert validation.conflicts == %{}
  end

  test "ignores non-overlapping windows" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    transport = create_transport(org.id, mission.id)
    _profile = create_profile(org.id, mission.id, ground_station.id, ["ant-1"], transport.id)

    {:ok, _contact_one} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 00:05:00Z],
        direction: :uplink,
        state: :planned
      })

    {:ok, _contact_two} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:06:00Z],
        end_time: ~U[2024-01-01 00:10:00Z],
        direction: :uplink,
        state: :planned
      })

    validation = ContactValidator.validate(org.id, mission.id)
    assert validation.conflicts == %{}
  end

  test "ignores cancelled contacts" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    transport = create_transport(org.id, mission.id)
    _profile = create_profile(org.id, mission.id, ground_station.id, ["ant-1"], transport.id)

    {:ok, _planned_contact} =
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
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:05:00Z],
        end_time: ~U[2024-01-01 00:15:00Z],
        direction: :uplink,
        state: :cancelled
      })

    validation = ContactValidator.validate(org.id, mission.id)
    assert validation.conflicts == %{}
  end

  test "detects spacecraft conflicts" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    transport = create_transport(org.id, mission.id)

    _profile =
      create_profile(org.id, mission.id, ground_station.id, ["ant-1", "ant-2"], transport.id)

    {:ok, contact_one} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 00:10:00Z],
        direction: :uplink,
        state: :planned
      })

    {:ok, contact_two} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-2",
        start_time: ~U[2024-01-01 00:05:00Z],
        end_time: ~U[2024-01-01 00:15:00Z],
        direction: :uplink,
        state: :planned
      })

    validation = ContactValidator.validate(org.id, mission.id)

    contact_one_id = contact_one.id
    contact_two_id = contact_two.id

    assert Map.has_key?(validation.conflicts, contact_one_id)
    assert Map.has_key?(validation.conflicts, contact_two_id)

    conflicts_one = Map.get(validation.conflicts, contact_one_id, [])
    conflicts_two = Map.get(validation.conflicts, contact_two_id, [])

    assert Enum.any?(conflicts_one, &(&1.type == :spacecraft_conflict))
    assert Enum.any?(conflicts_two, &(&1.type == :spacecraft_conflict))
  end

  test "reports hard errors for missing profile and antenna mapping" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    {:ok, contact_one} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 00:10:00Z],
        direction: :uplink,
        state: :planned
      })

    validation = ContactValidator.validate(org.id, mission.id)

    contact_one_id = contact_one.id

    issues = Map.get(validation.hard_errors, contact_one_id, [])
    assert [issue | _] = issues
    assert issue.type == :profile_not_found

    transport = create_transport(org.id, mission.id)

    _profile = create_profile(org.id, mission.id, ground_station.id, ["ant-2"], transport.id)

    validation = ContactValidator.validate(org.id, mission.id)
    issues = Map.get(validation.hard_errors, contact_one_id, [])
    assert [issue | _] = issues
    assert issue.type == :antenna_not_found
  end

  defp create_transport(org_id, mission_id) do
    {:ok, transport} =
      Transports.create_interface(org_id, mission_id, %{
        name: "Uplink",
        type: :tcp,
        enabled: true
      })

    transport
  end

  defp create_profile(org_id, mission_id, ground_station_id, antenna_ids, transport_id) do
    antennas =
      antenna_ids
      |> List.wrap()
      |> Enum.map(fn antenna_id ->
        %{
          "id" => antenna_id,
          "activation" => %{"uplink_transport_id" => transport_id}
        }
      end)

    {:ok, profile} =
      GroundStations.create_profile(org_id, mission_id, %{
        ground_station_target_id: ground_station_id,
        name: "Profile-#{List.first(List.wrap(antenna_ids))}",
        enabled: true,
        resources: %{
          "antennas" => antennas
        }
      })

    profile
  end
end
