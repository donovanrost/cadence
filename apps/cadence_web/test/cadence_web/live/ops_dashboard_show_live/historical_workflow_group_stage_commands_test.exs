defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStageCommandsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflow,
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowPresenter
  }

  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowParams
  alias Phoenix.LiveView.Socket

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
      request_group_id: "request-group-1",
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

  test "recording a group stage preserves request group context on errors" do
    socket =
      HistoricalWorkflow.record_group_stage(
        socket(),
        %{
          "workflow" => "backfill",
          "stage" => "approved",
          "request_group_id" => "request-group-1",
          "event_id" => "event-group-1",
          "confirmed" => "true"
        },
        record_group_stage: fn params, _scope, _mission ->
          assert %HistoricalWorkflowParams{request_group_id: "request-group-1"} = params
          {:error, {:request_group_not_found, "request-group-1"}}
        end
      )

    assert socket.assigns.flash["error"] ==
             "Historical workflow request group request-group-1 was not found."

    assert_action_outcome(socket, %{
      action: "group_stage_transition",
      status: "error",
      kind: "error",
      reason: "group_stage_transition_failed",
      stage: "approved",
      request_group_id: "request-group-1",
      target_event_id: "event-group-1",
      message: "Historical workflow request group request-group-1 was not found."
    })
  end

  test "unconfirmed group stages preserve request group context" do
    socket =
      HistoricalWorkflow.record_group_stage(
        socket(),
        %{
          "workflow" => "backfill",
          "stage" => "started",
          "request_group_id" => "request-group-1",
          "event_id" => "event-group-1"
        },
        record_group_stage: fn _params, _scope, _mission -> flunk("command should not run") end
      )

    assert socket.assigns.flash["error"] ==
             "Confirm the historical data workflow group started transition before recording it."

    assert_action_outcome(socket, %{
      action: "group_stage_transition",
      status: "blocked",
      kind: "error",
      reason: "confirmation_required",
      stage: "started",
      request_group_id: "request-group-1",
      target_event_id: "event-group-1",
      message:
        "Confirm the historical data workflow group started transition before recording it."
    })
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
