defmodule Cadence.Telemetry.BackfillLifecycleChangedTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Telemetry.BackfillLifecycleChanged
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent

  test "exposes committed lifecycle data without the storage representation" do
    event =
      BackfillLifecycleEvent.new(%{
        backfill_lifecycle_event_id: "backfill-event-1",
        backfill_run_id: "backfill-run-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        realm: :flight,
        data_source_id: "source-1",
        binding_id: "binding-1",
        observable_id: "HK.counter",
        event_type: :backfill_completed,
        source_from: ~U[2026-08-02 12:00:00Z],
        source_to: ~U[2026-08-02 12:05:00Z],
        sample_count: 42,
        occurred_at: ~U[2026-08-02 12:06:00Z]
      })

    assert %BackfillLifecycleChanged{} = fact = BackfillLifecycleEvent.to_fact(event)
    assert fact.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id
    assert fact.backfill_run_id == event.backfill_run_id
    assert fact.organization_id == event.organization_id
    assert fact.mission_id == event.mission_id
    assert fact.event_type == :backfill_completed
    assert fact.sample_count == 42
    refute Map.has_key?(fact, :__meta__)
  end
end
