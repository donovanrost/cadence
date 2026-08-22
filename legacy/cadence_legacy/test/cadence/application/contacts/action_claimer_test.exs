defmodule Cadence.Application.Contacts.ActionClaimerTest do
  use Cadence.DataCase, async: false

  alias Cadence.Adapters.Contacts.ActionClaimer
  alias Cadence.Buckets
  alias Cadence.Contacts
  alias Cadence.Recordings.Recordables.ContactActionDispatched

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.TargetsFixtures

  test "claim is idempotent via unique contact_action_id" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)

    spacecraft = spacecraft_fixture(organization: org, mission: mission)
    ground_station = ground_station_fixture(organization: org, mission: mission)

    {:ok, contact} =
      Contacts.create_contact(org.id, mission.id, %{
        spacecraft_target_id: spacecraft.id,
        ground_station_target_id: ground_station.id,
        antenna_id: "ant-1",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 00:10:00Z],
        direction: :uplink,
        state: :planned
      })

    {:ok, action} =
      Contacts.create_contact_command_action(org.id, mission.id, %{
        contact_id: contact.id,
        gate: :uplink_ready,
        order: 0,
        state: :planned,
        command_ref: %{"command_name" => "PING", "parameters" => %{}}
      })

    {:ok, bucket} =
      Buckets.create_bucket_with_path(%{
        organization_id: org.id,
        mission_id: mission.id,
        bucket_type: "mission",
        bucketable_type: "Mission",
        bucketable_id: mission.id,
        name: mission.name
      })

    context = %{organization_id: org.id, mission_id: mission.id, bucket_id: bucket.id}

    assert :ok = ActionClaimer.claim(action, context)
    assert {:error, :already_claimed} = ActionClaimer.claim(action, context)

    assert Repo.aggregate(ContactActionDispatched, :count) == 1
  end
end
