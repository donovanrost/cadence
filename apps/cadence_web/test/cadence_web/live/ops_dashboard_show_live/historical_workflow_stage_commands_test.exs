defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageCommandsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflow,
    HistoricalWorkflowActionOutcome,
    HistoricalWorkflowParams,
    HistoricalWorkflowPresenter
  }

  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery
  alias Phoenix.LiveView.Socket

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
