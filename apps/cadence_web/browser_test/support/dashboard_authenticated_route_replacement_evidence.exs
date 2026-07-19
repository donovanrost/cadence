defmodule CadenceWeb.Assets.DashboardAuthenticatedRouteReplacementEvidence do
  @moduledoc false

  import ExUnit.Assertions
  import CadenceWeb.Assets.DashboardRenderedViewportWorkflowFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Telemetry.Storage
  alias CadenceWeb.TestFixtures

  def run(context) do
    %{
      app_root: app_root,
      base_url: base_url,
      dashboard: dashboard,
      mission: mission,
      org: org,
      script: script,
      user: user
    } = context

    skipped_retry_group_id = "browser-smoke-workflow-skipped-retry-group"
    skipped_retryable_run_id = "browser-smoke-workflow-skipped-retryable"
    skipped_missing_job_run_id = "browser-smoke-workflow-skipped-missing-job"

    skipped_retry_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-skipped-retry-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    skipped_retryable_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        skipped_retryable_run_id,
        "HK.voltage",
        skipped_retry_group_id,
        1,
        2,
        dashboard_context: skipped_retry_dashboard_context
      )

    skipped_missing_job_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        skipped_missing_job_run_id,
        "HK.current",
        skipped_retry_group_id,
        2,
        2,
        dashboard_context: skipped_retry_dashboard_context
      )

    for attrs <- [skipped_retryable_attrs, skipped_missing_job_attrs],
        stage <- ["requested", "approved", "started"] do
      record_backfill_workflow_event!(org, mission, stage, attrs)
    end

    assert {:ok, skipped_retryable_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               skipped_retryable_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => skipped_retryable_run_id}
               }
             )

    assert Enum.any?(
             Cadence.Jobs.claim_jobs(10),
             &(&1.job_id == skipped_retryable_job.job_id)
           )

    assert {:ok, failed_skipped_retryable_job} =
             Cadence.Jobs.fail_worker_start(
               skipped_retryable_job.job_id,
               :source_window_failed
             )

    assert failed_skipped_retryable_job.status == :failed

    skipped_retryable_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: skipped_retryable_run_id,
          point_id: "HK.voltage",
          request_group_id: skipped_retry_group_id,
          item_index: 1,
          item_count: 2,
          payload: %{
            "dashboard_context" => skipped_retry_dashboard_context,
            "job_id" => skipped_retryable_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => true,
                "retry_blockers" => [],
                "recovery_action" => "retry_job"
              }
            }
          }
        }
      )

    skipped_missing_job_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: skipped_missing_job_run_id,
          point_id: "HK.current",
          request_group_id: skipped_retry_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{
            "dashboard_context" => skipped_retry_dashboard_context,
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => true,
                "retry_blockers" => [],
                "recovery_action" => "retry_job"
              }
            }
          }
        }
      )

    skipped_retry_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: skipped_missing_job_failed_event.backfill_lifecycle_event_id
    }

    skipped_retry_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{skipped_retry_query}"

    assert {skipped_retry_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-retry-skipped-workflow",
                 "--url",
                 skipped_retry_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert skipped_retry_output =~ "dashboard_viewport_smoke passed"

    assert [skipped_retry_retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == skipped_retryable_run_id))

    assert skipped_retry_retried_event.payload["retry_source_event_id"] ==
             skipped_retryable_failed_event.backfill_lifecycle_event_id

    assert skipped_retry_retried_event.payload["retry_job_id"] == skipped_retryable_job.job_id
    assert skipped_retry_retried_event.payload["request_group_id"] == skipped_retry_group_id

    assert {:ok, skipped_retryable_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(skipped_retryable_run_id)

    assert skipped_retryable_retried_job.status == :queued
    refute skipped_retry_retried_event.backfill_run_id == skipped_missing_job_run_id

    replacement_retry_group_id = "browser-smoke-workflow-replacement-retry-group"
    replacement_retry_source_run_id = "browser-smoke-workflow-replacement-retry-source"
    replacement_retry_corrected_run_id = "browser-smoke-workflow-replacement-retry-corrected"

    replacement_retry_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-replacement-retry-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    replacement_retry_source_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        replacement_retry_source_run_id,
        "HK.current",
        replacement_retry_group_id,
        1,
        1,
        dashboard_context: replacement_retry_dashboard_context
      )

    _replacement_retry_source_requested =
      record_backfill_workflow_event!(org, mission, "requested", replacement_retry_source_attrs)

    _replacement_retry_source_approved =
      record_backfill_workflow_event!(org, mission, "approved", replacement_retry_source_attrs)

    _replacement_retry_source_started =
      record_backfill_workflow_event!(org, mission, "started", replacement_retry_source_attrs)

    replacement_retry_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        replacement_retry_source_run_id,
        :replacement_retry_source_failed
      )

    replacement_retry_source_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: replacement_retry_source_run_id,
          point_id: "HK.current",
          request_group_id: replacement_retry_group_id,
          item_index: 1,
          item_count: 1,
          payload: %{
            "dashboard_context" => replacement_retry_dashboard_context,
            "job_id" => replacement_retry_source_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => false,
                "retry_blockers" => ["operator_correction_required"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    replacement_retry_correction_payload = %{
      "dashboard_context" => replacement_retry_dashboard_context,
      "recovery_action" => "correct_workflow_request",
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "corrects_run_id" => replacement_retry_source_run_id,
      "corrects_event_id" => replacement_retry_source_failed_event.backfill_lifecycle_event_id,
      "corrects_job_id" => replacement_retry_source_job.job_id
    }

    replacement_retry_corrected_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        replacement_retry_corrected_run_id,
        "HK.current",
        replacement_retry_group_id,
        1,
        1,
        dashboard_context: replacement_retry_dashboard_context
      )
      |> Map.put(:payload, replacement_retry_correction_payload)

    _replacement_retry_corrected_requested =
      record_backfill_workflow_event!(
        org,
        mission,
        "requested",
        replacement_retry_corrected_attrs
      )

    _replacement_retry_corrected_approved =
      record_backfill_workflow_event!(org, mission, "approved", replacement_retry_corrected_attrs)

    _replacement_retry_corrected_started =
      record_backfill_workflow_event!(org, mission, "started", replacement_retry_corrected_attrs)

    replacement_retry_corrected_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        replacement_retry_corrected_run_id,
        :replacement_retry_corrected_failed
      )

    replacement_retry_corrected_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: replacement_retry_corrected_run_id,
          point_id: "HK.current",
          request_group_id: replacement_retry_group_id,
          item_index: 1,
          item_count: 1,
          payload:
            Map.merge(replacement_retry_correction_payload, %{
              "job_id" => replacement_retry_corrected_job.job_id,
              "job_type" => "telemetry_historical_data_workflow",
              "workflow_job_status" => "failed",
              "source" => %{
                "failure" => %{
                  "code" => "replacement_worker_failed",
                  "retryable" => true,
                  "retry_blockers" => [],
                  "recovery_action" => "retry_job"
                }
              }
            })
        }
      )

    replacement_retry_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: replacement_retry_source_failed_event.backfill_lifecycle_event_id
    }

    replacement_retry_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replacement_retry_query}"

    assert {replacement_retry_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-retry-workflow",
                 "--url",
                 replacement_retry_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert replacement_retry_output =~ "dashboard_viewport_smoke passed"

    assert [replacement_retry_retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == replacement_retry_corrected_run_id))

    assert replacement_retry_retried_event.payload["retry_source_event_id"] ==
             replacement_retry_corrected_failed_event.backfill_lifecycle_event_id

    assert replacement_retry_retried_event.payload["retry_job_id"] ==
             replacement_retry_corrected_job.job_id

    assert replacement_retry_retried_event.payload["retry_job_status"] == "queued"

    assert replacement_retry_retried_event.payload["request_group_id"] ==
             replacement_retry_group_id

    assert {:ok, replacement_retry_requeued_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               replacement_retry_corrected_run_id
             )

    assert replacement_retry_requeued_job.status == :queued

    row_replacement_retry =
      seed_failed_replacement_retry_workflow!(
        org,
        mission,
        dashboard,
        group_id: "browser-smoke-workflow-row-replacement-retry-group",
        source_run_id: "browser-smoke-workflow-row-replacement-retry-source",
        corrected_run_id: "browser-smoke-workflow-row-replacement-retry-corrected",
        replay_run_id: "replay-row-replacement-retry-browser",
        source_failure_reason: :row_replacement_retry_source_failed,
        corrected_failure_reason: :row_replacement_retry_corrected_failed
      )

    row_replacement_retry_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: row_replacement_retry.source_failed_event.backfill_lifecycle_event_id
    }

    row_replacement_retry_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{row_replacement_retry_query}"

    assert {row_replacement_retry_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "row-replacement-retry-workflow",
                 "--url",
                 row_replacement_retry_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert row_replacement_retry_output =~ "dashboard_viewport_smoke passed"

    assert [row_replacement_retry_retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == row_replacement_retry.corrected_run_id))

    assert row_replacement_retry_retried_event.payload["retry_source_event_id"] ==
             row_replacement_retry.corrected_failed_event.backfill_lifecycle_event_id

    assert row_replacement_retry_retried_event.payload["retry_job_id"] ==
             row_replacement_retry.corrected_job.job_id

    assert row_replacement_retry_retried_event.payload["retry_job_status"] == "queued"

    assert row_replacement_retry_retried_event.payload["request_group_id"] ==
             row_replacement_retry.group_id

    assert {:ok, row_replacement_retry_requeued_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               row_replacement_retry.corrected_run_id
             )

    assert row_replacement_retry_requeued_job.status == :queued

    stale_group_id = "browser-smoke-workflow-stale-replacement-group"
    stale_source_run_id = "browser-smoke-workflow-stale-replacement-source"
    stale_corrected_run_id = "browser-smoke-workflow-stale-replacement-corrected"

    stale_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-stale-replacement-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    stale_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        stale_source_run_id,
        :stale_replacement_source_failed
      )

    stale_source_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: stale_source_run_id,
          point_id: "HK.gyro",
          request_group_id: stale_group_id,
          item_index: 1,
          item_count: 1,
          payload: %{
            "dashboard_context" => stale_dashboard_context,
            "job_id" => stale_source_job.job_id,
            "job_type" => "telemetry_historical_data_workflow",
            "workflow_job_status" => "failed",
            "source" => %{
              "failure" => %{
                "code" => "source_window_failed",
                "retryable" => false,
                "retry_blockers" => ["operator_correction_required"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    stale_correction_payload = %{
      "dashboard_context" => stale_dashboard_context,
      "recovery_action" => "correct_workflow_request",
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "corrects_run_id" => stale_source_run_id,
      "corrects_event_id" => stale_source_failed_event.backfill_lifecycle_event_id,
      "corrects_job_id" => stale_source_job.job_id
    }

    stale_corrected_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        stale_corrected_run_id,
        "HK.gyro",
        stale_group_id,
        1,
        1,
        dashboard_context: stale_dashboard_context
      )
      |> Map.put(:payload, stale_correction_payload)

    _stale_corrected_requested =
      record_backfill_workflow_event!(org, mission, "requested", stale_corrected_attrs)

    _stale_corrected_approved =
      record_backfill_workflow_event!(org, mission, "approved", stale_corrected_attrs)

    stale_corrected_started =
      record_backfill_workflow_event!(org, mission, "started", stale_corrected_attrs)

    stale_corrected_job =
      enqueue_stale_running_historical_workflow_job!(mission, stale_corrected_run_id)

    stale_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: stale_source_failed_event.backfill_lifecycle_event_id
    }

    stale_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{stale_query}"

    assert {stale_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-stale-workflow",
                 "--url",
                 stale_dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert stale_output =~ "dashboard_viewport_smoke passed"

    assert [stale_requeue_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_stale_replacement_requeued
             )
             |> Enum.filter(&(&1.backfill_run_id == stale_corrected_run_id))

    assert stale_requeue_event.payload["stale_replacement_source_event_id"] ==
             stale_corrected_started.backfill_lifecycle_event_id

    assert stale_requeue_event.payload["stale_replacement_job_id"] ==
             stale_corrected_job.job_id

    assert stale_requeue_event.payload["stale_replacement_job_status"] == "running"

    assert stale_requeue_event.payload["stale_replacement_action"] ==
             "requeue_stale_replacement_job"

    assert stale_requeue_event.payload["stale_replacement_requeued_job_id"] ==
             stale_corrected_job.job_id

    assert stale_requeue_event.payload["stale_replacement_requeued_job_status"] == "queued"

    assert stale_requeue_event.payload["stale_replacement_requeued_failure_reason"] ==
             "dashboard_stale_replacement_requeued"

    assert {:ok, stale_requeued_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(stale_corrected_run_id)

    assert stale_requeued_job.status == :queued

    context
  end
end
