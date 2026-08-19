defmodule Cadence.Telemetry.DataManagementTest do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  use Cadence.ConfigCase, async: false

  import Cadence.Telemetry.DataManagementFixtures

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.Storage

  setup do
    persistence_policy = data_management_persistence_policy()

    start_supervised!(
      CurrentValueStore.child_spec(persistence_policy.storage.current_value_store_policy)
    )

    start_supervised!(HistoryStore.child_spec(persistence_policy.history_store))
    CurrentValueStore.reset(persistence_policy.storage.current_value_store_policy)
    HistoryStore.reset(persistence_policy.history_store)

    %{persistence_policy: persistence_policy}
  end

  test "records historical workflow stage transitions through product action policy" do
    assert {:ok, requested} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "requested",
               %{
                 backfill_lifecycle_event_id: "stage-transition-requested",
                 backfill_run_id: "stage-transition-run",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 reason: "operator_requested_backfill",
                 payload: %{
                   "dashboard_context" => %{
                     "dashboard_id" => "dashboard-stage",
                     "dashboard_version" => "3",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-stage-product",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   },
                   "comparison_review_origin" => %{
                     "request_event_id" => "review-request-stage",
                     "request_kind" => "comparison_open_findings_review",
                     "open_count" => "1",
                     "open_placement_ids" => "placement-stage"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:historical_workflow_stage_transition_blocked, "stage-transition-requested",
             "stage_transition_out_of_order"}} =
             Cadence.record_telemetry_historical_data_workflow_stage_transition(
               "backfill",
               "completed",
               requested.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 reason: "operator_completed_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, approved} =
             Cadence.record_telemetry_historical_data_workflow_stage_transition(
               "backfill",
               "approved",
               requested.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 reason: "operator_approved_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.event_type == :backfill_approved
    assert approved.backfill_run_id == requested.backfill_run_id
    assert approved.payload["stage_transition_source"] == "dashboard_stage_action"
    assert approved.payload["source_event_id"] == requested.backfill_lifecycle_event_id
    assert approved.payload["source_event_type"] == "backfill_requested"

    assert approved.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-stage",
             "dashboard_version" => "3",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-stage-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert approved.payload["comparison_review_origin"] == %{
             "request_event_id" => "review-request-stage",
             "request_kind" => "comparison_open_findings_review",
             "open_count" => "1",
             "open_placement_ids" => "placement-stage"
           }

    assert {:error,
            {:historical_workflow_stage_transition_blocked, blocked_event_id, "already_in_stage"}} =
             Cadence.record_telemetry_historical_data_workflow_stage_transition(
               "backfill",
               "approved",
               approved.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 reason: "operator_approved_backfill_again"
               },
               dashboard_runtime_invalidation?: false
             )

    assert blocked_event_id == approved.backfill_lifecycle_event_id
  end

  test "event-only late-data policy records audit semantics without projection claims" do
    assert {:ok, event} =
             Cadence.record_telemetry_late_data_policy_decision(
               :accept,
               %{
                 backfill_run_id: "late-policy-event-only",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 execution_mode: "event_only",
                 payload: %{
                   "dashboard_context" => %{
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-policy-product",
                     "dashboard_limit_mode" => "compare"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :late_data_accepted
    assert event.payload["execution_mode"] == "event_only"
    assert event.payload["projection_effect"] == "audit_event_only"
    refute event.payload["record_current_values"]
    refute event.payload["refresh_latest_value"]

    assert event.payload["dashboard_context"] == %{
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-policy-product",
             "dashboard_limit_mode" => "compare"
           }
  end

  test "late-data policy write opts drive current projection behavior", %{
    persistence_policy: persistence_policy
  } do
    baseline =
      sample("sample-late-policy-baseline", ~U[2026-06-22 10:00:00Z], ~U[2026-06-22 10:00:03Z],
        raw_value: 10
      )

    accepted =
      sample("sample-late-policy-accepted", ~U[2026-06-22 10:05:00Z], ~U[2026-06-22 12:05:03Z],
        raw_value: 20
      )

    rejected =
      sample("sample-late-policy-rejected", ~U[2026-06-22 10:10:00Z], ~U[2026-06-22 12:10:03Z],
        raw_value: 99
      )

    assert :ok =
             Storage.persist_samples(persistence_policy.storage, [baseline],
               organization_id: "org-product"
             )

    assert_receive {:telemetry_storage_envelopes, [_baseline_envelope]}

    assert {:ok, accept_opts} =
             Cadence.telemetry_late_data_policy_write_opts(:accept,
               organization_id: "org-product",
               backfill_run_id: "late-policy-accept-run",
               recorded_at: ~U[2026-06-22 12:05:05Z],
               dashboard_runtime_invalidation?: false
             )

    assert :ok = Storage.persist_samples(persistence_policy.storage, [accepted], accept_opts)
    assert_receive {:telemetry_storage_envelopes, [_accepted_envelope]}

    latest =
      TelemetryReads.latest_value(
        "mission-product",
        "HK.counter",
        telemetry_read_opts([spacecraft_id: "sc-1"], persistence_policy)
      )

    assert latest.sample_id == "sample-late-policy-accepted"
    assert latest.raw_value == 20
    assert latest.provenance["storage"]["validity_state"] == "canonical"

    assert {:ok, reject_opts} =
             Cadence.telemetry_late_data_policy_write_opts(:reject,
               organization_id: "org-product",
               backfill_run_id: "late-policy-reject-run",
               recorded_at: ~U[2026-06-22 12:10:05Z],
               dashboard_runtime_invalidation?: false
             )

    assert :ok = Storage.persist_samples(persistence_policy.storage, [rejected], reject_opts)
    assert_receive {:telemetry_storage_envelopes, [_rejected_envelope]}

    latest =
      TelemetryReads.latest_value(
        "mission-product",
        "HK.counter",
        telemetry_read_opts([spacecraft_id: "sc-1"], persistence_policy)
      )

    assert latest.sample_id == "sample-late-policy-accepted"
    assert latest.raw_value == 20
  end

  test "executes accepted late-data policy by selecting source samples and writing canonical history",
       %{persistence_policy: persistence_policy} do
    assert :ok =
             HistoryStore.persist_samples(
               persistence_policy.history_store,
               [
                 sample(
                   "sample-late-source-before",
                   ~U[2026-06-22 09:59:00Z],
                   ~U[2026-06-22 11:59:03Z],
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   raw_value: 9
                 ),
                 sample(
                   "sample-late-source-selected",
                   ~U[2026-06-22 10:10:00Z],
                   ~U[2026-06-22 12:10:03Z],
                   realm: :backfill,
                   data_source_id: "managed_questdb_backfill",
                   binding_id: "backfill_telemetry",
                   raw_value: 42
                 )
               ]
             )

    assert {:ok, %{event: event, sample_count: 1, diagnostics: diagnostics}} =
             Cadence.execute_telemetry_late_data_policy(
               :accept,
               %{
                 backfill_run_id: "late-policy-execute-accept",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 source_realm: :backfill,
                 source_data_source_id: "managed_questdb_backfill",
                 source_binding_id: "backfill_telemetry",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 10:30:00Z],
                 receipt_from: ~U[2026-06-22 12:00:00Z],
                 receipt_to: ~U[2026-06-22 12:30:00Z],
                 reason: "operator_accepts_late_data"
               },
               dashboard_runtime_invalidation?: false,
               persistence_policy: persistence_policy
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-late-source-selected"
    assert envelope.realm == :flight
    assert envelope.data_source_id == "managed_questdb_primary"
    assert envelope.binding_id == "default_flight_telemetry"
    assert envelope.validity_state == :canonical

    assert event.event_type == :late_data_accepted
    assert event.sample_count == 1
    assert event.payload["selected_sample_count"] == 1
    assert event.payload["projection_effect"] == "canonical_history_and_current_projection"
    assert event.payload["source"]["source_identity"]["realm"] == "backfill"
    assert diagnostics["point_id"] == "HK.counter"
  end

  test "executes rejected late-data policy as advisory history without current projection", %{
    persistence_policy: persistence_policy
  } do
    baseline =
      sample("sample-late-reject-baseline", ~U[2026-06-22 10:00:00Z], ~U[2026-06-22 10:00:03Z],
        raw_value: 10
      )

    late =
      sample("sample-late-reject-source", ~U[2026-06-22 10:20:00Z], ~U[2026-06-22 12:20:03Z],
        realm: :backfill,
        data_source_id: "managed_questdb_backfill",
        binding_id: "backfill_telemetry",
        raw_value: 99
      )

    assert :ok =
             Storage.persist_samples(persistence_policy.storage, [baseline],
               organization_id: "org-product"
             )

    assert_receive {:telemetry_storage_envelopes, [_baseline_envelope]}
    assert :ok = HistoryStore.persist_samples(persistence_policy.history_store, [late])

    assert {:ok, %{event: event, sample_count: 1}} =
             Cadence.execute_telemetry_late_data_policy(
               "reject",
               %{
                 backfill_run_id: "late-policy-execute-reject",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :flight,
                 data_source_id: "managed_questdb_primary",
                 binding_id: "default_flight_telemetry",
                 source_realm: :backfill,
                 source_data_source_id: "managed_questdb_backfill",
                 source_binding_id: "backfill_telemetry",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:10:00Z],
                 source_to: ~U[2026-06-22 10:30:00Z],
                 receipt_from: ~U[2026-06-22 12:10:00Z],
                 receipt_to: ~U[2026-06-22 12:30:00Z],
                 reason: "operator_rejects_late_data"
               },
               dashboard_runtime_invalidation?: false,
               persistence_policy: persistence_policy
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-late-reject-source"
    assert envelope.validity_state == :advisory

    latest =
      TelemetryReads.latest_value(
        "mission-product",
        "HK.counter",
        telemetry_read_opts([spacecraft_id: "sc-1"], persistence_policy)
      )

    assert latest.sample_id == "sample-late-reject-baseline"
    assert latest.raw_value == 10

    assert event.event_type == :late_data_rejected
    assert event.sample_count == 1
    assert event.payload["projection_effect"] == "advisory_history_only"
    assert event.payload["record_current_values"] == false
    assert event.payload["refresh_latest_value"] == false
  end

  test "backfills telemetry samples through storage with lifecycle events", %{
    persistence_policy: persistence_policy
  } do
    samples = [
      sample("sample-backfill-1", ~U[2026-06-22 11:00:00Z], ~U[2026-06-22 12:00:03Z]),
      sample("sample-backfill-2", ~U[2026-06-22 11:05:00Z], ~U[2026-06-22 12:05:03Z])
    ]

    assert :ok =
             Cadence.backfill_telemetry_samples(
               samples,
               %{
                 backfill_run_id: "backfill-run-product",
                 organization_id: "org-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 source_endpoint_id: "station-a",
                 recorded_at: ~U[2026-06-22 12:05:05Z],
                 actor_id: "operator-1",
                 actor_kind: "user"
               },
               dashboard_runtime_invalidation?: false,
               persistence_policy: persistence_policy
             )

    assert_receive {:telemetry_storage_envelopes, envelopes}
    assert Enum.map(envelopes, & &1.sample_id) == ["sample-backfill-1", "sample-backfill-2"]
    assert Enum.all?(envelopes, &(&1.realm == :backfill))
    assert Enum.all?(envelopes, &(&1.data_source_id == "managed_questdb_backfill"))
    assert Enum.all?(envelopes, &(&1.binding_id == "backfill_telemetry"))

    events =
      "mission-product"
      |> Storage.list_backfill_lifecycle_events(
        organization_id: "org-product",
        backfill_run_id: "backfill-run-product"
      )
      |> Enum.sort_by(&event_stage_order/1)

    assert Enum.map(events, & &1.event_type) == [
             :backfill_requested,
             :backfill_approved,
             :backfill_started,
             :backfill_completed
           ]

    assert Enum.all?(events, &(&1.sample_count == 2))
    assert Enum.all?(events, &(&1.source_from == ~U[2026-06-22 11:00:00.000000Z]))
    assert Enum.all?(events, &(&1.source_to == ~U[2026-06-22 11:05:00.000000Z]))
    assert Enum.all?(events, &(&1.receipt_from == ~U[2026-06-22 12:00:03.000000Z]))
    assert Enum.all?(events, &(&1.receipt_to == ~U[2026-06-22 12:05:03.000000Z]))
    assert Enum.all?(events, &(&1.observable_id == "HK.counter"))
    assert Enum.all?(events, &(&1.spacecraft_id == "sc-1"))
  end

  test "imports telemetry samples through storage with lifecycle events", %{
    persistence_policy: persistence_policy
  } do
    samples = [sample("sample-import-1", ~U[2026-06-22 11:00:00Z], ~U[2026-06-22 12:00:03Z])]

    assert :ok =
             Cadence.import_telemetry_samples(
               samples,
               %{
                 import_run_id: "import-run-product",
                 organization_id: "org-product",
                 realm: :rehearsal,
                 data_source_id: "managed_questdb_rehearsal",
                 binding_id: "rehearsal_telemetry",
                 source_endpoint_id: "station-a",
                 recorded_at: ~U[2026-06-22 12:00:05Z]
               },
               dashboard_runtime_invalidation?: false,
               persistence_policy: persistence_policy
             )

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-import-1"
    assert envelope.realm == :rehearsal
    assert envelope.data_source_id == "managed_questdb_rehearsal"
    assert envelope.binding_id == "rehearsal_telemetry"

    events =
      "mission-product"
      |> Storage.list_backfill_lifecycle_events(
        organization_id: "org-product",
        backfill_run_id: "import-run-product"
      )
      |> Enum.sort_by(&event_stage_order/1)

    assert Enum.map(events, & &1.event_type) == [
             :import_requested,
             :import_approved,
             :import_started,
             :import_completed
           ]
  end

  test "records historical data workflow stage events without writing samples" do
    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "requested",
               %{
                 backfill_run_id: "backfill-run-requested",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :advisory,
                 reason: "operator_requested_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :backfill_requested
    assert event.backfill_run_id == "backfill-run-requested"
    assert event.authority == :advisory
    assert event.payload["workflow"] == "backfill"
    assert event.payload["stage"] == "requested"
    assert event.payload["run_id"] == "backfill-run-requested"
    assert event.payload["requested_event_type"] == "backfill_requested"

    assert [listed] =
             Storage.list_backfill_lifecycle_events("mission-product",
               organization_id: "org-product",
               backfill_run_id: "backfill-run-requested"
             )

    assert listed.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id
    assert listed.event_type == :backfill_requested
    assert listed.payload["stage"] == "requested"
  end

  test "records historical data workflow requests through the product API" do
    attrs = %{
      backfill_run_id: "backfill-run-request-group",
      organization_id: "org-product",
      mission_id: "mission-product",
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2026-06-22 10:00:00Z],
      source_to: ~U[2026-06-22 11:00:00Z],
      authority: :unknown,
      reason: "operator_requested_backfill",
      actor_id: "operator-2",
      actor_kind: "operator",
      payload: %{
        "dashboard_context" => %{
          "dashboard_id" => "dashboard-power",
          "dashboard_version" => "4"
        },
        "comparison_review_origin" => %{
          "request_event_id" => "review-request-group",
          "request_kind" => "comparison_open_findings_review",
          "open_count" => "2",
          "open_placement_ids" => "placement-counter,placement-voltage",
          "workflow_kind" => "bulk_correction_authority_review",
          "workflow_action" => "request_comparison_review",
          "workflow_selection_kind" => "open_comparison_findings",
          "workflow_selection_count" => "2",
          "primary_data_view" => "all_revisions",
          "compare_data_view" => "canonical"
        },
        "operator_note" => "AI&T replay gap"
      }
    }

    assert {:ok, events} =
             Cadence.record_telemetry_historical_data_workflow_request(
               "backfill",
               attrs,
               ["HK.counter", "HK.voltage"],
               dashboard_runtime_invalidation?: false
             )

    assert Enum.map(events, & &1.backfill_run_id) == [
             "backfill-run-request-group-001",
             "backfill-run-request-group-002"
           ]

    assert Enum.map(events, & &1.point_id) == ["HK.counter", "HK.voltage"]
    assert Enum.all?(events, &(&1.event_type == :backfill_requested))
    assert Enum.all?(events, &(&1.reason == "operator_requested_backfill"))
    assert Enum.all?(events, &(&1.payload["request_mode"] == "bulk_points"))
    assert Enum.map(events, & &1.payload["request_item_index"]) == [1, 2]
    assert Enum.all?(events, &(&1.payload["request_item_count"] == 2))
    assert Enum.all?(events, &(&1.payload["request_group_id"] == "backfill-run-request-group"))
    assert Enum.all?(events, &(&1.payload["operator_note"] == "AI&T replay gap"))

    assert Enum.all?(
             events,
             &(&1.payload["comparison_review_origin"] == %{
                 "request_event_id" => "review-request-group",
                 "request_kind" => "comparison_open_findings_review",
                 "open_count" => "2",
                 "open_placement_ids" => "placement-counter,placement-voltage",
                 "workflow_kind" => "bulk_correction_authority_review",
                 "workflow_action" => "request_comparison_review",
                 "workflow_selection_kind" => "open_comparison_findings",
                 "workflow_selection_count" => "2",
                 "primary_data_view" => "all_revisions",
                 "compare_data_view" => "canonical"
               })
           )

    assert Enum.all?(
             events,
             &(&1.payload["dashboard_context"] == %{
                 "dashboard_id" => "dashboard-power",
                 "dashboard_version" => "4"
               })
           )

    assert Enum.map(events, & &1.payload["request_item_run_id"]) ==
             ["backfill-run-request-group-001", "backfill-run-request-group-002"]
  end

  test "records single historical data workflow request without an explicit point" do
    assert {:ok, [event]} =
             Cadence.record_telemetry_historical_data_workflow_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-request-single",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :unknown,
                 reason: "operator_requested_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               [],
               dashboard_runtime_invalidation?: false
             )

    assert event.backfill_run_id == "backfill-run-request-single"
    assert event.point_id == nil
    assert event.observable_id == nil
    assert event.payload["request_mode"] == "single_point"
    assert event.payload["request_group_id"] == "backfill-run-request-single"
    assert event.payload["request_item_index"] == 1
    assert event.payload["request_item_count"] == 1
    assert event.payload["request_item_run_id"] == "backfill-run-request-single"
  end

  test "records corrected historical data workflow request through the product API" do
    failed_job = failed_historical_workflow_job("backfill-run-original")

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-event-original",
               "backfill-run-original",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-original-group",
               item_count: 1,
               job_id: failed_job.job_id,
               point_id: "HK.counter",
               observable_id: "HK.counter",
               dashboard_context: %{
                 "dashboard_id" => "dashboard-correction",
                 "dashboard_version" => "5",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-correction-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :unknown,
                 reason: "operator_corrected_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               %{
                 "original_run_id" => "",
                 "original_event_id" => source_event.backfill_lifecycle_event_id,
                 "original_job_id" => ""
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :backfill_requested
    assert event.backfill_run_id == "backfill-run-corrected"
    assert event.payload["recovery_action"] == "correct_workflow_request"
    assert event.payload["correction_source"] == "dashboard_correction_request"
    assert event.payload["correction_source_event_type"] == "backfill_failed"
    assert event.payload["corrects_run_id"] == "backfill-run-original"
    assert event.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert event.payload["corrects_job_id"] == failed_job.job_id
    assert event.payload["request_group_id"] == "backfill-run-original-group"
    assert event.payload["request_item_index"] == 1
    assert event.payload["request_item_count"] == 1
    assert event.payload["workflow"] == "backfill"
    assert event.payload["stage"] == "requested"

    assert event.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-correction",
             "dashboard_version" => "5",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }
  end

  test "rejects corrected historical workflow requests without a valid correction source" do
    assert {:error, {:historical_workflow_correction_source_not_found, "missing-event"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-missing-source",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => "missing-event"},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, retryable_source_event} =
             record_group_failed_event(
               "failed-event-retryable-source",
               "backfill-run-retryable-source",
               1,
               retryable: true,
               request_group_id: "backfill-run-retryable-source-group",
               item_count: 1
             )

    assert {:error,
            {:invalid_historical_workflow_correction_source, "failed-event-retryable-source",
             :correction_not_required}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-retryable-source",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => retryable_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, backfill_source_event} =
             record_group_failed_event(
               "failed-event-workflow-mismatch-source",
               "backfill-run-workflow-mismatch-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-workflow-mismatch-source-group",
               item_count: 1
             )

    assert {:error,
            {:invalid_historical_workflow_correction_source,
             "failed-event-workflow-mismatch-source", :workflow_mismatch}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "import",
               %{
                 import_run_id: "import-run-corrected-mismatch",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_import"
               },
               %{"original_event_id" => backfill_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, missing_job_source_event} =
             record_group_failed_event(
               "failed-event-missing-job-source",
               "backfill-run-missing-job-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-missing-job-source-group",
               item_count: 1
             )

    assert {:error,
            {:historical_workflow_correction_request_blocked, "failed-event-missing-job-source",
             "job_status_missing"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-missing-job",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => missing_job_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-queued-correction-source",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert {:ok, queued_job_source_event} =
             record_group_failed_event(
               "failed-event-queued-job-source",
               "backfill-run-queued-correction-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-queued-correction-source-group",
               item_count: 1,
               job_id: queued_job.job_id
             )

    assert {:error,
            {:historical_workflow_correction_request_blocked, "failed-event-queued-job-source",
             "job_not_failed"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-queued-job",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => queued_job_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert [claimed_queued_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_queued_job.job_id == queued_job.job_id

    mismatched_failed_job = failed_historical_workflow_job("backfill-run-job-id-mismatch-source")

    assert {:ok, mismatched_job_source_event} =
             record_group_failed_event(
               "failed-event-job-id-mismatch-source",
               "backfill-run-job-id-mismatch-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-job-id-mismatch-source-group",
               item_count: 1,
               job_id: "other-#{mismatched_failed_job.job_id}"
             )

    assert {:error,
            {:historical_workflow_correction_request_blocked,
             "failed-event-job-id-mismatch-source", :job_id_mismatch}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-corrected-job-id-mismatch",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => mismatched_job_source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )
  end

  test "records corrected historical workflow transitions through the product API" do
    failed_job = failed_historical_workflow_job("backfill-run-correction-transition-source")

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-event-correction-transition",
               "backfill-run-correction-transition-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-correction-transition-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-correction-transition",
                 "dashboard_version" => "6",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-correction-transition-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-correction-transition",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, stale_correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-stale-correction-transition",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill_again"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, approved} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "approved",
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.event_type == :backfill_approved
    assert approved.backfill_run_id == correction_request.backfill_run_id
    assert approved.reason == "operator_approved_corrected_backfill"
    assert approved.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert approved.payload["correction_transition_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert approved.payload["corrects_run_id"] == source_event.backfill_run_id
    assert approved.payload["corrects_job_id"] == failed_job.job_id

    assert approved.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-correction-transition",
             "dashboard_version" => "6",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-transition-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    correction_request_id = correction_request.backfill_lifecycle_event_id

    assert {:error,
            {:historical_workflow_correction_transition_blocked, ^correction_request_id,
             "stage_transition_out_of_order"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "completed",
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_completed_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, started} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "started",
               approved.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_started_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started.event_type == :backfill_started
    assert started.payload["dashboard_context"] == approved.payload["dashboard_context"]

    assert {:ok, completed} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "completed",
               started.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_completed_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert completed.event_type == :backfill_completed
    assert completed.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert completed.payload["dashboard_context"] == approved.payload["dashboard_context"]

    assert {:error,
            {:historical_workflow_correction_source_superseded,
             "failed-event-correction-transition"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "approved",
               stale_correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_approved_stale_corrected_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:historical_workflow_correction_source_superseded,
             "failed-event-correction-transition"}} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-correction-after-completed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_backfill_after_completed"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, normal_request} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "requested",
               %{
                 backfill_lifecycle_event_id: "normal-request-event",
                 backfill_run_id: "backfill-run-normal-request",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_requested_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:invalid_historical_workflow_correction_event, "normal-request-event",
             :missing_source_event}} =
             Cadence.record_telemetry_historical_data_workflow_correction_transition(
               "backfill",
               "approved",
               normal_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 authority: :authoritative,
                 reason: "operator_approved_normal_request"
               },
               dashboard_runtime_invalidation?: false
             )
  end
end
