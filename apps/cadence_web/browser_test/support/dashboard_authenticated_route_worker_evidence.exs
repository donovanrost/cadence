defmodule CadenceWeb.Assets.DashboardAuthenticatedRouteWorkerEvidence do
  @moduledoc false

  import ExUnit.Assertions
  import CadenceWeb.Assets.DashboardRenderedViewportWorkflowFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.DocumentStore.LifecycleEventRow, as: DashboardLifecycleEventRow
  alias Cadence.Repo
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
      trend_widget: trend_widget,
      user: user
    } = context

    real_job_group_id = "browser-smoke-workflow-real-job-group"
    real_job_completed_run_id = "browser-smoke-workflow-real-job-completed"
    real_job_retryable_failed_run_id = "browser-smoke-workflow-real-job-retryable-failed"
    real_job_failed_run_id = "browser-smoke-workflow-real-job-failed"

    real_job_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-real-job-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    real_job_review_request =
      CadenceWeb.DashboardReviewFixtures.comparison_review_request_event(
        event_id: "browser-smoke-review-origin-request",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: dashboard.dashboard_id,
        dashboard_version: 1,
        actor_id: user.email,
        placement_ids: [trend_widget.widget_id]
      )

    assert {:ok, _review_request_row} =
             real_job_review_request
             |> DashboardLifecycleEventRow.changeset()
             |> Repo.insert()

    real_job_comparison_review_origin = %{
      "request_event_id" => real_job_review_request.dashboard_lifecycle_event_id,
      "request_kind" => "comparison_open_findings_review",
      "open_count" => "1",
      "open_placement_ids" => trend_widget.widget_id,
      "workflow_kind" => "bulk_correction_authority_review",
      "workflow_action" => "request_comparison_review",
      "workflow_selection_kind" => "open_comparison_findings",
      "workflow_selection_count" => "1",
      "primary_data_view" => "all_revisions",
      "compare_data_view" => "canonical"
    }

    real_job_completed_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        real_job_completed_run_id,
        "HK.counter",
        real_job_group_id,
        1,
        3,
        dashboard_context: real_job_dashboard_context,
        comparison_review_origin: real_job_comparison_review_origin
      )

    real_job_failed_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        real_job_failed_run_id,
        nil,
        real_job_group_id,
        3,
        3,
        dashboard_context: real_job_dashboard_context,
        comparison_review_origin: real_job_comparison_review_origin
      )

    real_job_retryable_failed_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        real_job_retryable_failed_run_id,
        "HK.voltage",
        real_job_group_id,
        2,
        3,
        dashboard_context: real_job_dashboard_context,
        comparison_review_origin: real_job_comparison_review_origin
      )

    _real_job_completed_requested =
      record_backfill_workflow_event!(org, mission, "requested", real_job_completed_attrs)

    _real_job_completed_approved =
      record_backfill_workflow_event!(org, mission, "approved", real_job_completed_attrs)

    _real_job_completed_started =
      record_backfill_workflow_event!(org, mission, "started", real_job_completed_attrs)

    _real_job_retryable_failed_requested =
      record_backfill_workflow_event!(org, mission, "requested", real_job_retryable_failed_attrs)

    _real_job_retryable_failed_approved =
      record_backfill_workflow_event!(org, mission, "approved", real_job_retryable_failed_attrs)

    _real_job_retryable_failed_started =
      record_backfill_workflow_event!(org, mission, "started", real_job_retryable_failed_attrs)

    _real_job_failed_requested =
      record_backfill_workflow_event!(org, mission, "requested", real_job_failed_attrs)

    _real_job_failed_approved =
      record_backfill_workflow_event!(org, mission, "approved", real_job_failed_attrs)

    _real_job_failed_started =
      record_backfill_workflow_event!(org, mission, "started", real_job_failed_attrs)

    assert {:ok, real_retryable_failed_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               real_job_retryable_failed_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => real_job_retryable_failed_run_id}
               }
             )

    assert Enum.any?(
             Cadence.Jobs.claim_jobs(10),
             &(&1.job_id == real_retryable_failed_job.job_id)
           )

    assert {:ok, failed_retryable_real_job} =
             Cadence.Jobs.fail_worker_start(
               real_retryable_failed_job.job_id,
               :source_window_failed
             )

    assert failed_retryable_real_job.status == :failed

    real_job_retryable_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: real_job_retryable_failed_run_id,
          point_id: "HK.voltage",
          request_group_id: real_job_group_id,
          item_index: 2,
          item_count: 3,
          payload: %{
            "dashboard_context" => real_job_dashboard_context,
            "comparison_review_origin" => real_job_comparison_review_origin,
            "job_id" => real_retryable_failed_job.job_id,
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

    assert {:ok, real_completed_job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               real_job_completed_attrs,
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, real_failed_job} =
             Cadence.start_telemetry_historical_data_workflow_job(
               "backfill",
               real_job_failed_attrs,
               dashboard_runtime_invalidation?: false
             )

    claimed_real_jobs = Cadence.Jobs.claim_jobs(10)

    claimed_real_completed_job =
      Enum.find(claimed_real_jobs, &(&1.job_id == real_completed_job.job_id))

    claimed_real_failed_job = Enum.find(claimed_real_jobs, &(&1.job_id == real_failed_job.job_id))

    assert claimed_real_completed_job
    assert claimed_real_failed_job

    assert {:ok, completed_real_job} = Cadence.Jobs.run_job(claimed_real_completed_job.job_id)
    assert completed_real_job.status == :completed

    assert {:ok, failed_real_job} = Cadence.Jobs.run_job(claimed_real_failed_job.job_id)
    assert failed_real_job.status == :failed

    assert [real_completed_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_completed
             )
             |> Enum.filter(&(&1.backfill_run_id == real_job_completed_run_id))

    assert real_completed_event.reason == "historical_data_job_completed"
    assert real_completed_event.payload["job_id"] == real_completed_job.job_id
    assert real_completed_event.payload["workflow_job_status"] == "completed"
    assert real_completed_event.payload["request_group_id"] == real_job_group_id
    assert real_completed_event.payload["request_item_index"] == 1
    assert real_completed_event.payload["request_item_count"] == 3
    assert real_completed_event.payload["request_item_run_id"] == real_job_completed_run_id
    assert real_completed_event.payload["dashboard_context"] == real_job_dashboard_context

    assert real_completed_event.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert [real_failed_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_failed
             )
             |> Enum.filter(&(&1.backfill_run_id == real_job_failed_run_id))

    assert real_failed_event.reason == :historical_data_job_failed
    assert real_failed_event.payload["job_id"] == real_failed_job.job_id
    assert real_failed_event.payload["workflow_job_status"] == "failed"
    assert real_failed_event.payload["request_group_id"] == real_job_group_id
    assert real_failed_event.payload["request_item_index"] == 3
    assert real_failed_event.payload["request_item_count"] == 3
    assert real_failed_event.payload["request_item_run_id"] == real_job_failed_run_id
    assert real_failed_event.payload["dashboard_context"] == real_job_dashboard_context

    assert real_failed_event.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_failed_event.payload["source"]["failure"]["recovery_action"] ==
             "correct_workflow_request"

    assert real_job_retryable_failed_event.payload["request_group_id"] == real_job_group_id
    assert real_job_retryable_failed_event.payload["request_item_index"] == 2
    assert real_job_retryable_failed_event.payload["request_item_count"] == 3

    assert real_job_retryable_failed_event.payload["request_item_run_id"] ==
             real_job_retryable_failed_run_id

    assert real_job_retryable_failed_event.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_retryable_failed_event.payload["source"]["failure"]["recovery_action"] ==
             "retry_job"

    real_job_recovery_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: real_failed_event.backfill_lifecycle_event_id
    }

    real_job_recovery_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{real_job_recovery_query}"

    assert {real_job_recovery_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-job-recovery-workflow",
                 "--url",
                 real_job_recovery_dashboard_url,
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

    assert real_job_recovery_output =~ "dashboard_viewport_smoke passed"

    real_job_corrected_run_id = "browser-smoke-workflow-real-job-corrected"

    real_job_corrected_events =
      mission.mission_id
      |> Storage.list_backfill_lifecycle_events(
        organization_id: org.organization_id,
        backfill_run_id: real_job_corrected_run_id
      )

    assert %{event_type: :backfill_requested} =
             real_job_corrected_requested =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_requested))

    assert real_job_corrected_requested.reason == "browser_smoke_real_worker_correction"
    assert real_job_corrected_requested.point_id == "HK.current"

    assert real_job_corrected_requested.payload["request_group_id"] ==
             real_job_group_id

    assert real_job_corrected_requested.payload["request_item_index"] == 3
    assert real_job_corrected_requested.payload["request_item_count"] == 3

    assert real_job_corrected_requested.payload["request_item_run_id"] ==
             real_job_corrected_run_id

    assert real_job_corrected_requested.payload["corrects_run_id"] == real_job_failed_run_id

    assert real_job_corrected_requested.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_requested.payload["corrects_job_id"] == real_failed_job.job_id

    assert real_job_corrected_requested.payload["dashboard_context"] ==
             real_job_dashboard_context

    assert real_job_corrected_requested.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert %{event_type: :backfill_approved} =
             real_job_corrected_approved =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_approved))

    assert real_job_corrected_approved.reason == "dashboard_recovery_replacement_approved"
    assert real_job_corrected_approved.payload["request_group_id"] == real_job_group_id

    assert real_job_corrected_approved.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_approved.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_corrected_approved.payload["group_transition_scope"] ==
             "replacement_corrections"

    assert %{event_type: :backfill_started} =
             real_job_corrected_started =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_started))

    assert real_job_corrected_started.reason == "dashboard_recovery_replacement_started"
    assert real_job_corrected_started.payload["request_group_id"] == real_job_group_id

    assert real_job_corrected_started.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_started.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_corrected_started.payload["group_transition_scope"] ==
             "replacement_corrections"

    assert %{event_type: :backfill_completed} =
             real_job_corrected_completed =
             Enum.find(real_job_corrected_events, &(&1.event_type == :backfill_completed))

    assert real_job_corrected_completed.reason == "dashboard_recovery_replacement_completed"
    assert real_job_corrected_completed.payload["request_group_id"] == real_job_group_id

    assert real_job_corrected_completed.payload["corrects_event_id"] ==
             real_failed_event.backfill_lifecycle_event_id

    assert real_job_corrected_completed.payload["comparison_review_origin"] ==
             real_job_comparison_review_origin

    assert real_job_corrected_completed.payload["group_transition_scope"] ==
             "replacement_corrections"

    assert [real_job_retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == real_job_retryable_failed_run_id))

    assert real_job_retried_event.payload["retry_source_event_id"] ==
             real_job_retryable_failed_event.backfill_lifecycle_event_id

    assert real_job_retried_event.payload["retry_job_id"] == real_retryable_failed_job.job_id
    assert real_job_retried_event.payload["retry_job_status"] == "queued"
    assert real_job_retried_event.payload["request_group_id"] == real_job_group_id

    assert {:ok, real_job_retried_job} =
             Cadence.fetch_telemetry_historical_data_workflow_job(
               real_job_retryable_failed_run_id
             )

    assert real_job_retried_job.status == :queued

    context
  end
end
