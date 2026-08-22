defmodule CadenceWeb.OpsDashboardShowLive.RenderPanelObservableFilterTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document, OperationalObservable}
  alias CadenceWeb.OpsDashboardShowLive.RenderPanelModel

  test "props filters operational observables by active widget type" do
    observables = OperationalObservable.list()

    value_tile_ids =
      operational_observable_ids(%{"type" => "value_tile"}, observables)

    assert "comms.transport.downlink_bitrate" in value_tile_ids
    refute "contacts.phase" in value_tile_ids
    refute "comms.transport.connection_state" in value_tile_ids

    for widget_type <- ["status_matrix", "data_table"] do
      ids = operational_observable_ids(%{"type" => widget_type}, observables)

      assert "contacts.phase" in ids
      assert "comms.transport.connection_state" in ids
      assert "comms.transport.downlink_bitrate" in ids
    end

    state_timeline_ids =
      operational_observable_ids(%{"type" => "state_timeline"}, observables)

    assert "contacts.phase" in state_timeline_ids
    assert "comms.transport.connection_state" in state_timeline_ids
    refute "comms.transport.downlink_bitrate" in state_timeline_ids
  end

  defp operational_observable_ids(form_params, observables) do
    %{filtered_operational_observables: filtered_observables} =
      %{widget_form: to_form(form_params, as: :widget), operational_observables: observables}
      |> assigns()
      |> RenderPanelModel.props(%{}, "/dashboard-path")

    Enum.map(filtered_observables, & &1.observable_id)
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
