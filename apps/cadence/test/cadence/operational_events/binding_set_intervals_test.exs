defmodule Cadence.OperationalEvents.BindingSetIntervalsTest do
  use Cadence.DataCase, async: true

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.{Event, EventQuery}

  test "interval reads omit fleet metadata while preserving boundaries, scope and full evidence" do
    organization_id = "org-interval-#{Ecto.UUID.generate()}"
    mission_id = "mission-interval-#{Ecto.UUID.generate()}"
    persist_mission_scope(organization_id, mission_id)
    start = ~U[2026-10-01 00:00:00.000000Z]
    metadata = %{"compiled_fleet" => String.duplicate("x", 1_000_000)}

    events =
      Enum.map(1..2, fn version ->
        event =
          Event.new(%{
            event_id: "activation-#{mission_id}-#{version}",
            organization_id: organization_id,
            mission_id: mission_id,
            occurred_at: DateTime.add(start, version, :second),
            category: :runtime,
            kind: :binding_set_activated,
            subject: %{kind: :binding_set, id: "binding-#{version}"},
            causality: %{
              source_record_kind: :binding_set_activation,
              source_record_id: "v#{version}"
            },
            payload: %{
              binding_set_id: "binding-#{version}",
              binding_set_version: version,
              activation_id: "v#{version}"
            },
            metadata: metadata
          })

        assert {:ok, saved} = OperationalEvents.persist_event(event)
        saved
      end)

    assert [first, second] =
             EventQuery.list_binding_set_interval_events(organization_id, mission_id, 1_000)

    assert first.metadata == %{}
    assert second.metadata == %{}
    assert [limited] = EventQuery.list_binding_set_interval_events(nil, mission_id, 1)
    assert limited.event_id == first.event_id
    assert [] = EventQuery.list_binding_set_interval_events("another-org", mission_id, 1_000)

    assert [one, two] = OperationalEvents.binding_set_intervals(organization_id, mission_id, [])
    assert one.starts_at == first.occurred_at
    assert one.ends_at == second.occurred_at
    assert two.starts_at == second.occurred_at
    assert two.ends_at == nil
    assert one.superseded_by_event_id == second.event_id
    assert one.payload["activation_id"] == "v1"
    assert two.payload["binding_set_version"] == 2
    assert one.metadata["source_record_id"] == "v1"

    for event <- events do
      assert {:ok, full} =
               OperationalEvents.fetch_event(organization_id, mission_id, event.event_id)

      assert full.metadata == metadata
    end
  end
end
