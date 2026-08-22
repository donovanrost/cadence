defmodule Cadence.Reads.MissionTimelineTest do
  use Cadence.DataCase, async: true

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.{Event, EventRow}
  alias Cadence.Reads.MissionTimeline
  alias Cadence.Repo

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

  test "filtered contact reads are not drowned out by newer unrelated operational events" do
    organization_id = "org-mission-timeline-contact"
    mission_id = "mission-timeline-contact"

    contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-contact-timeline",
        mission_id: mission_id,
        starts_at: ~U[2026-08-01 12:00:00Z],
        ends_at: ~U[2026-08-01 12:15:00Z]
      })

    assert {:ok, _event} =
             contact
             |> Map.put(:organization_id, organization_id)
             |> Event.from_scheduled_contact_interval()
             |> OperationalEvents.persist_event()

    inserted_at = ~U[2026-08-01 13:00:00Z]

    noise_rows =
      Enum.map(1..1_001, fn index ->
        Event.new(%{
          event_id: "newer-runtime-event-#{index}",
          organization_id: organization_id,
          mission_id: mission_id,
          occurred_at: DateTime.add(inserted_at, index, :second),
          category: :runtime,
          kind: :binding_set_activated,
          severity: :info
        })
        |> EventRow.insert_attrs(inserted_at)
      end)

    assert {1_001, nil} = Repo.insert_all(EventRow, noise_rows)

    assert [entry] =
             MissionTimeline.list_for_mission(organization_id, mission_id,
               category: :operations,
               kind: :scheduled_contact_interval,
               limit: 10
             )

    assert entry.scheduled_contact_id == contact.scheduled_contact_id
    assert entry.category == :operations
  end
end
