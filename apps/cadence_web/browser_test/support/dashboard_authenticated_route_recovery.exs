defmodule CadenceWeb.Assets.DashboardAuthenticatedRouteRecovery do
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
      base_unix: base_unix,
      base_url: base_url,
      dashboard: dashboard,
      mission: mission,
      org: org,
      script: script,
      user: user
    } = context

    retry_run_id = "browser-smoke-workflow-run-retry"
    retry_source_from = DateTime.from_unix!(base_unix - 60)
    retry_source_to = DateTime.from_unix!(base_unix + 60)

    assert {:ok, failed_event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "failed",
               %{
                 backfill_run_id: retry_run_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.counter",
                 point_id: "HK.counter",
                 source_from: retry_source_from,
                 source_to: retry_source_to,
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "failure" => "source window unavailable",
                   "request_source" => "dashboard_direct_request",
                   "request_mode" => "bulk_points",
                   "request_group_id" => "browser-smoke-workflow-retry-group",
                   "request_item_index" => 1,
                   "request_item_count" => 2,
                   "request_item_run_id" => retry_run_id,
                   "dashboard_context" => %{
                     "dashboard_id" => dashboard.dashboard_id,
                     "dashboard_version" => "1",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-retry-browser",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, retry_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               retry_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => retry_run_id}
               }
             )

    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == retry_job.job_id))

    assert {:ok, failed_job} =
             Cadence.Jobs.fail_worker_start(retry_job.job_id, :source_window_failed)

    assert failed_job.status == :failed

    retry_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: failed_event.backfill_lifecycle_event_id
    }

    retry_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{retry_query}"

    assert {retry_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "retry-workflow",
                 "--url",
                 retry_dashboard_url,
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

    assert retry_output =~ "dashboard_viewport_smoke passed"

    assert {:ok, retried_job} = Cadence.fetch_telemetry_historical_data_workflow_job(retry_run_id)
    assert retried_job.status == :queued
    assert retried_job.failure_reason == nil

    assert [retried_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_retried
             )
             |> Enum.filter(&(&1.backfill_run_id == retry_run_id))

    assert retried_event.reason == "dashboard_historical_workflow_retried"
    assert retried_event.payload["retry_action"] == "retry_job"

    assert retried_event.payload["retry_source_event_id"] ==
             failed_event.backfill_lifecycle_event_id

    assert retried_event.payload["retry_job_id"] == retry_job.job_id
    assert retried_event.payload["retry_job_status"] == "queued"

    correction_run_id = "browser-smoke-workflow-run-nonretryable"
    corrected_run_id = "browser-smoke-workflow-run-corrected"

    assert {:ok, correction_group_context_event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "completed",
               %{
                 backfill_run_id: "browser-smoke-workflow-run-context",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK.voltage",
                 point_id: "HK.voltage",
                 authority: :authoritative,
                 reason: "historical_data_job_completed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "request_source" => "dashboard_direct_request",
                   "request_mode" => "bulk_points",
                   "request_group_id" => "browser-smoke-workflow-correction-group",
                   "request_item_index" => 2,
                   "request_item_count" => 2,
                   "request_item_run_id" => "browser-smoke-workflow-run-context"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_source_event} =
             Cadence.record_telemetry_historical_data_workflow_event(
               "backfill",
               "failed",
               %{
                 backfill_run_id: correction_run_id,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :backfill,
                 data_source_id: "managed_questdb_backfill",
                 binding_id: "backfill_telemetry",
                 observable_id: "HK counter",
                 point_id: "HK counter",
                 authority: :advisory,
                 reason: "historical_data_job_failed",
                 actor_id: "system",
                 actor_kind: "system",
                 payload: %{
                   "request_source" => "dashboard_direct_request",
                   "request_mode" => "bulk_points",
                   "request_group_id" => "browser-smoke-workflow-correction-group",
                   "request_item_index" => 1,
                   "request_item_count" => 2,
                   "request_item_run_id" => correction_run_id,
                   "dashboard_context" => %{
                     "dashboard_id" => dashboard.dashboard_id,
                     "dashboard_version" => "1",
                     "dashboard_time_mode" => "replay_run",
                     "dashboard_replay_run_id" => "replay-correction-browser",
                     "dashboard_data_view" => "all_revisions",
                     "dashboard_limit_mode" => "observed"
                   },
                   "source" => %{
                     "failure" => %{
                       "code" => "missing_field:point_id",
                       "retryable" => false,
                       "retry_blockers" => ["missing point_id"],
                       "recovery_action" => "correct_workflow_request"
                     }
                   }
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, correction_job} =
             Cadence.Jobs.enqueue(
               :telemetry_historical_data_workflow,
               mission.mission_id,
               correction_run_id,
               %{
                 "workflow" => "backfill",
                 "attrs" => %{"backfill_run_id" => correction_run_id}
               }
             )

    assert Enum.any?(Cadence.Jobs.claim_jobs(10), &(&1.job_id == correction_job.job_id))

    assert {:ok, failed_correction_job} =
             Cadence.Jobs.fail_worker_start(correction_job.job_id, :missing_point_id)

    assert failed_correction_job.status == :failed

    correction_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: correction_group_context_event.backfill_lifecycle_event_id
    }

    correction_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{correction_query}"

    assert {correction_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "correction-workflow",
                 "--url",
                 correction_dashboard_url,
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

    assert correction_output =~ "dashboard_viewport_smoke passed"

    corrected_events =
      mission.mission_id
      |> Storage.list_backfill_lifecycle_events(
        organization_id: org.organization_id,
        backfill_run_id: corrected_run_id
      )

    assert %{event_type: :backfill_requested} =
             corrected_event =
             Enum.find(corrected_events, &(&1.event_type == :backfill_requested))

    assert corrected_event.reason == "browser_smoke_historical_correction"
    assert corrected_event.point_id == "HK counter"
    assert corrected_event.payload["recovery_action"] == "correct_workflow_request"
    assert corrected_event.payload["correction_source"] == "dashboard_correction_request"
    assert corrected_event.payload["correction_source_event_type"] == "backfill_failed"
    assert corrected_event.payload["request_mode"] == "bulk_points"

    assert corrected_event.payload["request_group_id"] ==
             "browser-smoke-workflow-correction-group"

    assert corrected_event.payload["request_item_index"] == 1
    assert corrected_event.payload["request_item_count"] == 2
    assert corrected_event.payload["request_item_run_id"] == corrected_run_id
    assert corrected_event.payload["corrects_run_id"] == correction_run_id

    assert corrected_event.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert corrected_event.payload["corrects_job_id"] == correction_job.job_id

    assert corrected_event.payload["dashboard_context"] == %{
             "dashboard_id" => dashboard.dashboard_id,
             "dashboard_version" => "1",
             "dashboard_time_mode" => "replay_run",
             "dashboard_replay_run_id" => "replay-correction-browser",
             "dashboard_data_view" => "all_revisions",
             "dashboard_limit_mode" => "observed"
           }

    assert %{event_type: :backfill_approved} =
             approved_replacement =
             Enum.find(corrected_events, &(&1.event_type == :backfill_approved))

    assert approved_replacement.reason == "dashboard_recovery_replacement_approved"

    assert approved_replacement.payload["request_group_id"] ==
             "browser-smoke-workflow-correction-group"

    assert approved_replacement.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert approved_replacement.payload["group_transition_source"] == "dashboard_group_action"
    assert approved_replacement.payload["group_transition_scope"] == "replacement_corrections"

    assert %{event_type: :backfill_started} =
             started_replacement =
             Enum.find(corrected_events, &(&1.event_type == :backfill_started))

    assert started_replacement.reason == "dashboard_recovery_replacement_started"
    assert started_replacement.backfill_run_id == corrected_run_id

    assert started_replacement.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert started_replacement.payload["group_transition_source"] == "dashboard_group_action"
    assert started_replacement.payload["group_transition_scope"] == "replacement_corrections"

    assert %{event_type: :backfill_completed} =
             completed_replacement =
             Enum.find(corrected_events, &(&1.event_type == :backfill_completed))

    assert completed_replacement.reason == "dashboard_recovery_replacement_completed"
    assert completed_replacement.backfill_run_id == corrected_run_id

    assert completed_replacement.payload["corrects_event_id"] ==
             correction_source_event.backfill_lifecycle_event_id

    assert completed_replacement.payload["group_transition_source"] == "dashboard_group_action"
    assert completed_replacement.payload["group_transition_scope"] == "replacement_corrections"

    closure_group_id = "browser-smoke-workflow-closure-group"
    closure_failed_run_id = "browser-smoke-workflow-closure-failed"
    closure_corrected_run_id = "browser-smoke-workflow-closure-corrected"
    closure_ready_run_id = "browser-smoke-workflow-closure-ready"

    closure_dashboard_context = %{
      "dashboard_id" => dashboard.dashboard_id,
      "dashboard_version" => "1",
      "dashboard_time_mode" => "replay_run",
      "dashboard_replay_run_id" => "replay-closure-browser",
      "dashboard_data_view" => "all_revisions",
      "dashboard_limit_mode" => "observed"
    }

    closure_source_job =
      enqueue_failed_historical_workflow_job!(
        mission,
        closure_failed_run_id,
        :closure_ready_source_failed
      )

    closure_source_event =
      record_backfill_workflow_event!(
        org,
        mission,
        "failed",
        %{
          run_id: closure_failed_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: %{
            "dashboard_context" => closure_dashboard_context,
            "source" => %{
              "failure" => %{
                "code" => "missing_field:point_id",
                "retryable" => false,
                "retry_blockers" => ["missing point_id"],
                "recovery_action" => "correct_workflow_request"
              }
            }
          }
        }
      )

    closure_correction_payload = %{
      "dashboard_context" => closure_dashboard_context,
      "correction_source" => "dashboard_correction_request",
      "correction_source_event_type" => "backfill_failed",
      "recovery_action" => "correct_workflow_request",
      "corrects_run_id" => closure_failed_run_id,
      "corrects_event_id" => closure_source_event.backfill_lifecycle_event_id,
      "corrects_job_id" => closure_source_job.job_id
    }

    _closure_corrected_requested =
      record_backfill_workflow_event!(
        org,
        mission,
        "requested",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_corrected_approved =
      record_backfill_workflow_event!(
        org,
        mission,
        "approved",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_corrected_started =
      record_backfill_workflow_event!(
        org,
        mission,
        "started",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_corrected_completed =
      record_backfill_workflow_event!(
        org,
        mission,
        "completed",
        %{
          run_id: closure_corrected_run_id,
          point_id: "HK.current",
          request_group_id: closure_group_id,
          item_index: 1,
          item_count: 2,
          payload: closure_correction_payload
        }
      )

    _closure_ready_requested =
      record_backfill_workflow_event!(
        org,
        mission,
        "requested",
        %{
          run_id: closure_ready_run_id,
          point_id: "HK.voltage",
          request_group_id: closure_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{"dashboard_context" => closure_dashboard_context}
        }
      )

    _closure_ready_approved =
      record_backfill_workflow_event!(
        org,
        mission,
        "approved",
        %{
          run_id: closure_ready_run_id,
          point_id: "HK.voltage",
          request_group_id: closure_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{"dashboard_context" => closure_dashboard_context}
        }
      )

    closure_ready_started =
      record_backfill_workflow_event!(
        org,
        mission,
        "started",
        %{
          run_id: closure_ready_run_id,
          point_id: "HK.voltage",
          request_group_id: closure_group_id,
          item_index: 2,
          item_count: 2,
          payload: %{"dashboard_context" => closure_dashboard_context}
        }
      )

    _closure_corrected_job =
      enqueue_completed_historical_workflow_job!(mission, closure_corrected_run_id)

    _closure_ready_job =
      enqueue_completed_historical_workflow_job!(mission, closure_ready_run_id)

    closure_query = %{
      panel: "data_link",
      selected_target: "telemetry_backfill_lifecycle_event",
      selected_id: closure_ready_started.backfill_lifecycle_event_id
    }

    closure_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{closure_query}"

    assert {closure_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "closure-completion-workflow",
                 "--url",
                 closure_dashboard_url,
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

    assert closure_output =~ "dashboard_viewport_smoke passed"

    assert [closure_completion_event] =
             mission.mission_id
             |> Storage.list_backfill_lifecycle_events(
               organization_id: org.organization_id,
               event_type: :backfill_completed
             )
             |> Enum.filter(&(&1.backfill_run_id == closure_ready_run_id))

    assert closure_completion_event.reason == "dashboard_recovery_group_completed"
    assert closure_completion_event.payload["request_group_id"] == closure_group_id
    assert closure_completion_event.payload["request_item_index"] == 2
    assert closure_completion_event.payload["request_item_count"] == 2
    assert closure_completion_event.payload["request_item_run_id"] == closure_ready_run_id

    assert closure_completion_event.payload["requested_event_id"] ==
             closure_ready_started.backfill_lifecycle_event_id

    assert closure_completion_event.payload["group_transition_source"] ==
             "dashboard_group_action"

    assert closure_completion_event.payload["dashboard_context"] == closure_dashboard_context

    context
  end
end
