defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflow,
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowParams,
    HistoricalWorkflowPresenter
  }

  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.Socket

  test "opens request panel with defaults from the current data selection" do
    socket =
      socket(%{
        dashboard_document: %Cadence.Dashboards.Document{
          dashboard_id: "dashboard-power",
          metadata: %{version: 4}
        },
        dashboard_data_realm: "backfill",
        dashboard_data_view: "as_recorded",
        dashboard_data_source_id: "managed_questdb_backfill",
        dashboard_source_binding_id: "binding-alpha",
        dashboard_time_mode: "archive",
        dashboard_replay_run_id: "replay-4",
        dashboard_limit_mode: "observed",
        dashboard_selected_data_ref: %{"point_id" => "HK.counter"},
        dashboard_time_from: "2026-06-22T10:00:00Z",
        dashboard_time_to: "2026-06-22T11:00:00Z"
      })

    socket = HistoricalWorkflow.open_request(socket)

    assert socket.assigns.panel == :historical_workflow_request

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :point_id) ==
             "HK.counter"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :data_source_id) ==
             "managed_questdb_backfill"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :dashboard_id) ==
             "dashboard-power"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :dashboard_version) ==
             "4"

    assert Form.input_value(
             socket.assigns.historical_workflow_request_form,
             :dashboard_time_mode
           ) == "archive"

    assert Form.input_value(
             socket.assigns.historical_workflow_request_form,
             :dashboard_replay_run_id
           ) == "replay-4"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :dashboard_data_view) ==
             "as_recorded"

    assert Form.input_value(
             socket.assigns.historical_workflow_request_form,
             :dashboard_limit_mode
           ) == "observed"
  end

  test "opens request panel from a comparison-review request with affected point ids" do
    request =
      comparison_review_request_event(
        findings: [
          %{
            "placement_id" => "placement-counter",
            "title" => "Counter",
            "state" => "increased",
            "decision_status" => "unhandled",
            "primary_observable_ids" => ["HK.counter"],
            "compare_observable_ids" => ["HK.counter"]
          },
          %{
            "placement_id" => "placement-voltage",
            "title" => "Voltage",
            "state" => "missing",
            "decision_status" => "unhandled",
            "observable_id" => "HK.voltage"
          }
        ]
      )

    socket =
      socket(%{
        dashboard_document: %Cadence.Dashboards.Document{
          dashboard_id: "dashboard-power",
          metadata: %{version: 4}
        },
        dashboard_lifecycle_events: [request],
        dashboard_data_realm: "backfill",
        dashboard_data_source_id: "managed_questdb_backfill",
        dashboard_source_binding_id: "binding-alpha",
        dashboard_time_from: "2026-06-22T10:00:00Z",
        dashboard_time_to: "2026-06-22T11:00:00Z"
      })

    socket =
      HistoricalWorkflow.open_comparison_review_request(socket, %{
        "request-event-id" => "dashboard-lifecycle-event-1"
      })

    assert socket.assigns.panel == :historical_workflow_request

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :observable_id) ==
             "HK.counter"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :point_id) ==
             "HK.counter"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :point_ids) ==
             "HK.counter, HK.voltage"

    assert Form.input_value(
             socket.assigns.historical_workflow_request_form,
             :comparison_review_request_event_id
           ) == "dashboard-lifecycle-event-1"

    assert Form.input_value(
             socket.assigns.historical_workflow_request_form,
             :comparison_review_request_kind
           ) == "comparison_open_findings_review"

    assert Form.input_value(
             socket.assigns.historical_workflow_request_form,
             :comparison_review_open_count
           ) == "2"

    assert Form.input_value(
             socket.assigns.historical_workflow_request_form,
             :comparison_review_open_placement_ids
           ) == "placement-1,placement-2"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :reason) ==
             "operator_requested_bulk_correction_authority_review"

    assert Form.input_value(socket.assigns.historical_workflow_request_form, :data_source_id) ==
             "managed_questdb_backfill"
  end

  test "open comparison-review request flashes when the request event is absent" do
    socket =
      socket()
      |> HistoricalWorkflow.open_comparison_review_request(%{
        "request-event-id" => "missing-request"
      })

    assert socket.assigns.flash["error"] == "Comparison review request is no longer available."
    refute Map.has_key?(socket.assigns, :historical_workflow_request_form)
  end

  test "recording a stage requires explicit confirmation before invoking commands" do
    socket =
      HistoricalWorkflow.record_stage(
        socket(),
        %{"workflow" => "backfill", "stage" => "approved"},
        record_stage: fn _params, _scope, _mission -> flunk("command should not run") end
      )

    assert socket.assigns.flash["error"] ==
             "Confirm the historical data workflow approved transition before recording it."

    assert_action_outcome(socket, %{
      action: "stage_transition",
      status: "blocked",
      kind: "error",
      reason: "confirmation_required",
      stage: "approved",
      message: "Confirm the historical data workflow approved transition before recording it."
    })
  end

  test "recording a stage flashes the job result and selects the event" do
    test_pid = self()
    event = workflow_event("event-stage-1")

    socket =
      HistoricalWorkflow.record_stage(
        socket(),
        %{
          "workflow" => "backfill",
          "stage" => "started",
          "confirmed" => "true",
          "point_id" => "HK.counter"
        },
        Keyword.merge(selection_opts(),
          record_stage: fn params, scope, mission ->
            send(test_pid, {:record_stage, params, scope.organization_id, mission.mission_id})
            {:ok, event, {:ok, %{job_id: "job-1"}}}
          end
        )
      )

    assert_received {:record_stage,
                     %HistoricalWorkflowParams{stage: "started", point_id: "HK.counter"}, "org-1",
                     "mission-1"}

    assert socket.assigns.flash["info"] ==
             "Historical data workflow started recorded and job job-1 queued."

    assert_action_outcome(socket, %{
      action: "stage_transition",
      status: "ok",
      kind: "info",
      reason: "stage_recorded_job_queued",
      stage: "started",
      job_id: "job-1",
      target_event_id: "event-stage-1",
      message: "Historical data workflow started recorded and job job-1 queued."
    })

    assert %SelectionQuery{} = socket.assigns.selected_workflow_query

    assert SelectionQuery.to_params(socket.assigns.selected_workflow_query) == %{
             "selected_target" => "telemetry_backfill_lifecycle_event",
             "selected_id" => "event-stage-1"
           }

    assert socket.assigns.selected_workflow_link.target_id == "event-stage-1"
  end

  test "recording a stage presents structured command errors as operator copy" do
    socket =
      HistoricalWorkflow.record_stage(
        socket(),
        %{
          "workflow" => "backfill",
          "stage" => "completed",
          "confirmed" => "true",
          "event_id" => "event-stage-1"
        },
        Keyword.merge(selection_opts(),
          record_stage: fn _params, _scope, _mission ->
            {:error,
             {:historical_workflow_stage_transition_blocked, "event-stage-1",
              "stage_transition_out_of_order"}}
          end
        )
      )

    assert socket.assigns.flash["error"] ==
             "Historical data workflow transition was blocked for event event-stage-1: the requested stage is out of order."

    assert_action_outcome(socket, %{
      action: "stage_transition",
      status: "error",
      kind: "error",
      reason: "stage_transition_failed",
      stage: "completed",
      target_event_id: "event-stage-1",
      message:
        "Historical data workflow transition was blocked for event event-stage-1: the requested stage is out of order."
    })

    refute socket.assigns.flash["error"] =~ "{:"
  end

  test "recording a group start selects the first event with a failed dispatch result" do
    events = [
      workflow_event("event-group-ok-1"),
      workflow_event("event-group-failed"),
      workflow_event("event-group-ok-2")
    ]

    socket =
      HistoricalWorkflow.record_group_stage(
        socket(),
        %{
          "workflow" => "backfill",
          "stage" => "started",
          "request_group_id" => "request-group-1",
          "confirmed" => "true"
        },
        Keyword.merge(selection_opts(),
          record_group_stage: fn params, _scope, _mission ->
            assert %HistoricalWorkflowParams{request_group_id: "request-group-1"} = params

            {:ok, events,
             [{:ok, %{job_id: "job-1"}}, {:error, :queue_down}, {:ok, %{job_id: "job-3"}}]}
          end
        )
      )

    assert socket.assigns.flash["error"] ==
             "Historical data workflow group started for 3 items; 2 jobs queued and 1 job dispatch failed."

    assert_action_outcome(socket, %{
      action: "group_stage_transition",
      status: "degraded",
      kind: "error",
      reason: "group_started_job_dispatch_degraded",
      stage: "started",
      count: "3",
      queued_jobs: "2",
      failed_jobs: "1",
      result_event_ids: "event-group-ok-1,event-group-failed,event-group-ok-2",
      target_event_id: "event-group-failed",
      message:
        "Historical data workflow group started for 3 items; 2 jobs queued and 1 job dispatch failed."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-group-failed"

    assert socket.assigns.selected_workflow_link.target_id == "event-group-failed"
  end

  test "retrying group failures selects the retry summary event" do
    event = workflow_event("event-retry-1")

    socket =
      HistoricalWorkflow.retry_group_failed_jobs(
        socket(),
        "request-group-1",
        "fallback-event",
        Keyword.merge(selection_opts(),
          retry_group_failed_jobs: fn request_group_id, _scope, _mission ->
            assert request_group_id == "request-group-1"
            {:ok, %{retried: 1, nonretryable: 0, skipped: 2, failed: 0, events: [event]}}
          end
        )
      )

    assert socket.assigns.flash["info"] ==
             "Retried 1 failed workflow jobs; skipped 0 non-retryable, 2 not-failed or missing, and 0 retry errors."

    assert_action_outcome(socket, %{
      action: "retry_group_failed_jobs",
      status: "ok",
      kind: "info",
      reason: "retry_group_failed_jobs_recorded",
      target_event_id: "event-retry-1",
      result_event_ids: "event-retry-1",
      retried: "1",
      retry_nonretryable: "0",
      retry_skipped: "2",
      retry_errors: "0",
      message:
        "Retried 1 failed workflow jobs; skipped 0 non-retryable, 2 not-failed or missing, and 0 retry errors."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-retry-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-retry-1"
  end

  test "retrying group failures preserves replacement run scope for command callbacks" do
    event = workflow_event("event-retry-1")

    socket =
      HistoricalWorkflow.retry_group_failed_jobs(
        socket(),
        "request-group-1",
        "fallback-event",
        Keyword.merge(selection_opts(),
          retry_run_ids: ["run-004-corrected"],
          retry_group_failed_jobs: fn request_group_id, _scope, _mission, opts ->
            assert request_group_id == "request-group-1"
            assert Keyword.fetch!(opts, :retry_run_ids) == ["run-004-corrected"]
            {:ok, %{retried: 1, nonretryable: 0, skipped: 0, failed: 0, events: [event]}}
          end
        )
      )

    assert socket.assigns.flash["info"] ==
             "Retried 1 failed workflow jobs; skipped 0 non-retryable, 0 not-failed or missing, and 0 retry errors."

    assert_action_outcome(socket, %{
      action: "retry_group_failed_jobs",
      status: "ok",
      kind: "info",
      reason: "retry_group_failed_jobs_recorded",
      target_event_id: "event-retry-1",
      result_event_ids: "event-retry-1",
      retried: "1",
      retry_nonretryable: "0",
      retry_skipped: "0",
      retry_errors: "0",
      retry_scope: "replacement_jobs",
      retry_run_ids: "run-004-corrected",
      message:
        "Retried 1 failed workflow jobs; skipped 0 non-retryable, 0 not-failed or missing, and 0 retry errors."
    })
  end

  test "retrying group failures reports partial retry errors as degraded" do
    event = workflow_event("event-retry-1")

    socket =
      HistoricalWorkflow.retry_group_failed_jobs(
        socket(),
        "request-group-1",
        "fallback-event",
        Keyword.merge(selection_opts(),
          retry_group_failed_jobs: fn request_group_id, _scope, _mission ->
            assert request_group_id == "request-group-1"

            {:ok,
             %{
               retried: 1,
               nonretryable: 0,
               skipped: 0,
               failed: 2,
               retry_error_items: [
                 %{
                   run_id: "run-004-corrected",
                   event_id: "failed-event-4",
                   job_id: "job-4",
                   reason: "queue_down"
                 }
               ],
               events: [event]
             }}
          end
        )
      )

    assert socket.assigns.flash["error"] ==
             "Retried 1 failed workflow jobs; skipped 0 non-retryable, 0 not-failed or missing, and 2 retry errors."

    assert_action_outcome(socket, %{
      action: "retry_group_failed_jobs",
      status: "degraded",
      kind: "error",
      reason: "retry_group_failed_jobs_degraded",
      target_event_id: "event-retry-1",
      result_event_ids: "event-retry-1",
      retried: "1",
      retry_nonretryable: "0",
      retry_skipped: "0",
      retry_errors: "2",
      retry_error_run_ids: "run-004-corrected",
      retry_error_event_ids: "failed-event-4",
      retry_error_items: "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
      message:
        "Retried 1 failed workflow jobs; skipped 0 non-retryable, 0 not-failed or missing, and 2 retry errors."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-retry-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-retry-1"
  end

  test "inspecting stale replacement jobs records and selects audit event" do
    event = workflow_event("event-stale-inspection-1")

    socket =
      HistoricalWorkflow.inspect_stale_replacement_job(
        socket(),
        "job-stale-1",
        "event-source-1",
        Keyword.merge(selection_opts(),
          inspect_stale_replacement_job: fn job_id, event_id, _scope, _mission ->
            assert job_id == "job-stale-1"
            assert event_id == "event-source-1"
            {:ok, event}
          end
        )
      )

    assert socket.assigns.flash["info"] == "Recorded stale replacement job inspection."

    assert_action_outcome(socket, %{
      action: "stale_replacement_job_inspection",
      status: "ok",
      kind: "info",
      reason: "stale_replacement_job_inspection_recorded",
      target_event_id: "event-stale-inspection-1",
      result_event_ids: "event-stale-inspection-1",
      message: "Recorded stale replacement job inspection."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-stale-inspection-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-stale-inspection-1"
  end

  test "inspecting missing replacement jobs records and selects audit event" do
    event =
      "event-missing-inspection-1"
      |> workflow_event()
      |> Map.put(:backfill_run_id, "run-missing-replacement")

    socket =
      HistoricalWorkflow.inspect_missing_replacement_job(
        socket(),
        "group-1",
        "run-missing-replacement",
        Keyword.merge(selection_opts(),
          inspect_missing_replacement_job: fn request_group_id,
                                              replacement_run_id,
                                              _scope,
                                              _mission ->
            assert request_group_id == "group-1"
            assert replacement_run_id == "run-missing-replacement"
            {:ok, event}
          end
        )
      )

    assert socket.assigns.flash["info"] == "Recorded missing replacement job inspection."

    assert_action_outcome(socket, %{
      action: "missing_replacement_job_inspection",
      status: "ok",
      kind: "info",
      reason: "missing_replacement_job_inspection_recorded",
      target_event_id: "event-missing-inspection-1",
      target_run_id: "run-missing-replacement",
      result_event_ids: "event-missing-inspection-1",
      message: "Recorded missing replacement job inspection."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-missing-inspection-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-missing-inspection-1"
  end

  test "requeueing stale replacement jobs records and selects audit event" do
    event =
      "event-stale-requeue-1"
      |> workflow_event()
      |> Map.put(:backfill_run_id, "run-stale-requeued")

    socket =
      HistoricalWorkflow.requeue_stale_replacement_job(
        socket(),
        "job-stale-1",
        "event-source-1",
        Keyword.merge(selection_opts(),
          requeue_stale_replacement_job: fn job_id, event_id, _scope, _mission ->
            assert job_id == "job-stale-1"
            assert event_id == "event-source-1"
            {:ok, %{job_id: "job-stale-1", status: :queued}, event}
          end
        )
      )

    assert socket.assigns.flash["info"] ==
             "Requeued stale replacement job job-stale-1 and recorded audit event."

    assert_action_outcome(socket, %{
      action: "stale_replacement_job_requeue",
      status: "ok",
      kind: "info",
      reason: "stale_replacement_job_requeue_recorded",
      job_id: "job-stale-1",
      target_event_id: "event-stale-requeue-1",
      target_run_id: "run-stale-requeued",
      result_event_ids: "event-stale-requeue-1",
      message: "Requeued stale replacement job job-stale-1 and recorded audit event."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-stale-requeue-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-stale-requeue-1"
  end

  defp selection_opts do
    [
      put_link_selection: fn socket, query, link ->
        socket
        |> assign(:selected_workflow_query, query)
        |> assign(:selected_workflow_link, link)
      end
    ]
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            current_scope: %{organization_id: "org-1", user: %{id: "operator-1"}},
            current_mission: %{mission_id: "mission-1"},
            panel: nil,
            selected_point_id: nil,
            dashboard_selected_data_ref: nil,
            dashboard_data_realm: "backfill",
            dashboard_data_source_id: nil,
            dashboard_source_binding_id: nil,
            dashboard_time_from: nil,
            dashboard_time_to: nil
          },
          assigns
        )
    }
  end

  defp workflow_event(event_id) do
    %{
      backfill_lifecycle_event_id: event_id,
      realm: "backfill",
      data_source_id: "managed_questdb_backfill",
      binding_id: "binding-alpha",
      point_id: "HK.counter"
    }
  end

  defp assert_action_outcome(socket, expected_attrs) do
    assert %HistoricalWorkflowActionOutcome{} =
             outcome =
             socket.assigns.data_link_action_outcome

    assert HistoricalWorkflowPresenter.action_attrs(outcome) == expected_attrs
  end
end
