defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRetryCommandsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflow,
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowPresenter
  }

  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.LiveView.Socket

  test "retrying a failed replacement job preserves replacement run scope in the action outcome" do
    event = workflow_event("event-retry-1")

    socket =
      HistoricalWorkflow.retry_job(
        socket(),
        "job-4",
        "event-4",
        Keyword.merge(selection_opts(),
          replacement_run_id: "run-004-corrected",
          retry_job: fn job_id, event_id, _scope, _mission ->
            assert job_id == "job-4"
            assert event_id == "event-4"
            {:ok, %{job_id: job_id}, event}
          end
        )
      )

    assert socket.assigns.flash["info"] ==
             "Retried historical data workflow job job-4 and recorded retry event."

    assert_action_outcome(socket, %{
      action: "retry_job",
      status: "ok",
      kind: "info",
      reason: "retry_job_recorded",
      job_id: "job-4",
      result_event_ids: "event-retry-1",
      target_event_id: "event-retry-1",
      target_run_id: "run-004-corrected",
      message: "Retried historical data workflow job job-4 and recorded retry event."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-retry-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-retry-1"
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
      request_group_id: "request-group-1",
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
      request_group_id: "request-group-1",
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

  test "retrying group failures preserves request group context on policy errors" do
    socket =
      HistoricalWorkflow.retry_group_failed_jobs(
        socket(),
        "request-group-1",
        "fallback-event",
        retry_group_failed_jobs: fn request_group_id, _scope, _mission ->
          assert request_group_id == "request-group-1"

          {:error,
           {:historical_workflow_group_retry_blocked, request_group_id,
            "no_retryable_group_failures"}}
        end
      )

    assert socket.assigns.flash["error"] ==
             "Historical data workflow group retry was blocked for request group request-group-1: the group has no retryable failed jobs."

    assert_action_outcome(socket, %{
      action: "retry_group_failed_jobs",
      status: "error",
      kind: "error",
      reason: "retry_group_failed_jobs_failed",
      request_group_id: "request-group-1",
      target_event_id: "fallback-event",
      message:
        "Historical data workflow group retry was blocked for request group request-group-1: the group has no retryable failed jobs."
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
      request_group_id: "request-group-1",
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
