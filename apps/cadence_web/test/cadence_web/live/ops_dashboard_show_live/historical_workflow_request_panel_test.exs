defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestPanelTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflow
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
end
