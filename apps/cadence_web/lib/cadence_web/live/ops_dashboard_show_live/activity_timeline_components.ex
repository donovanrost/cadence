defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityEventSummary
  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineShellComponents
  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel

  alias Cadence.Dashboards.ComparisonReviewQueue

  attr :dashboard_document, :any, required: true
  attr :dashboard_lifecycle_events, :list, required: true
  attr :dashboard_comparison_review_queue, :map, default: nil
  attr :dashboard_source_action_events, :list, default: []
  attr :dashboard_recent_invalidations, :list, default: []
  attr :dashboard_activity_filter, :atom, default: nil
  attr :dashboard_activity_event_id, :string, default: nil
  attr :dashboard_review_placement_id, :string, default: nil
  attr :dashboard_readiness_return_intent, :string, default: nil
  attr :dashboard_comparison_review_action_outcome, :map, default: nil
  attr :dashboard_current_path, :string, required: true

  def activity_timeline(assigns) do
    ~H"""
      <% activity =
        dashboard_activity_view_model(
          @dashboard_lifecycle_events,
          @dashboard_comparison_review_queue,
          @dashboard_activity_filter,
          @dashboard_review_placement_id
        ) %>
      <% selected_activity_event =
        ActivityEventSummary.build(
          @dashboard_lifecycle_events,
          @dashboard_activity_event_id,
          activity.visible_events,
          activity,
          @dashboard_recent_invalidations,
          @dashboard_source_action_events
        ) %>
      <% activity_rows =
        ActivityEventSummary.rows(
          activity.visible_events,
          @dashboard_activity_event_id,
          @dashboard_recent_invalidations
        ) %>
      <ActivityTimelineShellComponents.activity_timeline_shell
        activity={activity}
        activity_rows={activity_rows}
        selected_activity_event={selected_activity_event}
        dashboard_document={@dashboard_document}
        dashboard_lifecycle_events={@dashboard_lifecycle_events}
        dashboard_activity_event_id={@dashboard_activity_event_id}
        dashboard_review_placement_id={@dashboard_review_placement_id}
        dashboard_readiness_return_intent={@dashboard_readiness_return_intent}
        dashboard_comparison_review_action_outcome={@dashboard_comparison_review_action_outcome}
        dashboard_current_path={@dashboard_current_path}
      />
    """
  end

  defp dashboard_activity_view_model(events, open_summary, filter, selected_placement_id)
       when is_list(events) do
    ActivityViewModel.build(events, filter,
      open_summary: comparison_review_queue(open_summary),
      selected_placement_id: selected_placement_id
    )
  end

  defp comparison_review_queue(%{count: count, requests: requests} = open_summary)
       when is_integer(count) and is_list(requests),
       do: open_summary

  defp comparison_review_queue(_open_summary), do: ComparisonReviewQueue.open_summary([])
end
