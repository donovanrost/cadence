defmodule CadenceWeb.OpsDashboardShowLive.RenderPanelModelTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document, ValidationResult}
  alias CadenceWeb.OpsDashboardShowLive.RenderPanelModel

  test "open? reflects shell panel visibility" do
    assert RenderPanelModel.open?(%{panel: :add_widget}) == true
    assert RenderPanelModel.open?(%{panel: nil}) == false
  end

  test "props prepares panel data from form filters, selections, lifecycle, and diagnostics" do
    widget_form = to_form(%{"point_q" => "temp"}, as: :widget)
    history_form = to_form(%{"workflow" => "backfill"}, as: :historical_workflow_request)

    runtime_diagnostics = %{
      refresh_status: "settled",
      recent_invalidations: [%{id: "invalidation-1"}]
    }

    props =
      assigns(%{
        panel: :add_widget,
        widget_form: widget_form,
        historical_workflow_request_form: history_form,
        points: [
          %{point_id: "HK.temp", description: "Battery temperature"},
          %{point_id: "HK.voltage", description: "Bus voltage"}
        ],
        operational_observables: [
          %{observable_id: "obs.temp", name: "Temperature bit rate", description: ""},
          %{observable_id: "obs.rate", name: "Bit rate", description: ""}
        ],
        selected_point_id: "HK.temp",
        selected_point_ids: ["HK.temp", "obs.temp"],
        dashboard_scope_context: %{primary: %{kind: "spacecraft", ids: ["sc-1"]}},
        widget_error: "invalid widget",
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: "event-1",
        dashboard_review_placement_id: "placement-1",
        dashboard_selected_publish_issue_id: "error:invalid-grid",
        dashboard_comparison_review_action_outcome: %{action: :comparison_review_bulk_decision},
        spacecraft: [%{spacecraft_id: "SC-1"}],
        dashboard_summary: %{draft_version: 2},
        dashboard_versions: [%{version: 2}],
        dashboard_lifecycle_events: [%{event_type: :created}],
        dashboard_comparison_review_queue: %{count: 1, requests: [%{event_id: "review-1"}]},
        dashboard_source_action_events: [%{source_health_event_id: "source-health-event-1"}],
        dashboard_publish_validation: %ValidationResult{valid?: false},
        dashboard_publish_validation_freshness: freshness()
      })
      |> RenderPanelModel.props(runtime_diagnostics, "/dashboard-path")

    assert props.panel == :add_widget
    assert props.dashboard_activity_filter == :open_comparison_reviews
    assert props.dashboard_activity_event_id == "event-1"
    assert props.dashboard_review_placement_id == "placement-1"
    assert props.dashboard_selected_publish_issue_id == "error:invalid-grid"

    assert props.dashboard_comparison_review_action_outcome == %{
             action: :comparison_review_bulk_decision
           }

    assert props.form == widget_form
    assert props.spacecraft == [%{spacecraft_id: "SC-1"}]

    assert props.operational_observables |> Enum.map(& &1.observable_id) == [
             "obs.temp",
             "obs.rate"
           ]

    assert props.filtered_points |> Enum.map(& &1.point_id) == ["HK.temp"]
    assert props.filtered_operational_observables |> Enum.map(& &1.observable_id) == ["obs.temp"]
    assert props.points_empty? == false
    assert props.selected_point.point_id == "HK.temp"
    assert props.selected_points |> Enum.map(& &1.point_id) == ["HK.temp"]
    assert props.selected_operational_observables |> Enum.map(& &1.observable_id) == ["obs.temp"]
    assert props.dashboard_scope_context == %{primary: %{kind: "spacecraft", ids: ["sc-1"]}}
    assert props.error == "invalid widget"
    assert props.mission_id == "mission-1"
    assert props.dashboard_document.dashboard_id == "dashboard-1"
    assert props.dashboard_summary == %{draft_version: 2}
    assert props.dashboard_versions == [%{version: 2}]
    assert props.dashboard_lifecycle_events == [%{event_type: :created}]

    assert props.dashboard_comparison_review_queue == %{
             count: 1,
             requests: [%{event_id: "review-1"}]
           }

    assert props.dashboard_source_action_events == [
             %{source_health_event_id: "source-health-event-1"}
           ]

    assert props.dashboard_recent_invalidations == [%{id: "invalidation-1"}]
    assert props.dashboard_publish_readiness.status == "blocked"
    assert props.dashboard_publish_readiness.freshness == freshness()
    assert props.runtime_diagnostics == runtime_diagnostics
    assert props.dashboard_current_path == "/dashboard-path"
    assert props.historical_workflow_request_form == history_form
  end

  test "props prefers assigned recent invalidations over runtime diagnostics" do
    props =
      assigns(%{
        dashboard_recent_invalidations: [%{id: "assigned-invalidation"}]
      })
      |> RenderPanelModel.props(
        %{recent_invalidations: [%{id: "diagnostic-invalidation"}]},
        "/dashboard-path"
      )

    assert props.dashboard_recent_invalidations == [%{id: "assigned-invalidation"}]
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: %Document{dashboard_id: "dashboard-1"},
        panel: nil,
        dashboard_activity_filter: nil,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: nil,
        points: [],
        operational_observables: [],
        selected_point_id: nil,
        selected_point_ids: [],
        dashboard_scope_context: nil,
        widget_error: nil,
        widget_form: nil,
        historical_workflow_request_form: nil,
        spacecraft: [],
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: empty_review_queue(),
        dashboard_source_action_events: [],
        dashboard_publish_validation: nil,
        dashboard_publish_validation_freshness: nil
      },
      overrides
    )
  end

  defp freshness do
    %{state: "current", evaluated_at: "2026-06-27T12:00:00Z"}
  end

  defp empty_review_queue do
    ComparisonReviewQueue.open_summary([])
  end
end
