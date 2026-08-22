defmodule Cadence.Contacts.ContactTest do
  use Cadence.DataCase, async: true

  alias Cadence.Contacts.Contact

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.TargetsFixtures

  test "changeset validates required fields and time range" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)
    spacecraft = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    attrs = %{
      organization_id: org.id,
      mission_id: mission.id,
      spacecraft_target_id: spacecraft.id,
      ground_station_target_id: ground_station.id,
      antenna_id: "ant-1",
      start_time: ~U[2024-01-01 00:00:00Z],
      end_time: ~U[2024-01-01 00:10:00Z],
      direction: :uplink,
      state: :planned
    }

    changeset = Contact.changeset(%Contact{}, attrs)
    assert %Ecto.Changeset{valid?: true} = changeset
    assert Ecto.Changeset.get_field(changeset, :priority) == 0

    invalid_attrs = Map.put(attrs, :end_time, ~U[2024-01-01 00:00:00Z])

    assert %Ecto.Changeset{valid?: false} = Contact.changeset(%Contact{}, invalid_attrs)
  end
end
