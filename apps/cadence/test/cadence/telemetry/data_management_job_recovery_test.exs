defmodule Cadence.Telemetry.DataManagementJobRecoveryTest do
  use Cadence.ConfigCase, async: false

  import Cadence.Telemetry.DataManagementFixtures

  alias Cadence.Telemetry.CurrentValueStore
  alias Cadence.Telemetry.HistoryStore
  alias Cadence.Telemetry.HistoryStore.ETS, as: HistoryStoreETS
  alias Cadence.Telemetry.Storage

  setup do
    previous_storage_config = Application.get_env(:cadence, :telemetry_storage, [])
    previous_history_store = Application.get_env(:cadence, :telemetry_history_store, [])

    previous_current_value_store =
      Application.get_env(:cadence, :telemetry_current_value_store, [])

    Application.put_env(:cadence, :telemetry_storage,
      writer: Cadence.TestSupport.CapturingTelemetryStorageWriter,
      writer_opts: [test_pid: self()],
      realm: :flight,
      data_source_id: "managed_questdb_primary",
      binding_id: "default_flight_telemetry",
      dashboard_runtime_invalidation?: false
    )

    Application.put_env(:cadence, :telemetry_current_value_store,
      module: Cadence.Telemetry.CurrentValueStore.ETS
    )

    Application.put_env(:cadence, :telemetry_history_store,
      module: HistoryStoreETS,
      max_samples_per_point: :infinity
    )

    start_supervised!(HistoryStoreETS)
    HistoryStoreETS.reset()

    start_supervised!(Cadence.Telemetry.CurrentValueStore.ETS)
    CurrentValueStore.reset()

    on_exit(fn ->
      Application.put_env(:cadence, :telemetry_storage, previous_storage_config)
      Application.put_env(:cadence, :telemetry_history_store, previous_history_store)
      Application.put_env(:cadence, :telemetry_current_value_store, previous_current_value_store)
    end)

    :ok
  end

  test "retries historical data workflow group failed jobs through the product API" do
    retryable_job_1 = failed_historical_workflow_job("backfill-run-group-failed-1")
    retryable_job_2 = failed_historical_workflow_job("backfill-run-group-failed-2")

    assert {:ok, retryable_failed_event} =
             record_group_failed_event("failed-group-event-1", "backfill-run-group-failed-1", 1,
               retryable: true,
               item_count: 5
             )

    assert {:ok, second_retryable_failed_event} =
             record_group_failed_event("failed-group-event-2", "backfill-run-group-failed-2", 2,
               retryable: true,
               item_count: 5
             )

    assert {:ok, _nonretryable_failed_event} =
             record_group_failed_event("failed-group-event-3", "backfill-run-group-failed-3", 3,
               retryable: false,
               item_count: 5
             )

    assert {:ok, _missing_job_failed_event} =
             record_group_failed_event("failed-group-event-4", "backfill-run-group-failed-4", 4,
               retryable: true,
               item_count: 5
             )

    assert {:ok, _correction_required_failed_event} =
             record_group_failed_event("failed-group-event-5", "backfill-run-group-failed-5", 5,
               retryable: true,
               recovery_action: "correct_workflow_request",
               item_count: 5
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-failed",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 2
    assert summary.nonretryable == 2
    assert summary.skipped == 1
    assert summary.failed == 0
    assert summary.retry_error_items == []

    nonretryable_items =
      summary.nonretryable_items
      |> Enum.sort_by(& &1.event_id)

    assert nonretryable_items == [
             %{
               event_id: "failed-group-event-3",
               reason: "nonretryable_failure",
               run_id: "backfill-run-group-failed-3"
             },
             %{
               event_id: "failed-group-event-5",
               reason: "correction_required",
               recovery_action: "correct_workflow_request",
               run_id: "backfill-run-group-failed-5"
             }
           ]

    assert summary.skipped_items == [
             %{
               event_id: "failed-group-event-4",
               reason: "job_status_missing",
               run_id: "backfill-run-group-failed-4"
             }
           ]

    retry_events =
      summary.events
      |> Enum.sort_by(& &1.payload["request_item_index"])

    assert Enum.map(retry_events, & &1.event_type) == [:backfill_retried, :backfill_retried]

    assert Enum.map(retry_events, & &1.reason) == [
             "dashboard_historical_workflow_retried",
             "dashboard_historical_workflow_retried"
           ]

    assert Enum.map(retry_events, & &1.actor_id) == ["operator-2", "operator-2"]

    assert Enum.map(retry_events, & &1.payload["retry_action"]) == ["retry_job", "retry_job"]

    assert Enum.map(retry_events, & &1.payload["retry_source_event_id"]) == [
             retryable_failed_event.backfill_lifecycle_event_id,
             second_retryable_failed_event.backfill_lifecycle_event_id
           ]

    assert Enum.map(retry_events, & &1.payload["request_group_id"]) == [
             "backfill-run-group-failed",
             "backfill-run-group-failed"
           ]

    assert Enum.map(retry_events, & &1.payload["request_item_index"]) == [1, 2]
    assert Enum.map(retry_events, & &1.payload["request_item_count"]) == [5, 5]

    assert Enum.map(retry_events, & &1.payload["retry_job_id"]) == [
             retryable_job_1.job_id,
             retryable_job_2.job_id
           ]

    assert Enum.map(retry_events, & &1.payload["retry_job_status"]) == ["queued", "queued"]

    assert {:ok, retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("backfill-run-group-failed-1")

    assert retried_job.status == :queued

    assert {:ok, second_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("backfill-run-group-failed-2")

    assert second_retried_job.status == :queued

    assert {:error, {:missing_field, :request_group_id}} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _nonretryable_only_event} =
             record_group_failed_event(
               "failed-group-no-retry-event",
               "backfill-run-group-no-retry-1",
               1,
               retryable: false,
               request_group_id: "backfill-run-group-no-retry",
               item_count: 1
             )

    assert {:error,
            {:historical_workflow_group_retry_blocked, "backfill-run-group-no-retry",
             "no_retryable_group_failures"}} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-no-retry",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "retries only scoped replacement runs in a historical workflow group" do
    original_failed_job = failed_historical_workflow_job("backfill-run-group-scoped-original")

    replacement_failed_job =
      failed_historical_workflow_job("backfill-run-group-scoped-replacement")

    assert {:ok, _original_failed_event} =
             record_group_failed_event(
               "failed-group-scoped-original-event",
               "backfill-run-group-scoped-original",
               1,
               retryable: true,
               request_group_id: "backfill-run-group-scoped",
               item_count: 2
             )

    assert {:ok, replacement_failed_event} =
             record_group_failed_event(
               "failed-group-scoped-replacement-event",
               "backfill-run-group-scoped-replacement",
               2,
               retryable: true,
               request_group_id: "backfill-run-group-scoped",
               item_count: 2,
               recovery_action: "retry_job"
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-scoped",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               retry_run_ids: ["backfill-run-group-scoped-replacement"],
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 1
    assert summary.nonretryable == 0
    assert summary.skipped == 0
    assert summary.failed == 0
    assert summary.retry_error_items == []
    assert [retry_event] = summary.events

    assert retry_event.payload["retry_source_event_id"] ==
             replacement_failed_event.backfill_lifecycle_event_id

    assert retry_event.payload["request_group_id"] == "backfill-run-group-scoped"
    assert retry_event.payload["request_item_index"] == 2
    assert retry_event.payload["retry_job_id"] == replacement_failed_job.job_id

    assert {:ok, still_failed_original} =
             Cadence.Jobs.fetch_job(original_failed_job.job_id)

    assert still_failed_original.status == :failed

    assert {:ok, retried_replacement} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "backfill-run-group-scoped-replacement"
             )

    assert retried_replacement.status == :queued
  end

  test "reports skipped items in degraded scoped replacement retry batches" do
    replacement_failed_job =
      failed_historical_workflow_job("backfill-run-group-degraded-replacement-failed")

    replacement_running_job =
      running_historical_workflow_job("backfill-run-group-degraded-replacement-running")

    assert {:ok, replacement_failed_event} =
             record_group_failed_event(
               "failed-group-degraded-replacement-event",
               "backfill-run-group-degraded-replacement-failed",
               1,
               retryable: true,
               request_group_id: "backfill-run-group-degraded-replacement",
               item_count: 2,
               recovery_action: "retry_job"
             )

    assert {:ok, replacement_running_event} =
             record_group_failed_event(
               "failed-group-degraded-running-event",
               "backfill-run-group-degraded-replacement-running",
               2,
               retryable: true,
               request_group_id: "backfill-run-group-degraded-replacement",
               item_count: 2,
               recovery_action: "retry_job"
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "backfill-run-group-degraded-replacement",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               retry_run_ids: [
                 "backfill-run-group-degraded-replacement-failed",
                 "backfill-run-group-degraded-replacement-running"
               ],
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 1
    assert summary.nonretryable == 0
    assert summary.skipped == 1
    assert summary.failed == 0
    assert summary.retry_error_items == []
    assert [retry_event] = summary.events

    assert retry_event.backfill_run_id == "backfill-run-group-degraded-replacement-failed"

    assert retry_event.payload["retry_source_event_id"] ==
             replacement_failed_event.backfill_lifecycle_event_id

    assert retry_event.payload["request_group_id"] == "backfill-run-group-degraded-replacement"
    assert retry_event.payload["request_item_index"] == 1
    assert retry_event.payload["retry_job_id"] == replacement_failed_job.job_id

    assert [skipped_item] = summary.skipped_items
    assert skipped_item.run_id == "backfill-run-group-degraded-replacement-running"
    assert skipped_item.event_id == replacement_running_event.backfill_lifecycle_event_id
    assert skipped_item.job_id == replacement_running_job.job_id
    assert skipped_item.job_status == "running"
    assert skipped_item.reason == "job_not_failed"

    assert {:ok, retried_replacement} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "backfill-run-group-degraded-replacement-failed"
             )

    assert retried_replacement.status == :queued

    assert {:ok, still_running_replacement} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               "backfill-run-group-degraded-replacement-running"
             )

    assert still_running_replacement.status == :running
  end

  test "retries import workflow group failed jobs through the product API" do
    retryable_job_1 =
      failed_historical_workflow_job("import-run-group-failed-1", workflow: :import)

    retryable_job_2 =
      failed_historical_workflow_job("import-run-group-failed-2", workflow: :import)

    assert {:ok, retryable_failed_event} =
             record_group_failed_event(
               "import-failed-group-event-1",
               "import-run-group-failed-1",
               1,
               workflow: :import,
               retryable: true,
               request_group_id: "import-run-group-failed",
               item_count: 2
             )

    assert {:ok, second_retryable_failed_event} =
             record_group_failed_event(
               "import-failed-group-event-2",
               "import-run-group-failed-2",
               2,
               workflow: :import,
               retryable: true,
               request_group_id: "import-run-group-failed",
               item_count: 2
             )

    assert {:ok, summary} =
             Cadence.retry_telemetry_historical_data_workflow_group_failed_jobs(
               "import-run-group-failed",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert summary.retried == 2
    assert summary.nonretryable == 0
    assert summary.skipped == 0
    assert summary.failed == 0
    assert summary.retry_error_items == []

    retry_events =
      summary.events
      |> Enum.sort_by(& &1.payload["request_item_index"])

    assert Enum.map(retry_events, & &1.event_type) == [:import_retried, :import_retried]

    assert Enum.map(retry_events, & &1.backfill_run_id) == [
             "import-run-group-failed-1",
             "import-run-group-failed-2"
           ]

    assert Enum.map(retry_events, & &1.payload["workflow"]) == ["import", "import"]

    assert Enum.map(retry_events, & &1.payload["retry_source_event_type"]) == [
             "import_failed",
             "import_failed"
           ]

    assert Enum.map(retry_events, & &1.payload["retry_source_event_id"]) == [
             retryable_failed_event.backfill_lifecycle_event_id,
             second_retryable_failed_event.backfill_lifecycle_event_id
           ]

    assert Enum.map(retry_events, & &1.payload["request_group_id"]) == [
             "import-run-group-failed",
             "import-run-group-failed"
           ]

    assert Enum.map(retry_events, & &1.payload["request_item_index"]) == [1, 2]
    assert Enum.map(retry_events, & &1.payload["request_item_count"]) == [2, 2]

    assert Enum.map(retry_events, & &1.payload["retry_job_id"]) == [
             retryable_job_1.job_id,
             retryable_job_2.job_id
           ]

    assert Enum.map(retry_events, & &1.payload["retry_job_status"]) == ["queued", "queued"]

    assert {:ok, retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("import-run-group-failed-1")

    assert retried_job.status == :queued
    assert retried_job.payload["workflow"] == "import"

    assert {:ok, second_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job("import-run-group-failed-2")

    assert second_retried_job.status == :queued
    assert second_retried_job.payload["workflow"] == "import"
  end

  test "records stale replacement job inspection without advancing replacement stage" do
    failed_job = failed_historical_workflow_job("backfill-run-stale-inspection-source")

    assert {:ok, failed_event} =
             record_group_failed_event(
               "failed-event-stale-inspection-source",
               "backfill-run-stale-inspection-source",
               1,
               retryable: false,
               request_group_id: "backfill-run-stale-inspection-group",
               item_count: 1,
               recovery_action: "correct_workflow_request",
               job_id: failed_job.job_id
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-stale-inspection-replacement",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-1",
                 actor_kind: "operator"
               },
               %{
                 original_event_id: failed_event.backfill_lifecycle_event_id,
                 original_run_id: failed_event.backfill_run_id,
                 original_job_id: failed_job.job_id,
                 request_group_id: "backfill-run-stale-inspection-group",
                 request_item_index: 1,
                 request_item_count: 1,
                 request_item_run_id: "backfill-run-stale-inspection-replacement"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, replacement_job} =
             stale_running_historical_workflow_job(correction_request.backfill_run_id)

    assert {:ok, inspection_event} =
             Cadence.record_telemetry_historical_data_workflow_stale_replacement_inspection(
               replacement_job.job_id,
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert inspection_event.event_type == :backfill_stale_replacement_inspected
    assert inspection_event.reason == "dashboard_historical_workflow_stale_replacement_inspected"
    assert inspection_event.authority == :advisory
    assert inspection_event.backfill_run_id == correction_request.backfill_run_id
    assert inspection_event.payload["stale_replacement_action"] == "inspect_stale_replacement_job"

    assert inspection_event.payload["stale_replacement_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert inspection_event.payload["stale_replacement_run_id"] ==
             correction_request.backfill_run_id

    assert inspection_event.payload["stale_replacement_job_id"] == replacement_job.job_id
    assert inspection_event.payload["stale_replacement_job_status"] == "running"
    assert inspection_event.payload["stale_replacement_stale_after_seconds"] == 900
    refute Map.has_key?(inspection_event.payload, "stage")

    correction_request_id = correction_request.backfill_lifecycle_event_id

    assert {:error,
            {:historical_workflow_stale_replacement_inspection_blocked, ^correction_request_id,
             :job_run_mismatch}} =
             Cadence.record_telemetry_historical_data_workflow_stale_replacement_inspection(
               failed_job.job_id,
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "records missing replacement job inspection without creating replacement job" do
    failed_job = failed_historical_workflow_job("backfill-run-missing-inspection-source")

    assert {:ok, failed_event} =
             record_group_failed_event(
               "failed-event-missing-inspection-source",
               "backfill-run-missing-inspection-source",
               1,
               retryable: false,
               request_group_id: "backfill-run-missing-inspection-group",
               item_count: 1,
               recovery_action: "correct_workflow_request",
               job_id: failed_job.job_id
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-missing-inspection-replacement",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-1",
                 actor_kind: "operator"
               },
               %{
                 original_event_id: failed_event.backfill_lifecycle_event_id,
                 original_run_id: failed_event.backfill_run_id,
                 original_job_id: failed_job.job_id,
                 request_group_id: "backfill-run-missing-inspection-group",
                 request_item_index: 1,
                 request_item_count: 1,
                 request_item_run_id: "backfill-run-missing-inspection-replacement"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, inspection_event} =
             Cadence.record_telemetry_historical_data_workflow_missing_replacement_inspection(
               "backfill-run-missing-inspection-group",
               correction_request.backfill_run_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert inspection_event.event_type == :backfill_missing_replacement_inspected

    assert inspection_event.reason ==
             "dashboard_historical_workflow_missing_replacement_inspected"

    assert inspection_event.authority == :advisory
    assert inspection_event.backfill_run_id == correction_request.backfill_run_id

    assert inspection_event.payload["missing_replacement_action"] ==
             "inspect_missing_replacement_job"

    assert inspection_event.payload["missing_replacement_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert inspection_event.payload["missing_replacement_run_id"] ==
             correction_request.backfill_run_id

    assert inspection_event.payload["missing_replacement_expected_job_type"] ==
             "telemetry_historical_data_workflow"

    refute Map.has_key?(inspection_event.payload, "stage")

    assert {:error,
            {:historical_workflow_missing_replacement_inspection_blocked,
             "backfill-run-missing-inspection-unknown", :replacement_event_not_found}} =
             Cadence.record_telemetry_historical_data_workflow_missing_replacement_inspection(
               "backfill-run-missing-inspection-group",
               "backfill-run-missing-inspection-unknown",
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, _replacement_job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               %{
                 backfill_run_id: correction_request.backfill_run_id,
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 realm: correction_request.realm,
                 data_source_id: correction_request.data_source_id,
                 binding_id: correction_request.binding_id,
                 observable_id: correction_request.observable_id,
                 source_from: correction_request.source_from,
                 source_to: correction_request.source_to
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:error,
            {:historical_workflow_missing_replacement_inspection_blocked,
             "backfill-run-missing-inspection-replacement", {:job_exists, :queued}}} =
             Cadence.record_telemetry_historical_data_workflow_missing_replacement_inspection(
               "backfill-run-missing-inspection-group",
               correction_request.backfill_run_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product"
               },
               dashboard_runtime_invalidation?: false
             )
  end

  test "requeues stale replacement job and records authoritative lifecycle event" do
    failed_job = failed_historical_workflow_job("backfill-run-stale-requeue-source")

    assert {:ok, failed_event} =
             record_group_failed_event(
               "failed-event-stale-requeue-source",
               "backfill-run-stale-requeue-source",
               1,
               retryable: false,
               request_group_id: "backfill-run-stale-requeue-group",
               item_count: 1,
               recovery_action: "correct_workflow_request",
               job_id: failed_job.job_id
             )

    assert {:ok, correction_request} =
             Cadence.record_telemetry_historical_data_workflow_correction_request(
               "backfill",
               %{
                 backfill_run_id: "backfill-run-stale-requeue-replacement",
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-1",
                 actor_kind: "operator"
               },
               %{
                 original_event_id: failed_event.backfill_lifecycle_event_id,
                 original_run_id: failed_event.backfill_run_id,
                 original_job_id: failed_job.job_id,
                 request_group_id: "backfill-run-stale-requeue-group",
                 request_item_index: 1,
                 request_item_count: 1,
                 request_item_run_id: "backfill-run-stale-requeue-replacement"
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, replacement_job} =
             stale_running_historical_workflow_job(correction_request.backfill_run_id)

    assert {:ok, requeued_job, requeue_event} =
             Cadence.requeue_telemetry_historical_data_workflow_stale_replacement_job(
               replacement_job.job_id,
               correction_request.backfill_lifecycle_event_id,
               %{
                 organization_id: "org-product",
                 mission_id: "mission-product",
                 actor_id: "operator-2",
                 actor_kind: "operator"
               },
               dashboard_runtime_invalidation?: false
             )

    assert requeued_job.status == :queued
    assert requeued_job.started_at == nil
    assert requeued_job.completed_at == nil
    assert requeued_job.failure_reason == %{"reason" => "dashboard_stale_replacement_requeued"}

    assert requeue_event.event_type == :backfill_stale_replacement_requeued
    assert requeue_event.reason == "dashboard_historical_workflow_stale_replacement_requeued"
    assert requeue_event.authority == :authoritative
    assert requeue_event.backfill_run_id == correction_request.backfill_run_id
    assert requeue_event.payload["stale_replacement_action"] == "requeue_stale_replacement_job"

    assert requeue_event.payload["stale_replacement_source_event_id"] ==
             correction_request.backfill_lifecycle_event_id

    assert requeue_event.payload["stale_replacement_run_id"] ==
             correction_request.backfill_run_id

    assert requeue_event.payload["stale_replacement_job_id"] == replacement_job.job_id
    assert requeue_event.payload["stale_replacement_job_status"] == "running"
    assert requeue_event.payload["stale_replacement_stale_after_seconds"] == 900
    assert requeue_event.payload["stale_replacement_requeued_job_id"] == requeued_job.job_id
    assert requeue_event.payload["stale_replacement_requeued_job_status"] == "queued"
    assert requeue_event.payload["stale_replacement_requeued_job_attempt_count"] == 1

    assert requeue_event.payload["stale_replacement_requeued_failure_reason"] ==
             "dashboard_stale_replacement_requeued"

    refute Map.has_key?(requeue_event.payload, "stage")

    assert {:ok, fetched_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               correction_request.backfill_run_id
             )

    assert fetched_job.status == :queued
  end

  test "dispatches historical data workflow jobs through the background job runner" do
    assert :ok =
             HistoryStore.persist_samples([
               sample("sample-source-before", ~U[2026-06-22 09:59:00Z], ~U[2026-06-22 10:59:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 raw_value: 41
               ),
               sample("sample-source-copied", ~U[2026-06-22 10:20:00Z], ~U[2026-06-22 10:20:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 raw_value: 43
               ),
               sample(
                 "sample-source-other-binding",
                 ~U[2026-06-22 10:30:00Z],
                 ~U[2026-06-22 10:30:03Z],
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "other_backfill_binding",
                 raw_value: 99
               )
             ])

    attrs = %{
      backfill_run_id: "backfill-run-dispatched",
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
      reason: "operator_started_backfill",
      actor_id: "operator-2",
      actor_kind: "operator",
      payload: %{
        "request_source" => "dashboard_direct_request",
        "request_mode" => "bulk_points",
        "request_group_id" => "backfill-run-dispatched-group",
        "request_item_index" => 1,
        "request_item_count" => 2,
        "request_item_run_id" => "backfill-run-dispatched",
        "dashboard_context" => %{
          "dashboard_id" => "dashboard-job-context",
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-job-context",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed"
        },
        "comparison_review_origin" => %{
          "review_request_event_id" => "review-job-context",
          "source" => "dashboard_comparison_review"
        }
      }
    }

    assert {:ok, started} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "started",
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert started.event_type == :backfill_started

    assert {:ok, job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert job.job_type == :telemetry_historical_data_workflow
    assert job.run_id == "backfill-run-dispatched"
    assert job.status == :queued
    assert job.payload["workflow"] == "backfill"
    assert job.payload["attrs"]["backfill_run_id"] == "backfill-run-dispatched"

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert claimed_job.status == :running

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert_receive {:telemetry_storage_envelopes, [envelope]}
    assert envelope.sample_id == "sample-source-copied"
    assert envelope.raw_value == 43
    assert envelope.realm == :backfill
    assert envelope.data_source_id == "managed_questdb_backfill"
    assert envelope.binding_id == "backfill_telemetry"

    events =
      Storage.list_backfill_lifecycle_events("mission-product",
        organization_id: "org-product",
        backfill_run_id: "backfill-run-dispatched"
      )

    assert Enum.map(events, & &1.event_type) == [:backfill_started, :backfill_completed]
    completed = List.last(events)
    assert completed.reason == "historical_data_job_completed"
    assert completed.sample_count == 1
    assert completed.payload["job_id"] == job.job_id
    assert completed.payload["workflow_job_status"] == "completed"
    assert completed.payload["request_source"] == "dashboard_direct_request"
    assert completed.payload["request_mode"] == "bulk_points"
    assert completed.payload["request_group_id"] == "backfill-run-dispatched-group"
    assert completed.payload["request_item_index"] == 1
    assert completed.payload["request_item_count"] == 2
    assert completed.payload["request_item_run_id"] == "backfill-run-dispatched"

    assert completed.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-job-context",
             "dashboard_version" => "1",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-job-context",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert completed.payload["comparison_review_origin"] == %{
             "review_request_event_id" => "review-job-context",
             "source" => "dashboard_comparison_review"
           }

    assert completed.payload["source"]["point_id"] == "HK.counter"

    assert completed.payload["source"]["source_identity"]["source_binding_id"] ==
             "backfill_telemetry"
  end

  test "records structured failure diagnostics for historical data workflow jobs" do
    attrs = %{
      backfill_run_id: "backfill-run-dispatch-failed",
      organization_id: "org-product",
      mission_id: "mission-product",
      realm: :backfill,
      data_source_id: "managed_questdb_backfill",
      binding_id: "backfill_telemetry",
      source_from: ~U[2026-06-22 10:00:00Z],
      source_to: ~U[2026-06-22 11:00:00Z],
      authority: :authoritative,
      reason: "operator_started_backfill",
      actor_id: "operator-2",
      actor_kind: "operator",
      payload: %{
        "request_source" => "dashboard_direct_request",
        "request_mode" => "bulk_points",
        "request_group_id" => "backfill-run-dispatch-failed-group",
        "request_item_index" => 2,
        "request_item_count" => 2,
        "request_item_run_id" => "backfill-run-dispatch-failed",
        "dashboard_context" => %{
          "dashboard_id" => "dashboard-job-failure-context",
          "dashboard_version" => "1",
          "dashboard_time_mode" => "replay_run",
          "dashboard_replay_run_id" => "replay-job-failure-context",
          "dashboard_data_view" => "all_revisions",
          "dashboard_limit_mode" => "observed"
        }
      }
    }

    assert {:ok, job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               attrs,
               dashboard_runtime_invalidation?: false
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id

    assert {:ok, failed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert failed_job.status == :failed
    assert failed_job.failure_reason == %{"tuple" => ["missing_field", "point_id"]}

    assert [failed] =
             Storage.list_backfill_lifecycle_events("mission-product",
               organization_id: "org-product",
               backfill_run_id: "backfill-run-dispatch-failed"
             )

    assert failed.event_type == :backfill_failed
    assert failed.reason == :historical_data_job_failed
    assert failed.payload["job_id"] == job.job_id
    assert failed.payload["workflow_job_status"] == "failed"
    assert failed.payload["request_source"] == "dashboard_direct_request"
    assert failed.payload["request_mode"] == "bulk_points"
    assert failed.payload["request_group_id"] == "backfill-run-dispatch-failed-group"
    assert failed.payload["request_item_index"] == 2
    assert failed.payload["request_item_count"] == 2
    assert failed.payload["request_item_run_id"] == "backfill-run-dispatch-failed"

    assert failed.payload["dashboard_context"] == %{
             "dashboard_id" => "dashboard-job-failure-context",
             "dashboard_version" => "1",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-job-failure-context",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert failed.payload["source"]["failure"]["code"] == "missing_field:point_id"
    assert failed.payload["source"]["failure"]["retryable"] == false
    assert failed.payload["source"]["failure"]["retry_blockers"] == ["missing point_id"]
    assert failed.payload["source"]["failure"]["recovery_action"] == "correct_workflow_request"
    assert failed.payload["source"]["source_window"]["from_observed_at"] == "2026-06-22T10:00:00Z"

    assert failed.payload["source"]["source_identity"]["source_binding_id"] ==
             "backfill_telemetry"
  end
end
