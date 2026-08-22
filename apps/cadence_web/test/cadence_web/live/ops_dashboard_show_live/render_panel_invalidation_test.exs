defmodule CadenceWeb.OpsDashboardShowLive.RenderPanelInvalidationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.RenderPanelModel

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
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([]),
        dashboard_source_action_events: [],
        dashboard_publish_validation: nil,
        dashboard_publish_validation_freshness: nil
      },
      overrides
    )
  end
end
