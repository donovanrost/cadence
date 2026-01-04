defmodule Cadence.TimelineTest do
  use Cadence.DataCase, async: true

  alias Cadence.{Buckets, Commands, Recordings, Timeline}
  alias Cadence.Recordings.Recordables.CommandDispatched

  import Cadence.MissionsFixtures
  import Cadence.OrganizationsFixtures
  import Cadence.TargetsFixtures

  test "command recordings include target id and name (via queue entry command aggregate id)" do
    org = organization_fixture()
    mission = mission_fixture(organization: org)
    target = target_fixture(organization: org, mission: mission, name: "SAT-001")

    {:ok, mission_bucket} =
      Buckets.create_bucket_with_path(%{
        organization_id: org.id,
        mission_id: mission.id,
        bucket_type: "mission",
        bucketable_type: "Mission",
        bucketable_id: mission.id,
        name: mission.name
      })

    now = DateTime.utc_now()
    command_aggregate_id = Ecto.UUID.generate()

    {:ok, %{recording: recording}} =
      Recordings.create(
        CommandDispatched,
        %{command_name: "SET_MODE"},
        %{
          organization_id: org.id,
          bucket_id: mission_bucket.id,
          aggregate_id: command_aggregate_id,
          timestamp: now
        }
      )

    _entry =
      Commands.QueueEntry.changeset(%Commands.QueueEntry{}, %{
        organization_id: org.id,
        mission_id: mission.id,
        target_id: target.id,
        command_name: "SET_MODE"
      })
      |> Repo.insert!()
      |> Commands.QueueEntry.execution_changeset(%{
        status: :executing,
        command_aggregate_id: command_aggregate_id
      })
      |> Repo.update!()

    start_time = DateTime.add(now, -60, :second)
    end_time = DateTime.add(now, 60, :second)

    [event] =
      Timeline.list_events_for_mission(mission.id, start_time, end_time,
        organization_id: org.id,
        types: [:command],
        include_future: false
      )

    assert event.id == "rec-#{recording.id}"
    assert event.target_id == target.id
    assert event.target_name == target.name
  end
end
