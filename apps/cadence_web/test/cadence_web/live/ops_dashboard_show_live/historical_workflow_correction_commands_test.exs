defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionCommandsTest do
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

  test "recording a correction request preserves request group context" do
    event =
      "event-correction-1"
      |> workflow_event()
      |> Map.put(:backfill_run_id, "run-corrected-1")

    socket =
      HistoricalWorkflow.record_correction_request(
        socket(),
        %{
          "workflow" => "backfill",
          "run_id" => "run-corrected-1",
          "original_run_id" => "run-original-1",
          "original_event_id" => "event-original-1",
          "original_job_id" => "job-original-1",
          "request_group_id" => "request-group-1",
          "confirmed" => "true"
        },
        Keyword.merge(selection_opts(),
          record_correction_request: fn params, _scope, _mission ->
            assert %HistoricalWorkflowParams{request_group_id: "request-group-1"} = params
            {:ok, event}
          end
        )
      )

    assert socket.assigns.flash["info"] ==
             "Corrected historical data workflow request recorded."

    assert_action_outcome(socket, %{
      action: "correction_request",
      status: "ok",
      kind: "info",
      reason: "correction_request_recorded",
      request_group_id: "request-group-1",
      result_event_ids: "event-correction-1",
      target_event_id: "event-correction-1",
      target_run_id: "run-corrected-1",
      message: "Corrected historical data workflow request recorded."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-correction-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-correction-1"
  end

  test "recording a correction request preserves request group context on errors" do
    socket =
      HistoricalWorkflow.record_correction_request(
        socket(),
        %{
          "workflow" => "backfill",
          "original_run_id" => "run-original-1",
          "original_event_id" => "event-original-1",
          "request_group_id" => "request-group-1",
          "confirmed" => "true"
        },
        record_correction_request: fn params, _scope, _mission ->
          assert %HistoricalWorkflowParams{request_group_id: "request-group-1"} = params

          {:error,
           {:historical_workflow_correction_request_blocked, "event-original-1",
            "job_status_missing"}}
        end
      )

    assert socket.assigns.flash["error"] ==
             "Corrected historical data workflow request was blocked for source event event-original-1: workflow job status is missing."

    assert_action_outcome(socket, %{
      action: "correction_request",
      status: "error",
      kind: "error",
      reason: "correction_request_failed",
      request_group_id: "request-group-1",
      target_event_id: "event-original-1",
      target_run_id: "run-original-1",
      message:
        "Corrected historical data workflow request was blocked for source event event-original-1: workflow job status is missing."
    })
  end

  test "unconfirmed correction requests preserve request group context" do
    socket =
      HistoricalWorkflow.record_correction_request(
        socket(),
        %{
          "workflow" => "backfill",
          "original_run_id" => "run-original-1",
          "original_event_id" => "event-original-1",
          "request_group_id" => "request-group-1"
        },
        record_correction_request: fn _params, _scope, _mission ->
          flunk("command should not run")
        end
      )

    assert socket.assigns.flash["error"] ==
             "Confirm the corrected historical data workflow request before recording it."

    assert_action_outcome(socket, %{
      action: "correction_request",
      status: "blocked",
      kind: "error",
      reason: "confirmation_required",
      request_group_id: "request-group-1",
      target_event_id: "event-original-1",
      target_run_id: "run-original-1",
      message: "Confirm the corrected historical data workflow request before recording it."
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
