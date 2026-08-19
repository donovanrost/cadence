defmodule Cadence.Telemetry.DataManagementGroupWorkflowTest do
  use Cadence.ConfigCase, async: false

  import Cadence.Telemetry.DataManagementFixtures

  alias Cadence.Jobs.Runner, as: JobRunner

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

  test "records historical data workflow retry events without writing samples" do
    assert {:ok, event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "retried",
               %{
                 backfill_run_id: "backfill-run-retried",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: ~U[2026-06-22 10:00:00Z],
                 source_to: ~U[2026-06-22 11:00:00Z],
                 authority: :authoritative,
                 reason: "dashboard_historical_workflow_retried",
                 actor_id: "operator-2",
                 actor_kind: "operator",
                 payload: %{
                   "retry_action" => "retry_job",
                   "retry_source_event_id" => "telemetry_backfill_lifecycle_event_failed",
                   "retry_job_id" => "job-retried",
                   "retry_job_status" => "queued"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert event.event_type == :backfill_retried
    assert event.authority == :authoritative
    assert event.reason == "dashboard_historical_workflow_retried"
    assert event.payload["workflow"] == "backfill"
    assert event.payload["stage"] == "retried"
    assert event.payload["requested_event_type"] == "backfill_retried"
    assert event.payload["retry_action"] == "retry_job"
    assert event.payload["retry_source_event_id"] == "telemetry_backfill_lifecycle_event_failed"
    assert event.payload["retry_job_id"] == "job-retried"
    assert event.payload["retry_job_status"] == "queued"
  end

  test "records historical data workflow group transitions through the product API" do
    requested_events =
      for index <- 1..2 do
        run_id = "backfill-run-group-#{index}"
        point_id = "HK.group#{index}"

        assert {:ok, event} =
                 Cadence.record_telemetry_historical_data_workflow_event(
                   "backfill",
                   "requested",
                   %{
                     backfill_run_id: run_id,
                     organization_id: "org-product",
                     mission_id: "mission-product",
                     realm: :backfill,
                     data_source_id: "managed_questdb_backfill",
                     binding_id: "backfill_telemetry",
                     observable_id: point_id,
                     point_id: point_id,
                     source_from: ~U[2026-06-22 10:00:00Z],
                     source_to: ~U[2026-06-22 11:00:00Z],
                     authority: :unknown,
                     reason: "operator_requested_group_backfill",
                     actor_id: "operator-2",
                     actor_kind: "operator",
                     payload: %{
                       "request_source" => "dashboard",
                       "request_mode" => "bulk_points",
                       "request_group_id" => "backfill-run-group",
                       "request_item_index" => index,
                       "request_item_count" => 2,
                       "request_item_run_id" => run_id,
                       "dashboard_context" => %{
                         "dashboard_id" => "dashboard-group",
                         "dashboard_version" => "8",
                         "dashboard_time_mode" => "replay_run",
                         "dashboard_replay_run_id" => "replay-group-product",
                         "dashboard_data_view" => "all_revisions",
                         "dashboard_limit_mode" => "observed"
                       },
                       "comparison_review_origin" => %{
                         "request_event_id" => "review-request-group-transition",
                         "request_kind" => "comparison_open_findings_review",
                         "open_count" => "2",
                         "open_placement_ids" => "placement-counter,placement-voltage",
                         "workflow_kind" => "bulk_correction_authority_review",
                         "workflow_action" => "request_comparison_review",
                         "workflow_selection_kind" => "open_comparison_findings",
                         "workflow_selection_count" => "2",
                         "primary_data_view" => "all_revisions",
                         "compare_data_view" => "canonical"
                       }
                     }
                   },
                   dashboard_runtime_invalidation?: false
                 )

        event
      end

    assert {:ok, approved_events, job_results} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "backfill-run-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert length(approved_events) == 2
    assert job_results == [{:ok, nil}, {:ok, nil}]

    assert Enum.map(approved_events, & &1.backfill_run_id) == [
             "backfill-run-group-1",
             "backfill-run-group-2"
           ]

    assert Enum.all?(approved_events, &(&1.reason == "operator_approved_group_backfill"))

    assert Enum.all?(
             approved_events,
             &(&1.payload["group_transition_source"] == "dashboard_group_action")
           )

    assert Enum.all?(
             approved_events,
             &(&1.payload["dashboard_context"] == %{
                 "dashboard_id" => "dashboard-group",
                 "dashboard_version" => "8",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-group-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               })
           )

    assert Enum.all?(
             approved_events,
             &(&1.payload["comparison_review_origin"] == %{
                 "request_event_id" => "review-request-group-transition",
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

    assert Enum.map(approved_events, & &1.payload["requested_event_id"]) ==
             Enum.map(requested_events, & &1.backfill_lifecycle_event_id)

    assert {:error, {:no_eligible_items, "approved"}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "backfill-run-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_duplicate_group_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error, {:request_group_not_found, "missing-group"}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "missing-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_missing_group_backfill"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error, {:missing_field, :request_group_id}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               nil,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_missing_group_backfill"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "records corrected group transitions through the correction transition API" do
    failed_job = failed_historical_workflow_job("backfill-run-correction-group-source")

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-event-correction-group-transition",
               "backfill-run-correction-group-source",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "backfill-run-correction-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-correction-group",
                 "dashboard_version" => "9",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-correction-group-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-correction-group-fixed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_group_backfill"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, [approved], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               "backfill-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.backfill_run_id == correction_request.backfill_run_id
    assert approved.payload["group_transition_source"] == "dashboard_group_action"
    assert approved.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert approved.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id

    assert approved.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-correction-group",
             "dashboard_version" => "9",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-group-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert {:ok, [started], [{:ok, started_job}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "started",
               "backfill-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_corrected_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started.backfill_run_id == correction_request.backfill_run_id
    assert started.payload["group_transition_source"] == "dashboard_group_action"
    assert started.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert started.payload["correction_transition_source_event_id"] ==
             approved.backfill_lifecycle_event_id

    assert started.payload["corrects_run_id"] == source_event.backfill_run_id
    assert started.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert started_job.status == :queued
    assert started_job.run_id == correction_request.backfill_run_id

    assert {:ok, [completed], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "completed",
               "backfill-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_completed_corrected_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert completed.backfill_run_id == correction_request.backfill_run_id
    assert completed.payload["group_transition_source"] == "dashboard_group_action"
    assert completed.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert completed.payload["correction_transition_source_event_id"] ==
             started.backfill_lifecycle_event_id

    assert completed.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert completed.payload["corrects_run_id"] == source_event.backfill_run_id
    assert completed.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
  end

  test "starts corrected import workflow group transition jobs through the product API", %{
    persistence_policy: persistence_policy
  } do
    failed_job =
      failed_historical_workflow_job("import-run-correction-group-source", workflow: :import)

    assert {:ok, source_event} =
             record_group_failed_event(
               "import-failed-event-correction-group-transition",
               "import-run-correction-group-source",
               1,
               workflow: :import,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "import-run-correction-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-import-correction-group",
                 "dashboard_version" => "9",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-import-correction-group-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "import",
               %{
                 import_run_id: "import-run-correction-group-fixed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_group_import"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert correction_request.event_type == :import_requested
    assert correction_request.backfill_run_id == "import-run-correction-group-fixed"
    assert correction_request.payload["workflow"] == "import"
    assert correction_request.payload["correction_source"] == "dashboard_correction_request"
    assert correction_request.payload["correction_source_event_type"] == "import_failed"

    assert correction_request.payload["corrects_event_id"] ==
             source_event.backfill_lifecycle_event_id

    assert correction_request.payload["corrects_job_id"] == failed_job.job_id

    assert correction_request.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-import-correction-group",
             "dashboard_version" => "9",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-import-correction-group-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert {:ok, [approved], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "approved",
               "import-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert approved.event_type == :import_approved
    assert approved.backfill_run_id == correction_request.backfill_run_id
    assert approved.payload["group_transition_source"] == "dashboard_group_action"
    assert approved.payload["correction_source"] == "dashboard_correction_request"
    assert approved.payload["correction_source_event_type"] == "import_failed"
    assert approved.payload["correction_transition_source"] == "dashboard_correction_transition"

    assert approved.payload["requested_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert approved.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id

    assert {:ok, [started], [{:ok, started_job}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "started",
               "import-run-correction-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started.event_type == :import_started
    assert started.backfill_run_id == correction_request.backfill_run_id
    assert started.payload["correction_source"] == "dashboard_correction_request"
    assert started.payload["correction_source_event_type"] == "import_failed"
    assert started.payload["correction_transition_source"] == "dashboard_correction_transition"
    assert started.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert started_job.status == :queued
    assert started_job.run_id == "import-run-correction-group-fixed"
    assert started_job.payload["workflow"] == "import"
    assert started_job.payload["attrs"]["import_run_id"] == "import-run-correction-group-fixed"

    assert started_job.payload["attrs"]["payload"]["correction_source"] ==
             "dashboard_correction_request"

    assert started_job.payload["attrs"]["payload"]["correction_source_event_type"] ==
             "import_failed"

    assert :ok =
             HistoryStore.persist_samples(
               persistence_policy.history_store,
               [
                 sample(
                   "sample-import-corrected-source",
                   ~U[2026-06-22 10:20:00Z],
                   ~U[2026-06-22 10:20:03Z],
                   point_id: "HK.group_failed1",
                   realm: :backfill,
                   data_source_id: "customer_archive_import",
                   binding_id: "import_telemetry",
                   raw_value: 88
                 )
               ]
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == started_job.job_id

    assert {:ok, completed_job} =
             JobRunner.run_job(data_management_job_runner(persistence_policy), claimed_job.job_id)

    assert completed_job.status == :completed

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-import-corrected-source"
    assert envelope.raw_value == 88
    assert envelope.realm == :backfill
    assert envelope.data_source_id == "customer_archive_import"
    assert envelope.binding_id == "import_telemetry"

    events =
      Storage.list_backfill_lifecycle_events("mission-product",
        organization_id: "org-product",
        backfill_run_id: "import-run-correction-group-fixed"
      )

    assert Enum.map(events, & &1.event_type) == [
             :import_requested,
             :import_approved,
             :import_started,
             :import_completed
           ]

    completed = List.last(events)
    assert completed.reason == "historical_data_job_completed"
    assert completed.sample_count == 1
    assert completed.payload["workflow"] == "import"
    assert completed.payload["workflow_job_status"] == "completed"
    assert completed.payload["job_id"] == started_job.job_id
    assert completed.payload["request_group_id"] == "import-run-correction-group"
    assert completed.payload["request_item_index"] == 1
    assert completed.payload["request_item_count"] == 1
    assert completed.payload["correction_source"] == "dashboard_correction_request"
    assert completed.payload["correction_source_event_type"] == "import_failed"
    assert completed.payload["recovery_action"] == "correct_workflow_request"
    assert completed.payload["corrects_run_id"] == "import-run-correction-group-source"
    assert completed.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert completed.payload["corrects_job_id"] == failed_job.job_id

    assert completed.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-import-correction-group",
             "dashboard_version" => "9",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-import-correction-group-product",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }
  end

  test "retries failed corrected import replacement jobs through the product API" do
    failed_job =
      failed_historical_workflow_job("import-run-correction-retry-source", workflow: :import)

    assert {:ok, source_event} =
             record_group_failed_event(
               "import-failed-event-correction-retry-source",
               "import-run-correction-retry-source",
               1,
               workflow: :import,
               retryable: true,
               recovery_action: "correct_workflow_request",
               request_group_id: "import-run-correction-retry-group",
               item_count: 1,
               job_id: failed_job.job_id,
               dashboard_context: %{
                 "dashboard_id" => "dashboard-import-correction-retry",
                 "dashboard_version" => "10",
                 "dashboard_time_mode" => "replay_run",
                 "dashboard_replay_run_id" => "replay-import-correction-retry-product",
                 "dashboard_data_view" => "all_revisions",
                 "dashboard_limit_mode" => "observed"
               }
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "import",
               %{
                 import_run_id: "import-run-correction-retry-fixed",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :unknown,
                 reason: "operator_corrected_group_import"
               },
               %{"original_event_id" => source_event.backfill_lifecycle_event_id},
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, [_approved], [{:ok, nil}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "approved",
               "import-run-correction-retry-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, [_started], [{:ok, started_job}]} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "import",
               "started",
               "import-run-correction-retry-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "customer_archive_import",
                 binding_id: "import_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_corrected_group_import",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert started_job.status == :queued

    failing_policy =
      data_management_persistence_policy(
        history_store: Cadence.TestSupport.FailingHistoryStore,
        failure_reason: :source_unavailable
      )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == started_job.job_id

    assert {:ok, failed_run_job} =
             JobRunner.run_job(data_management_job_runner(failing_policy), claimed_job.job_id)

    assert failed_run_job.status == :failed

    assert {:ok, failed_replacement_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "import-run-correction-retry-fixed"
             )

    assert failed_replacement_job.status == :failed

    events =
      Storage.list_backfill_lifecycle_events("mission-product",
        organization_id: "org-product",
        backfill_run_id: "import-run-correction-retry-fixed"
      )

    assert Enum.map(events, & &1.event_type) == [
             :import_requested,
             :import_approved,
             :import_started,
             :import_failed
           ]

    failed_replacement_event = List.last(events)
    assert failed_replacement_event.payload["workflow"] == "import"
    assert failed_replacement_event.payload["workflow_job_status"] == "failed"
    assert failed_replacement_event.payload["job_id"] == started_job.job_id

    assert failed_replacement_event.payload["request_group_id"] ==
             "import-run-correction-retry-group"

    assert failed_replacement_event.payload["request_item_index"] == 1
    assert failed_replacement_event.payload["request_item_count"] == 1
    assert failed_replacement_event.payload["correction_source"] == "dashboard_correction_request"
    assert failed_replacement_event.payload["correction_source_event_type"] == "import_failed"
    assert failed_replacement_event.payload["recovery_action"] == "correct_workflow_request"
    assert failed_replacement_event.payload["source"]["failure"]["retryable"] == true
    assert failed_replacement_event.payload["source"]["failure"]["recovery_action"] == "retry_job"

    assert failed_replacement_event.payload["corrects_event_id"] ==
             source_event.backfill_lifecycle_event_id

    assert failed_replacement_event.payload["corrects_job_id"] == failed_job.job_id

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "import-run-correction-retry-group",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-3",
                 actor_kind: "operator"
               },
               retry_run_ids: [correction_request.backfill_run_id],
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 1
    assert summary.nonretryable == 0
    assert summary.skipped == 0
    assert summary.failed == 0
    assert summary.retry_error_items == []
    assert [retry_event] = summary.events
    assert retry_event.event_type == :import_retried
    assert retry_event.backfill_run_id == correction_request.backfill_run_id

    assert retry_event.payload["retry_source_event_id"] ==
             failed_replacement_event.backfill_lifecycle_event_id

    assert retry_event.payload["retry_source_event_type"] == "import_failed"
    assert retry_event.payload["retry_job_id"] == started_job.job_id
    assert retry_event.payload["request_group_id"] == "import-run-correction-retry-group"
    assert retry_event.payload["correction_source"] == "dashboard_correction_request"
    assert retry_event.payload["correction_source_event_type"] == "import_failed"
    assert retry_event.payload["corrects_event_id"] == source_event.backfill_lifecycle_event_id
    assert retry_event.payload["corrects_job_id"] == failed_job.job_id

    assert {:ok, retried_replacement_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "import-run-correction-retry-fixed"
             )

    assert retried_replacement_job.status == :queued
  end

  test "starts historical data workflow group transition jobs through the product API" do
    requested_events =
      for index <- 1..2 do
        run_id = "backfill-run-group-start-#{index}"
        point_id = "HK.group_start#{index}"

        assert {:ok, event} =
                 Cadence.record_telemetry_historical_data_workflow_event(
                   "backfill",
                   "requested",
                   %{
                     backfill_run_id: run_id,
                     organization_id: "org-product",
                     mission_id: "mission-product",
                     realm: :backfill,
                     data_source_id: "managed_questdb_backfill",
                     binding_id: "backfill_telemetry",
                     observable_id: point_id,
                     point_id: point_id,
                     source_from: ~U[2026-06-22 10:00:00Z],
                     source_to: ~U[2026-06-22 11:00:00Z],
                     authority: :unknown,
                     reason: "operator_requested_group_start_backfill",
                     actor_id: "operator-2",
                     actor_kind: "operator",
                     payload: %{
                       "request_group_id" => "backfill-run-group-start",
                       "request_item_index" => index,
                       "request_item_count" => 2
                     }
                   },
                   dashboard_runtime_invalidation?: false
                 )

        event
      end

    assert {:error, {:no_eligible_items, "started"}} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "started",
               requested_events,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_group_backfill_too_early",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, approved_events, _approval_job_results} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "approved",
               requested_events,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_approved_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, started_events, job_results} =
             Cadence.record_telemetry_historical_data_workflow_group_transition(
               "backfill",
               "started",
               requested_events ++ approved_events,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 authority: :authoritative,
                 reason: "operator_started_group_backfill",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert length(started_events) == 2
    assert Enum.all?(started_events, &(&1.event_type == :backfill_started))

    assert Enum.all?(
             job_results,
             &match?({:ok, %{job_type: :telemetry_historical_data_workflow, status: :queued}}, &1)
           )

    assert Enum.map(job_results, fn {:ok, job} -> job.run_id end) ==
             ["backfill-run-group-start-1", "backfill-run-group-start-2"]
  end

  test "retries historical data workflow job through the product API" do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-single-retry",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert {:ok, failed_job} = Cadence.Jobs.fail_worker_start(job.job_id, :source_failed)
    assert failed_job.status == :failed

    assert {:ok, source_event} =
             record_group_failed_event(
               "failed-single-retry-event",
               "backfill-run-single-retry",
               1,
               retryable: true
             )

    assert {:ok, retried_job, retry_event} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               job.job_id,
               source_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert retried_job.status == :queued
    assert retry_event.event_type == :backfill_retried
    assert retry_event.actor_id == "operator-2"
    assert retry_event.payload["retry_action"] == "retry_job"

    assert retry_event.payload["retry_source_event_id"] ==
             source_event.backfill_lifecycle_event_id

    assert retry_event.payload["retry_job_id"] == job.job_id
    assert retry_event.payload["retry_job_status"] == "queued"
    assert [retried_claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert retried_claimed_job.job_id == job.job_id

    assert {:error, {:historical_workflow_event_not_found, "missing-event"}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               job.job_id,
               "missing-event",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, mismatched_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-mismatched-retry",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_mismatched_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_mismatched_job.job_id == mismatched_job.job_id

    assert {:ok, failed_mismatched_job} =
             Cadence.Jobs.fail_worker_start(mismatched_job.job_id, :source_failed)

    assert failed_mismatched_job.status == :failed

    assert {:error,
            {:historical_workflow_retry_blocked, "failed-single-retry-event", :job_run_mismatch}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               mismatched_job.job_id,
               source_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-single-queued-retry",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert {:ok, queued_source_event} =
             record_group_failed_event(
               "failed-single-queued-retry-event",
               "backfill-run-single-queued-retry",
               1,
               retryable: true,
               request_group_id: "backfill-run-single-queued-retry-group"
             )

    assert {:error,
            {:historical_workflow_retry_blocked, "failed-single-queued-retry-event",
             "job_not_failed"}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               queued_job.job_id,
               queued_source_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert [claimed_queued_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_queued_job.job_id == queued_job.job_id

    assert {:ok, correction_required_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               "mission-product",
               "backfill-run-single-correction",
               %{"workflow" => "backfill", "attrs" => %{}}
             )

    assert [claimed_correction_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_correction_job.job_id == correction_required_job.job_id

    assert {:ok, failed_correction_job} =
             Cadence.Jobs.fail_worker_start(correction_required_job.job_id, :source_failed)

    assert failed_correction_job.status == :failed

    assert {:ok, correction_required_event} =
             record_group_failed_event(
               "failed-single-correction-event",
               "backfill-run-single-correction",
               1,
               retryable: true,
               recovery_action: "correct_workflow_request"
             )

    assert {:error,
            {:historical_workflow_retry_blocked, "failed-single-correction-event",
             :correct_workflow_request}} =
             Cadence.retry_telemetry_historical_data_workflow_job(
               correction_required_job.job_id,
               correction_required_event.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )
  end
end
