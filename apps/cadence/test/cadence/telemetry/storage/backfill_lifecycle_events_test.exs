defmodule Cadence.Telemetry.Storage.BackfillLifecycleEventsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.OperationalEvents
  alias Cadence.Platform.EventBus
  alias Cadence.Telemetry.BackfillLifecycleChanged
  alias Cadence.Telemetry.Facts, as: TelemetryFacts
  alias Cadence.Telemetry.Storage

  test "workflow publication preserves the explicitly selected event bus" do
    event_bus = start_event_bus()
    assert :ok = TelemetryFacts.subscribe(event_bus, self())

    assert {:ok, event} =
             Storage.record_backfill_lifecycle_workflow_event(
               :backfill,
               :requested,
               %{
                 backfill_run_id: "backfill-run-explicit-bus",
                 organization_id: "org-explicit-bus",
                 mission_id: "mission-explicit-bus",
                 realm: :flight,
                 payload: %{"request" => "operator"}
               },
               event_bus: event_bus
             )

    assert_receive {:"$gen_cast",
                    {:cadence_fact, {:cadence, :telemetry, :facts},
                     %BackfillLifecycleChanged{} = fact}}

    assert fact.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id

    assert fact.payload == %{
             "request" => "operator",
             "workflow" => "backfill",
             "stage" => "requested",
             "run_id" => "backfill-run-explicit-bus",
             "requested_event_type" => "backfill_requested"
           }

    refute Map.has_key?(fact.payload, "event_bus")
  end

  test "records workflow-level backfill request and approval events" do
    base_attrs = %{
      backfill_run_id: "backfill-run-workflow",
      organization_id: "org-1",
      mission_id: "mission-workflow",
      realm: :flight,
      data_source_id: "flight-questdb",
      binding_id: "flight-telemetry",
      observable_id: "HK.counter",
      source_from: ~U[2026-06-22 11:00:00Z],
      source_to: ~U[2026-06-22 12:00:00Z],
      actor_id: "ops-1",
      actor_kind: "operator",
      payload: %{"ticket_id" => "ticket-1"}
    }

    assert {:ok, requested} =
             Storage.record_backfill_lifecycle_workflow_event(
               :backfill,
               :requested,
               Map.put(base_attrs, :occurred_at, ~U[2026-06-22 10:55:00Z]),
               dashboard_runtime_invalidation?: false
             )

    assert requested.event_type == :backfill_requested
    assert requested.authority == :unknown
    assert requested.reason == :backfill_requested
    assert requested.payload["workflow"] == "backfill"
    assert requested.payload["stage"] == "requested"
    assert requested.payload["run_id"] == "backfill-run-workflow"
    assert requested.payload["ticket_id"] == "ticket-1"

    assert {:ok, approved} =
             Storage.record_backfill_lifecycle_workflow_event(
               :backfill,
               :approved,
               Map.merge(base_attrs, %{
                 occurred_at: ~U[2026-06-22 10:58:00Z],
                 reason: :operator_approved_backfill
               }),
               dashboard_runtime_invalidation?: false
             )

    assert approved.event_type == :backfill_approved
    assert approved.authority == :authoritative
    assert approved.reason == :operator_approved_backfill

    assert [requested, approved] =
             Storage.list_backfill_lifecycle_events("mission-workflow",
               organization_id: "org-1",
               backfill_run_id: "backfill-run-workflow"
             )

    assert Enum.map([requested, approved], & &1.event_type) == [
             :backfill_requested,
             :backfill_approved
           ]
  end

  test "records workflow-level import rejection events from string inputs" do
    assert {:ok, event} =
             Storage.record_backfill_lifecycle_workflow_event(
               "import",
               "rejected",
               %{
                 import_run_id: "import-run-rejected",
                 organization_id: "org-1",
                 mission_id: "mission-import-workflow",
                 realm: "rehearsal",
                 data_source_id: "rehearsal-questdb",
                 binding_id: "rehearsal-telemetry",
                 reason: "operator_rejected_import",
                 actor_id: "ops-2",
                 occurred_at: ~U[2026-06-22 10:55:00Z]
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.backfill_run_id == "import-run-rejected"
    assert event.event_type == :import_rejected
    assert event.authority == :unknown
    assert event.reason == :operator_rejected_import
    assert event.payload["workflow"] == "import"
    assert event.payload["stage"] == "rejected"
    assert event.payload["requested_event_type"] == "import_rejected"
  end

  test "workflow-level lifecycle events require tenant mission realm and run context" do
    assert {:error, {:missing_field, :organization_id}} =
             Storage.record_backfill_lifecycle_workflow_event(:backfill, :requested, %{})

    assert {:error, {:missing_field, :backfill_run_id}} =
             Storage.record_backfill_lifecycle_workflow_event(:backfill, :requested, %{
               organization_id: "org-1",
               mission_id: "mission-1",
               realm: :flight
             })

    assert {:error, {:unsupported_backfill_lifecycle_stage, "queued"}} =
             Storage.record_backfill_lifecycle_workflow_event("backfill", "queued", %{
               organization_id: "org-1",
               mission_id: "mission-1",
               realm: :flight,
               backfill_run_id: "backfill-run-1"
             })
  end

  test "executes workflow lifecycle around a failed operation" do
    attrs = %{
      backfill_run_id: "backfill-run-failed-workflow",
      organization_id: "org-1",
      mission_id: "mission-workflow-failed",
      realm: :flight,
      data_source_id: "flight-questdb",
      binding_id: "flight-telemetry",
      observable_id: "HK.counter",
      source_from: ~U[2026-06-22 11:00:00Z],
      source_to: ~U[2026-06-22 12:00:00Z]
    }

    assert {:error, :writer_down} =
             Storage.execute_backfill_lifecycle_workflow(
               :backfill,
               attrs,
               [],
               fn write_opts ->
                 assert Keyword.fetch!(write_opts, :backfill_run_id) ==
                          "backfill-run-failed-workflow"

                 assert Keyword.fetch!(write_opts, :record_backfill_lifecycle_event?) == false
                 {:error, :writer_down}
               end,
               dashboard_runtime_invalidation?: false
             )

    events =
      Storage.list_backfill_lifecycle_events("mission-workflow-failed",
        organization_id: "org-1",
        backfill_run_id: "backfill-run-failed-workflow"
      )

    assert Enum.map(events, & &1.event_type) == [
             :backfill_requested,
             :backfill_approved,
             :backfill_started,
             :backfill_failed
           ]

    failed = List.last(events)
    assert failed.reason == :workflow_operation_failed
    assert failed.payload["error"] == ":writer_down"
  end

  test "rejected workflow lifecycle does not execute operation" do
    attrs = %{
      import_run_id: "import-run-rejected-workflow",
      organization_id: "org-1",
      mission_id: "mission-workflow-rejected",
      realm: :rehearsal,
      data_source_id: "rehearsal-questdb",
      binding_id: "rehearsal-telemetry"
    }

    assert {:error, {:workflow_rejected, :import}} =
             Storage.execute_backfill_lifecycle_workflow(
               :import,
               attrs,
               [],
               fn _write_opts -> flunk("operation should not execute for rejected workflows") end,
               approval: :rejected,
               dashboard_runtime_invalidation?: false
             )

    events =
      Storage.list_backfill_lifecycle_events("mission-workflow-rejected",
        organization_id: "org-1",
        backfill_run_id: "import-run-rejected-workflow"
      )

    assert Enum.map(events, & &1.event_type) == [
             :import_requested,
             :import_rejected
           ]
  end

  test "records and lists backfill lifecycle events by mission source observable and window" do
    assert {:ok, event} =
             Storage.record_backfill_lifecycle_event(
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
             Storage.record_backfill_lifecycle_event(
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
             Storage.record_backfill_lifecycle_event(%{
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

  defp start_event_bus do
    start_supervised!(%{
      id: {:backfill_fact_event_bus, make_ref()},
      start: {EventBus, :start_link, [[name: nil, delivery: :async, before_notify: nil]]},
      restart: :temporary
    })
  end
end
