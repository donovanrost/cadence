defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowPresenterTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowPresenter,
    HistoricalWorkflowRequestDefaults
  }

  describe "request_form_defaults/1" do
    test "builds default request form values from dashboard context" do
      defaults =
        HistoricalWorkflowPresenter.request_form_defaults(%{
          realm: "backfill",
          data_source_id: "source-1",
          source_binding_id: "binding-1",
          point_id: "point-1",
          source_from: "2026-06-25T00:00:00Z",
          source_to: "2026-06-25T01:00:00Z",
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_view: "all_revisions",
          dashboard_limit_mode: "observed"
        })

      assert %HistoricalWorkflowRequestDefaults{} = defaults
      assert defaults.workflow == "backfill"
      assert defaults.realm == "backfill"
      assert defaults.data_source_id == "source-1"
      assert defaults.source_binding_id == "binding-1"
      assert defaults.observable_id == "point-1"
      assert defaults.point_id == "point-1"
      assert defaults.point_ids == "point-1"
      assert defaults.source_from == "2026-06-25T00:00:00Z"
      assert defaults.source_to == "2026-06-25T01:00:00Z"
      assert defaults.dashboard_time_mode == "replay_run"
      assert defaults.dashboard_replay_run_id == "replay-1"
      assert defaults.dashboard_data_view == "all_revisions"
      assert defaults.dashboard_limit_mode == "observed"
      assert defaults.reason == "operator_requested_backfill"
      assert defaults.confirmed == ""
      assert String.starts_with?(defaults.run_id, "telemetry_backfill_run_")

      assert %{
               "workflow" => "backfill",
               "run_id" => run_id,
               "realm" => "backfill",
               "data_source_id" => "source-1",
               "source_binding_id" => "binding-1",
               "observable_id" => "point-1",
               "point_id" => "point-1",
               "point_ids" => "point-1",
               "source_from" => "2026-06-25T00:00:00Z",
               "source_to" => "2026-06-25T01:00:00Z",
               "dashboard_time_mode" => "replay_run",
               "dashboard_replay_run_id" => "replay-1",
               "dashboard_data_view" => "all_revisions",
               "dashboard_limit_mode" => "observed",
               "reason" => "operator_requested_backfill",
               "confirmed" => ""
             } = HistoricalWorkflowRequestDefaults.form_params(defaults)

      assert run_id == defaults.run_id
    end

    test "uses empty dashboard context defaults" do
      defaults = HistoricalWorkflowPresenter.request_form_defaults()

      assert %HistoricalWorkflowRequestDefaults{
               realm: "backfill",
               data_source_id: "",
               source_binding_id: "",
               observable_id: "",
               point_id: "",
               point_ids: "",
               source_from: "",
               source_to: ""
             } = defaults
    end
  end

  describe "flash copy" do
    test "builds structured action outcomes for direct stage transitions" do
      assert %HistoricalWorkflowActionOutcome{
               action: :stage_transition,
               status: :ok,
               kind: :info,
               reason: "stage_recorded_job_queued",
               stage: "started",
               job_id: "job-1",
               dashboard_context: %{
                 dashboard_id: "dashboard-1",
                 dashboard_version: "7",
                 dashboard_time_mode: "replay_run",
                 dashboard_replay_run_id: "replay-1",
                 dashboard_data_view: "all_revisions",
                 dashboard_limit_mode: "observed"
               },
               message: "Historical data workflow started recorded and job job-1 queued."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stage_transition,
                 {:ok, {:ok, %{job_id: "job-1"}}},
                 %{
                   stage: "started",
                   dashboard_id: "dashboard-1",
                   dashboard_version: 7,
                   dashboard_time_mode: "replay_run",
                   dashboard_replay_run_id: "replay-1",
                   dashboard_data_view: "all_revisions",
                   dashboard_limit_mode: "observed"
                 }
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :stage_transition,
               status: :blocked,
               kind: :error,
               reason: "confirmation_required",
               stage: "approved",
               message:
                 "Confirm the historical data workflow approved transition before recording it."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stage_transition,
                 :unconfirmed,
                 %{stage: "approved"}
               )
    end

    test "builds structured action outcomes for requests and retries" do
      assert %HistoricalWorkflowActionOutcome{
               action: :request,
               status: :ok,
               kind: :info,
               reason: "request_group_recorded",
               count: 2,
               message: "Historical data workflow request group recorded for 2 points."
             } =
               HistoricalWorkflowPresenter.action_outcome(:request, {:ok, [:event_1, :event_2]})

      assert %HistoricalWorkflowActionOutcome{
               action: :request,
               status: :ok,
               reason: "request_group_recorded",
               count: 2,
               result_event_ids: "event-1,event-2",
               target_event_id: "event-1",
               target_run_id: "run-1"
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :request,
                 {:ok,
                  [
                    %{backfill_lifecycle_event_id: "event-1", backfill_run_id: "run-1"},
                    %{backfill_lifecycle_event_id: "event-2", backfill_run_id: "run-2"}
                  ]},
                 %{target_run_id: "run-1"}
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :correction_request,
               result_event_ids: "correction-event-1",
               target_event_id: "correction-event-1",
               target_run_id: "correction-run-1"
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :correction_request,
                 {:ok,
                  %{
                    backfill_lifecycle_event_id: "correction-event-1",
                    backfill_run_id: "correction-run-1"
                  }},
                 %{target_run_id: "correction-run-1"}
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :retry_job,
               status: :error,
               kind: :error,
               reason: "retry_job_failed",
               error: :job_not_found,
               message: "Failed to retry historical data workflow job: job not found"
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :retry_job,
                 {:error, :job_not_found}
               )

      assert %HistoricalWorkflowActionOutcome{
               action: :stale_replacement_job_requeue,
               status: :ok,
               kind: :info,
               reason: "stale_replacement_job_requeue_recorded",
               job_id: "job-stale-1",
               result_event_ids: "event-stale-requeue-1",
               target_event_id: "event-stale-requeue-1",
               target_run_id: "run-stale-1",
               message: "Requeued stale replacement job job-stale-1 and recorded audit event."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stale_replacement_job_requeue,
                 {:ok, %{job_id: "job-stale-1"},
                  %{
                    backfill_lifecycle_event_id: "event-stale-requeue-1",
                    backfill_run_id: "run-stale-1"
                  }},
                 %{target_event_id: "event-stale-requeue-1", target_run_id: "run-stale-1"}
               )
    end

    test "builds missing replacement inspection action outcomes" do
      assert %HistoricalWorkflowActionOutcome{
               action: :missing_replacement_job_inspection,
               status: :ok,
               kind: :info,
               reason: "missing_replacement_job_inspection_recorded",
               result_event_ids: "event-missing-inspection-1",
               target_event_id: "event-missing-inspection-1",
               target_run_id: "run-missing-1",
               message: "Recorded missing replacement job inspection."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :missing_replacement_job_inspection,
                 {:ok,
                  %{
                    backfill_lifecycle_event_id: "event-missing-inspection-1",
                    backfill_run_id: "run-missing-1"
                  }},
                 %{
                   target_event_id: "event-missing-inspection-1",
                   target_run_id: "run-missing-1"
                 }
               )
    end

    test "builds structured no-op outcome for ineligible group actions" do
      assert %HistoricalWorkflowActionOutcome{
               action: :group_stage_transition,
               status: :no_op,
               kind: :info,
               reason: "no_eligible_group_items",
               stage: "approved",
               request_group_id: "group-1",
               message:
                 "No approve items are eligible in request group group-1. The workflow panel was refreshed with current eligibility counts."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :group_stage_transition,
                 {:no_eligible, "group-1", "approved"}
               )
    end

    test "describes structured stage transition errors without raw tuples" do
      assert %HistoricalWorkflowActionOutcome{
               reason: "stage_transition_failed",
               error:
                 {:historical_workflow_stage_transition_blocked, "event-1",
                  "stage_transition_out_of_order"},
               message:
                 "Historical data workflow transition was blocked for event event-1: the requested stage is out of order."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stage_transition,
                 {:error,
                  {:historical_workflow_stage_transition_blocked, "event-1",
                   "stage_transition_out_of_order"}},
                 %{stage: "completed"}
               )

      refute HistoricalWorkflowPresenter.action_outcome(
               :stage_transition,
               {:error,
                {:historical_workflow_stage_transition_blocked, "event-1",
                 "stage_transition_out_of_order"}},
               %{stage: "completed"}
             ).message =~ "{:"
    end

    test "describes structured correction request errors without raw tuples" do
      assert %HistoricalWorkflowActionOutcome{
               reason: "correction_request_failed",
               error:
                 {:historical_workflow_correction_request_blocked, "failed-event-1",
                  "job_status_missing"},
               message:
                 "Corrected historical data workflow request was blocked for source event failed-event-1: workflow job status is missing."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :correction_request,
                 {:error,
                  {:historical_workflow_correction_request_blocked, "failed-event-1",
                   "job_status_missing"}}
               )
    end

    test "describes structured retry errors without raw tuples" do
      assert %HistoricalWorkflowActionOutcome{
               reason: "retry_job_failed",
               error: {:historical_workflow_retry_blocked, "failed-event-1", :job_run_mismatch},
               message:
                 "Historical data workflow retry was blocked for event failed-event-1: the selected job does not belong to the selected event run."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :retry_job,
                 {:error,
                  {:historical_workflow_retry_blocked, "failed-event-1", :job_run_mismatch}}
               )

      assert %HistoricalWorkflowActionOutcome{
               reason: "retry_group_failed_jobs_failed",
               request_group_id: "request-group-1",
               error:
                 {:historical_workflow_group_retry_blocked, "request-group-1",
                  "no_retryable_group_failures"},
               message:
                 "Historical data workflow group retry was blocked for request group request-group-1: the group has no retryable failed jobs."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :retry_group_failed_jobs,
                 {:error,
                  {:historical_workflow_group_retry_blocked, "request-group-1",
                   "no_retryable_group_failures"}}
               )
    end

    test "describes structured stale replacement recovery errors without raw tuples" do
      assert %HistoricalWorkflowActionOutcome{
               reason: "stale_replacement_job_requeue_failed",
               error:
                 {:historical_workflow_stale_replacement_inspection_blocked, "event-stale-1",
                  :job_not_stale},
               message:
                 "Stale replacement job action was blocked for event event-stale-1: the selected replacement job is not stale."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :stale_replacement_job_requeue,
                 {:error,
                  {:historical_workflow_stale_replacement_inspection_blocked, "event-stale-1",
                   :job_not_stale}}
               )
    end

    test "describes structured missing replacement inspection errors without raw tuples" do
      assert %HistoricalWorkflowActionOutcome{
               reason: "missing_replacement_job_inspection_failed",
               error:
                 {:historical_workflow_missing_replacement_inspection_blocked, "run-missing-1",
                  :replacement_event_not_found},
               message:
                 "Missing replacement job inspection was blocked for run run-missing-1: replacement event not found."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :missing_replacement_job_inspection,
                 {:error,
                  {:historical_workflow_missing_replacement_inspection_blocked, "run-missing-1",
                   :replacement_event_not_found}}
               )
    end

    test "normalizes action outcomes for rendered metadata" do
      assert %{
               action: "stage_transition",
               status: "ok",
               kind: "info",
               reason: "stage_recorded_job_queued",
               stage: "started",
               count: "3",
               job_id: "job-1",
               result_event_ids: "event-1,event-2",
               message: "queued"
             } =
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :stage_transition,
                 status: :ok,
                 kind: :info,
                 reason: "stage_recorded_job_queued",
                 stage: "started",
                 count: 3,
                 job_id: "job-1",
                 retry_scope: :replacement_jobs,
                 retry_run_ids: ["run-004-corrected", "run-005-corrected"],
                 result_event_ids: "event-1,event-2",
                 request_group_id: nil,
                 message: "queued"
               })

      assert %{
               retry_scope: "replacement_jobs",
               retry_run_ids: "run-004-corrected,run-005-corrected",
               retry_error_run_ids: "run-004-corrected",
               retry_error_event_ids: "failed-event-4",
               retry_error_items:
                 "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"
             } =
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :retry_group_failed_jobs,
                 retry_scope: :replacement_jobs,
                 retry_run_ids: "run-004-corrected, run-005-corrected",
                 retry_error_run_ids: "run-004-corrected",
                 retry_error_event_ids: "failed-event-4",
                 retry_error_items:
                   "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"
               })

      refute Map.has_key?(
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :request,
                 status: :ok,
                 kind: :info,
                 reason: "request_recorded",
                 stage: "",
                 message: "recorded"
               }),
               :stage
             )
    end

    test "normalizes action outcome target scope for inline workflow presentation" do
      assert %{
               action: "stage_transition",
               target_event_id: "event-1",
               target_run_id: "run-1",
               message: "recorded"
             } =
               HistoricalWorkflowPresenter.action_attrs(%{
                 action: :stage_transition,
                 status: :ok,
                 kind: :info,
                 reason: "stage_recorded",
                 target_event_id: "event-1",
                 target_run_id: "run-1",
                 message: "recorded"
               })
    end

    test "describes single and grouped workflow requests" do
      assert HistoricalWorkflowPresenter.request_flash([:event]) ==
               "Historical data workflow request recorded."

      assert HistoricalWorkflowPresenter.request_flash([:event_1, :event_2]) ==
               "Historical data workflow request group recorded for 2 points."
    end

    test "describes direct workflow stage outcomes" do
      assert HistoricalWorkflowPresenter.workflow_flash("started", {:ok, %{job_id: "job-1"}}) ==
               {:info, "Historical data workflow started recorded and job job-1 queued."}

      assert HistoricalWorkflowPresenter.workflow_flash("approved", {:ok, nil}) ==
               {:info, "Historical data workflow approved recorded."}

      assert HistoricalWorkflowPresenter.workflow_flash("started", {:error, :queue_down}) ==
               {:error,
                "Historical data workflow started recorded, but job dispatch failed: queue down"}
    end

    test "describes grouped workflow outcomes" do
      events = [:event_1, :event_2, :event_3]
      job_results = [{:ok, %{job_id: "job-1"}}, {:ok, nil}, {:error, :queue_down}]

      assert HistoricalWorkflowPresenter.group_flash("started", events, job_results) ==
               {:error,
                "Historical data workflow group started for 3 items; 1 job queued and 1 job dispatch failed."}

      assert HistoricalWorkflowPresenter.group_flash("approved", events, []) ==
               {:info, "Historical data workflow group approved recorded for 3 items."}
    end

    test "marks grouped workflow start as degraded when job dispatch fails" do
      assert %HistoricalWorkflowActionOutcome{
               action: :group_stage_transition,
               status: :degraded,
               kind: :error,
               reason: "group_started_job_dispatch_degraded",
               stage: "started",
               count: 3,
               result_event_ids: "event-1,event-2,event-3",
               target_event_id: "event-1",
               message:
                 "Historical data workflow group started for 3 items; 2 jobs queued and 1 job dispatch failed."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :group_stage_transition,
                 {:ok,
                  [
                    %{backfill_lifecycle_event_id: "event-1"},
                    %{backfill_lifecycle_event_id: "event-2"},
                    %{backfill_lifecycle_event_id: "event-3"}
                  ],
                  [{:ok, %{job_id: "job-1"}}, {:error, :queue_down}, {:ok, %{job_id: "job-3"}}]},
                 %{stage: "started"}
               )
    end

    test "describes retry and no-eligible group states" do
      summary = %{
        retried: 2,
        nonretryable: 1,
        skipped: 3,
        failed: 4,
        nonretryable_items: [
          %{
            run_id: "run-nonretryable",
            event_id: "failed-event-nonretryable",
            reason: "correction_required",
            recovery_action: "correct_workflow_request"
          }
        ],
        skipped_items: [
          %{
            run_id: "run-skipped",
            event_id: "failed-event-skipped",
            job_id: "job-skipped",
            job_status: "running",
            reason: "job_not_failed"
          }
        ],
        retry_error_items: [
          %{
            run_id: "run-004-corrected",
            event_id: "failed-event-4",
            job_id: "job-4",
            reason: "queue_down"
          }
        ]
      }

      assert HistoricalWorkflowPresenter.group_retry_flash(summary) ==
               "Retried 2 failed workflow jobs; skipped 1 non-retryable, 3 not-failed or missing, and 4 retry errors."

      assert %HistoricalWorkflowActionOutcome{
               action: :retry_group_failed_jobs,
               status: :degraded,
               kind: :error,
               reason: "retry_group_failed_jobs_degraded",
               retried: 2,
               retry_nonretryable: 1,
               retry_skipped: 3,
               retry_errors: 4,
               retry_scope: "replacement_jobs",
               retry_run_ids: "run-004-corrected",
               retry_nonretryable_run_ids: "run-nonretryable",
               retry_nonretryable_event_ids: "failed-event-nonretryable",
               retry_nonretryable_items:
                 "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
               retry_skipped_run_ids: "run-skipped",
               retry_skipped_event_ids: "failed-event-skipped",
               retry_skipped_items:
                 "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed",
               retry_error_run_ids: "run-004-corrected",
               retry_error_event_ids: "failed-event-4",
               retry_error_items:
                 "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
               message:
                 "Retried 2 failed workflow jobs; skipped 1 non-retryable, 3 not-failed or missing, and 4 retry errors."
             } =
               HistoricalWorkflowPresenter.action_outcome(
                 :retry_group_failed_jobs,
                 {:ok, summary},
                 %{retry_run_ids: ["run-004-corrected"]}
               )

      assert HistoricalWorkflowPresenter.no_eligible_group_flash("group-1", "approved") ==
               "No approve items are eligible in request group group-1. The workflow panel was refreshed with current eligibility counts."
    end
  end

  describe "group_stage_label/1" do
    test "maps workflow stage values to operator actions" do
      assert HistoricalWorkflowPresenter.group_stage_label("approved") == "approve"
      assert HistoricalWorkflowPresenter.group_stage_label("rejected") == "reject"
      assert HistoricalWorkflowPresenter.group_stage_label("started") == "start"
      assert HistoricalWorkflowPresenter.group_stage_label("completed") == "complete"
      assert HistoricalWorkflowPresenter.group_stage_label("failed") == "fail"
      assert HistoricalWorkflowPresenter.group_stage_label("requested") == "request"
      assert HistoricalWorkflowPresenter.group_stage_label("needs_review") == "needs review"
      assert HistoricalWorkflowPresenter.group_stage_label(nil) == "selected"
    end
  end
end
