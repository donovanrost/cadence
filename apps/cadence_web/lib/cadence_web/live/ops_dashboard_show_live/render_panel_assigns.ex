defmodule CadenceWeb.OpsDashboardShowLive.RenderPanelAssigns do
  @moduledoc false

  alias Cadence.Dashboards.ComparisonReviewQueue

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec panel_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def panel_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)
    points = Map.get(assigns, :points, [])
    operational_observables = Map.get(assigns, :operational_observables, [])

    %{
      panel: Map.get(assigns, :panel),
      dashboard_render_items: Map.get(assigns, :dashboard_render_items, []),
      frames_by_placement: Map.get(assigns, :dashboard_engine_frames_by_placement, %{}),
      dashboard_activity_filter: Map.get(assigns, :dashboard_activity_filter),
      dashboard_activity_event_id: Map.get(assigns, :dashboard_activity_event_id),
      dashboard_review_placement_id: Map.get(assigns, :dashboard_review_placement_id),
      dashboard_selected_publish_issue_id: Map.get(assigns, :dashboard_selected_publish_issue_id),
      dashboard_comparison_review_action_outcome:
        Map.get(assigns, :dashboard_comparison_review_action_outcome),
      widget_form: Map.get(assigns, :widget_form),
      widget_binding_preview: Map.get(assigns, :widget_binding_preview),
      section_form: Map.get(assigns, :section_form),
      section_error: Map.get(assigns, :section_error),
      spacecraft: Map.get(assigns, :spacecraft, []),
      operational_observables: operational_observables,
      points: points,
      points_empty?: points == [],
      selected_point_id: Map.get(assigns, :selected_point_id),
      selected_point_ids: Map.get(assigns, :selected_point_ids, []),
      dashboard_scope_context: Map.get(assigns, :dashboard_scope_context),
      dashboard_editor_focus: Map.get(assigns, :dashboard_editor_focus),
      widget_error: Map.get(assigns, :widget_error),
      mission_id: mission_id(Map.get(assigns, :current_mission)),
      dashboard_document: Map.get(assigns, :dashboard_document),
      dashboard_summary: Map.get(assigns, :dashboard_summary),
      dashboard_versions: Map.get(assigns, :dashboard_versions, []),
      dashboard_lifecycle_events: Map.get(assigns, :dashboard_lifecycle_events, []),
      dashboard_comparison_review_queue: comparison_review_queue(assigns),
      dashboard_source_action_events: Map.get(assigns, :dashboard_source_action_events, []),
      dashboard_recent_invalidations: Map.get(assigns, :dashboard_recent_invalidations, []),
      dashboard_publish_validation: Map.get(assigns, :dashboard_publish_validation),
      dashboard_publish_validation_freshness:
        Map.get(assigns, :dashboard_publish_validation_freshness),
      historical_workflow_request_form: Map.get(assigns, :historical_workflow_request_form),
      data_link_action_outcome: Map.get(assigns, :data_link_action_outcome)
    }
  end

  defp mission_id(current_mission) when is_map(current_mission) do
    Map.get(current_mission, :mission_id)
  end

  defp mission_id(_current_mission), do: nil

  defp comparison_review_queue(%{
         dashboard_comparison_review_queue: %{count: count, requests: requests} = summary
       })
       when is_integer(count) and is_list(requests),
       do: summary

  defp comparison_review_queue(_assigns), do: ComparisonReviewQueue.open_summary([])
end
