defmodule Cadence.Reads.MissionTimelineTest do
  use Cadence.DataCase, async: true

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Reads.MissionTimeline

  test "projects otherwise unprojected operational events into the canonical read" do
    organization_id = "org-mission-timeline"
    mission_id = "mission-timeline"

    event =
      Event.new(%{
        event_id: "source-health-1",
        organization_id: organization_id,
        mission_id: mission_id,
        occurred_at: ~U[2026-08-01 12:00:00Z],
        category: :data_source,
        kind: :source_health_degraded,
        severity: :warning,
        subject: %{kind: :data_source, id: "flight-telemetry"},
        scope: %{spacecraft_id: "spacecraft-1", data_source_id: "flight-telemetry"},
        current: %{status: "degraded"}
      })

    assert {:ok, _event} = OperationalEvents.persist_event(event)

    assert [entry] =
             MissionTimeline.list_for_mission(organization_id, mission_id,
               category: :health,
               spacecraft_id: "spacecraft-1"
             )

    assert entry.mission_event_id == "mission_event:source-health-1"
    assert entry.category == :health
    assert entry.status == "degraded"

    assert {:ok, fetched} =
             MissionTimeline.fetch_for_mission(
               organization_id,
               mission_id,
               entry.mission_event_id
             )

    assert fetched == entry
  end
end
