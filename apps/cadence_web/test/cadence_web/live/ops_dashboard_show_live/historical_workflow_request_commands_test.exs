defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestCommandsTest do
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

  test "recording a bulk request preserves request group context" do
    events = [
      "event-request-1"
      |> workflow_event()
      |> Map.merge(%{
        backfill_run_id: "request-group-1-001",
        payload: %{"request_group_id" => "request-group-1"}
      }),
      "event-request-2"
      |> workflow_event()
      |> Map.merge(%{
        backfill_run_id: "request-group-1-002",
        payload: %{"request_group_id" => "request-group-1"}
      })
    ]

    socket =
      HistoricalWorkflow.record_request(
        socket(),
        %{
          "workflow" => "backfill",
          "run_id" => "request-group-1",
          "point_ids" => "HK.counter, HK.voltage",
          "confirmed" => "true"
        },
        Keyword.merge(selection_opts(),
          record_request: fn params, _scope, _mission ->
            assert %HistoricalWorkflowParams{run_id: "request-group-1"} = params
            {:ok, events, %{"run_id" => "request-group-1"}}
          end
        )
      )

    assert socket.assigns.flash["info"] ==
             "Historical data workflow request group recorded for 2 points."

    assert_action_outcome(socket, %{
      action: "request",
      status: "ok",
      kind: "info",
      reason: "request_group_recorded",
      count: "2",
      request_group_id: "request-group-1",
      result_event_ids: "event-request-1,event-request-2",
      target_event_id: "event-request-1",
      target_run_id: "request-group-1-001",
      message: "Historical data workflow request group recorded for 2 points."
    })

    assert SelectionQuery.value(socket.assigns.selected_workflow_query, "selected_id") ==
             "event-request-1"

    assert socket.assigns.selected_workflow_link.target_id == "event-request-1"
  end

  test "recording a request preserves request group context on errors" do
    socket =
      HistoricalWorkflow.record_request(
        socket(),
        %{
          "workflow" => "backfill",
          "run_id" => "request-group-1",
          "point_ids" => "HK.counter, HK.voltage",
          "confirmed" => "true"
        },
        record_request: fn params, _scope, _mission ->
          assert %HistoricalWorkflowParams{run_id: "request-group-1"} = params
          {:error, :source_unavailable}
        end
      )

    assert socket.assigns.flash["error"] ==
             "Failed to record historical data workflow request: source unavailable"

    assert_action_outcome(socket, %{
      action: "request",
      status: "error",
      kind: "error",
      reason: "request_failed",
      request_group_id: "request-group-1",
      message: "Failed to record historical data workflow request: source unavailable"
    })
  end

  test "unconfirmed requests preserve request group context" do
    socket =
      HistoricalWorkflow.record_request(
        socket(),
        %{
          "workflow" => "backfill",
          "run_id" => "request-group-1",
          "point_ids" => "HK.counter, HK.voltage"
        },
        record_request: fn _params, _scope, _mission -> flunk("command should not run") end
      )

    assert socket.assigns.flash["error"] ==
             "Confirm the historical data workflow request before recording it."

    assert_action_outcome(socket, %{
      action: "request",
      status: "blocked",
      kind: "error",
      reason: "confirmation_required",
      request_group_id: "request-group-1",
      message: "Confirm the historical data workflow request before recording it."
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
