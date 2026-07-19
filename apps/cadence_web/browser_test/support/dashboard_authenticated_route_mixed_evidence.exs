defmodule CadenceWeb.Assets.DashboardAuthenticatedRouteMixedEvidence do
  @moduledoc false

  import ExUnit.Assertions
  import CadenceWeb.Assets.DashboardRenderedViewportWorkflowFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

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

    missing_job_group_id = "browser-smoke-workflow-missing-job-replacement-group"
    missing_job_source_run_id = "browser-smoke-workflow-missing-job-replacement-source"
    missing_job_corrected_run_id = "browser-smoke-workflow-missing-job-replacement-corrected"

    missing_job_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-missing-job-replacement-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    missing_job_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        missing_job_source_run_id,
        :missing_job_replacement_source_failed
      )

    missing_job_source_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: missing_job_source_run_id,
          point_id: "HK.power",
          request_group_id: missing_job_group_id,
          item_index: 1,
          item_count: 1,
          payload: %{
            "dashboard_context" => missing_job_dashboard_context,
            "job_id" => missing_job_source_job.job_id,
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

    missing_job_correction_payload = %{
      "dashboard_context" => missing_job_dashboard_context,
      "recovery_action" => "correct_workflow_request",
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "corrects_run_id" => missing_job_source_run_id,
      "corrects_event_id" => missing_job_source_failed_event.backfill_lifecycle_event_id,
      "corrects_job_id" => missing_job_source_job.job_id
    }

    missing_job_corrected_attrs =
      historical_workflow_item_attrs(
        org,
        mission,
        missing_job_corrected_run_id,
        "HK.power",
        missing_job_group_id,
        1,
        1,
        dashboard_context: missing_job_dashboard_context
      )
      |> Map.put(:payload, missing_job_correction_payload)

    _missing_job_corrected_requested =
      record_backfill_workflow_event!(org, mission, "requested", missing_job_corrected_attrs)

    _missing_job_corrected_approved =
      record_backfill_workflow_event!(org, mission, "approved", missing_job_corrected_attrs)

    _missing_job_corrected_started =
      record_backfill_workflow_event!(org, mission, "started", missing_job_corrected_attrs)

    _missing_job_corrected_completed =
      record_backfill_workflow_event!(org, mission, "completed", missing_job_corrected_attrs)

    missing_job_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: missing_job_source_failed_event.backfill_lifecycle_event_id
    }

    missing_job_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{missing_job_query}"

    assert {missing_job_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-missing-job-workflow",
                 "--url",
                 missing_job_dashboard_url,
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

    assert missing_job_output =~ "dashboard_viewport_smoke passed"

    assert {:error, :job_not_found} =
             Cadence.fetch_telemetry_historical_data_workflow_job(missing_job_corrected_run_id)

    mixed_group_id = "browser-smoke-workflow-mixed-replacement-group"
    mixed_missing_source_run_id = "browser-smoke-workflow-mixed-source-missing"
    mixed_failed_source_run_id = "browser-smoke-workflow-mixed-source-failed"
    mixed_stale_source_run_id = "browser-smoke-workflow-mixed-source-stale"
    mixed_missing_corrected_run_id = "browser-smoke-workflow-mixed-replacement-missing"
    mixed_failed_corrected_run_id = "browser-smoke-workflow-mixed-replacement-failed"
    mixed_stale_corrected_run_id = "browser-smoke-workflow-mixed-replacement-stale"

    mixed_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-mixed-replacement-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    mixed_source_events =
      [
        {mixed_missing_source_run_id, "HK.mixed_missing", 1},
        {mixed_failed_source_run_id, "HK.mixed_failed", 2},
        {mixed_stale_source_run_id, "HK.mixed_stale", 3}
      ]
      |> Enum.map(fn {run_id, point_id, index} ->
        source_job =
          enqueue_failed_historical_workflow_job!(
            mission,
            run_id,
            :"mixed_replacement_source_failed_#{index}"
          )

        event =
          record_backfill_workflow_event!(
            org,
            mission,
            "failed",
            %{
              run_id: run_id,
              point_id: point_id,
              request_group_id: mixed_group_id,
              item_index: index,
              item_count: 3,
              payload: %{
                "dashboard_context" => mixed_dashboard_context,
                "job_id" => source_job.job_id,
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

        {run_id, point_id, source_job, event}
      end)

    mixed_correction_context =
      mixed_source_events
      |> Enum.zip([
        {mixed_missing_corrected_run_id, "HK.mixed_missing", 1},
        {mixed_failed_corrected_run_id, "HK.mixed_failed", 2},
        {mixed_stale_corrected_run_id, "HK.mixed_stale", 3}
      ])
      |> Enum.map(fn {{source_run_id, _source_point_id, source_job, source_event},
                      {corrected_run_id, corrected_point_id, index}} ->
        payload = %{
          "dashboard_context" => mixed_dashboard_context,
          "recovery_action" => "correct_workflow_request",
          "correction_source" => "dashboard_correction_request",
          "correction_source_event_type" => "backfill_failed",
          "corrects_run_id" => source_run_id,
          "corrects_event_id" => source_event.backfill_lifecycle_event_id,
          "corrects_job_id" => source_job.job_id
        }

        attrs =
          historical_workflow_item_attrs(
            org,
            mission,
            corrected_run_id,
            corrected_point_id,
            mixed_group_id,
            index,
            3,
            dashboard_context: mixed_dashboard_context
          )
          |> Map.put(:payload, payload)

        {corrected_run_id, attrs, payload, source_event}
      end)

    {^mixed_missing_corrected_run_id, mixed_missing_attrs, _mixed_missing_payload,
     mixed_missing_source_event} =
      Enum.at(mixed_correction_context, 0)

    {^mixed_failed_corrected_run_id, mixed_failed_attrs, mixed_failed_payload,
     _mixed_failed_source_event} =
      Enum.at(mixed_correction_context, 1)

    {^mixed_stale_corrected_run_id, mixed_stale_attrs, _mixed_stale_payload,
     _mixed_stale_source_event} =
      Enum.at(mixed_correction_context, 2)

    for stage <- ["requested", "approved", "started", "completed"] do
      record_backfill_workflow_event!(org, mission, stage, mixed_missing_attrs)
    end

    for stage <- ["requested", "approved", "started"] do
      record_backfill_workflow_event!(org, mission, stage, mixed_failed_attrs)
    end

    mixed_failed_corrected_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        mixed_failed_corrected_run_id,
        :mixed_replacement_corrected_failed
      )

    _mixed_failed_corrected_failed_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: mixed_failed_corrected_run_id,
          point_id: "HK.mixed_failed",
          request_group_id: mixed_group_id,
          item_index: 2,
          item_count: 3,
          payload:
            Map.merge(mixed_failed_payload, %{
              "job_id" => mixed_failed_corrected_job.job_id,
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

    for stage <- ["requested", "approved"] do
      record_backfill_workflow_event!(org, mission, stage, mixed_stale_attrs)
    end

    _mixed_stale_started_event =
      record_backfill_workflow_event!(org, mission, "started", mixed_stale_attrs)

    _mixed_stale_job =
      enqueue_stale_running_historical_workflow_job!(mission, mixed_stale_corrected_run_id)

    mixed_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: mixed_missing_source_event.backfill_lifecycle_event_id
    }

    mixed_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{mixed_query}"

    assert {mixed_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "group-replacement-mixed-workflow",
                 "--url",
                 mixed_dashboard_url,
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

    assert mixed_output =~ "dashboard_viewport_smoke passed"

    lifecycle_events =
      Cadence.Dashboards.list_lifecycle_events(
        org.organization_id,
        mission.mission_id,
        dashboard.dashboard_id
      )

    assert %{event_type: :comparison_review_requested} =
             comparison_review_request =
             Enum.find(
               lifecycle_events,
               &(Map.get(&1.payload, "source") == "dashboard_comparison_rollup")
             )

    assert %{event_type: :comparison_review_resolved} =
             resolution =
             Enum.find(
               lifecycle_events,
               &(Map.get(&1.payload, "source_request_event_id") ==
                   comparison_review_request.dashboard_lifecycle_event_id)
             )

    assert comparison_review_request.payload["source"] == "dashboard_comparison_rollup"
    assert trend_widget.widget_id in comparison_review_request.payload["open_placement_ids"]

    assert resolution.payload["source_request_event_id"] ==
             comparison_review_request.dashboard_lifecycle_event_id

    assert resolution.payload["resolution_reason"] == "Resolved by browser smoke"
  end
end
