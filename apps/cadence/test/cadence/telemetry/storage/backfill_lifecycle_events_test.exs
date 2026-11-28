defmodule Cadence.Telemetry.Storage.BackfillLifecycleEventsTest do
  use Cadence.DataCase, async: false

  import Cadence.BackfillLifecycleFixtures

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.OperationalEvents
  alias Cadence.Telemetry.Storage

  test "records and lists backfill lifecycle events by mission source observable and window" do
    assert {:ok, event} =
             record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "backfill-event-1",
                 backfill_run_id: "backfill-run-1",
                 organization_id: "org-1",
                 mission_id: "mission-1",
                 realm: :flight,
                 data_source_id: "flight-questdb",
                 binding_id: "flight-telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 spacecraft_id: "sc-1",
                 event_type: :backfill_completed,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 receipt_from: ~U[2026-06-22 12:10:00Z],
                 receipt_to: ~U[2026-06-22 12:20:00Z],
                 sample_count: 42,
                 authority: :authoritative,
                 reason: :operator_backfill,
                 actor_id: "ops-1",
                 actor_kind: "operator",
                 occurred_at: ~U[2026-06-22 12:21:00Z],
                 payload: %{"source" => "manual_import"}
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.backfill_lifecycle_event_id == "backfill-event-1"
    assert event.backfill_run_id == "backfill-run-1"
    assert event.event_type == :backfill_completed
    assert event.authority == :authoritative
    assert event.reason == :operator_backfill
    assert event.payload["source"] == "manual_import"

    assert [operational_event] =
             OperationalEvents.list_events("org-1", "mission-1",
               category: :telemetry,
               kind: :telemetry_backfill_completed,
               source_record_kind: :telemetry_backfill_lifecycle_event,
               source_record_id: "backfill-event-1"
             )

    assert operational_event.subject == %{kind: :telemetry_point, id: "HK.counter"}
    assert operational_event.scope["data_source_id"] == "flight-questdb"
    assert operational_event.scope["source_binding_id"] == "flight-telemetry"
    assert operational_event.scope["data_realm"] == "flight"
    assert operational_event.payload["event_type"] == "backfill_completed"
    assert operational_event.payload["authority"] == "authoritative"
    assert operational_event.payload["lifecycle_payload"] == %{"source" => "manual_import"}

    assert [listed] =
             Storage.list_backfill_lifecycle_events("mission-1",
               organization_id: "org-1",
               realm: :flight,
               data_source_id: "flight-questdb",
               binding_id: "flight-telemetry",
               observable_id: "HK.counter",
               source_from: ~U[2026-06-22 11:30:00Z],
               source_to: ~U[2026-06-22 11:45:00Z],
               from_occurred_at: ~U[2026-06-22 12:00:00Z],
               to_occurred_at: ~U[2026-06-22 12:30:00Z]
             )

    assert listed.backfill_lifecycle_event_id == "backfill-event-1"

    assert fetched =
             Storage.fetch_backfill_lifecycle_event("backfill-event-1",
               organization_id: "org-1",
               mission_id: "mission-1"
             )

    assert fetched.backfill_lifecycle_event_id == "backfill-event-1"
    assert fetched.point_id == "HK.counter"

    refute Storage.fetch_backfill_lifecycle_event("backfill-event-1",
             organization_id: "org-1",
             mission_id: "mission-other"
           )

    assert [] =
             Storage.list_backfill_lifecycle_events("mission-1",
               organization_id: "org-1",
               observable_id: "HK.voltage"
             )

    assert [] =
             Storage.list_backfill_lifecycle_events("mission-1",
               organization_id: "org-1",
               source_from: ~U[2026-06-22 13:00:00Z],
               source_to: ~U[2026-06-22 14:00:00Z]
             )
  end

  test "lists replay backfill lifecycle events by replay run" do
    assert {:ok, event} =
             record_backfill_lifecycle_event(
               %{
                 backfill_lifecycle_event_id: "backfill-event-replay-1",
                 backfill_run_id: "backfill-run-replay-1",
                 organization_id: "org-1",
                 mission_id: "mission-1",
                 realm: :replay,
                 replay_run_id: "replay-run-1",
                 data_source_id: "replay-questdb",
                 binding_id: "replay-telemetry",
                 observable_id: "HK.counter",
                 event_type: :backfill_completed,
                 source_from: ~U[2026-06-22 11:00:00Z],
                 source_to: ~U[2026-06-22 12:00:00Z],
                 authority: :authoritative,
                 occurred_at: ~U[2026-06-22 12:21:00Z]
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.replay_run_id == "replay-run-1"

    assert [listed] =
             Storage.list_backfill_lifecycle_events("mission-1",
               organization_id: "org-1",
               realm: :replay,
               replay_run_id: "replay-run-1"
             )

    assert listed.backfill_lifecycle_event_id == "backfill-event-replay-1"
    assert listed.replay_run_id == "replay-run-1"

    assert [] =
             Storage.list_backfill_lifecycle_events("mission-1",
               organization_id: "org-1",
               realm: :replay,
               replay_run_id: "replay-run-2"
             )
  end

  test "emits historical data invalidation when recording lifecycle events" do
    attach_runtime_invalidation_telemetry(self())

    assert {:ok, event} =
             record_backfill_lifecycle_event(%{
               backfill_lifecycle_event_id: "backfill-event-invalidation",
               backfill_run_id: "backfill-run-invalidation",
               organization_id: "org-1",
               mission_id: "mission-1",
               realm: :replay,
               replay_run_id: "replay-run-invalidation",
               data_source_id: "replay-questdb",
               binding_id: "replay-telemetry",
               observable_id: "HK.counter",
               event_type: :backfill_completed,
               source_from: ~U[2026-06-22 11:00:00Z],
               source_to: ~U[2026-06-22 12:00:00Z],
               authority: :authoritative,
               occurred_at: ~U[2026-06-22 12:21:00Z]
             })

    assert event.backfill_lifecycle_event_id == "backfill-event-invalidation"

    assert_receive {:runtime_invalidation_telemetry, metadata}
    assert metadata.boundary == :historical_data_changed
    assert metadata.filters.organization_id == "org-1"
    assert metadata.filters.mission_id == "mission-1"
    assert metadata.filters.logical_source == :telemetry
    assert metadata.filters.data_source_id == "replay-questdb"
    assert metadata.filters.source_binding_id == "replay-telemetry"
    assert metadata.filters.realm == :replay
    assert metadata.filters.replay_run_id == "replay-run-invalidation"
    assert metadata.filters.observable == "HK.counter"
    assert metadata.filters.evidence_ref.id == "backfill-event-invalidation"
  end

  defp attach_runtime_invalidation_telemetry(test_pid) do
    handler_id = "backfill-lifecycle-invalidation-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [RuntimeInvalidation.telemetry_event()],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:runtime_invalidation_telemetry, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
