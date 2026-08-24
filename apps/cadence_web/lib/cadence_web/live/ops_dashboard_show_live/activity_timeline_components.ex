defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityEventSummary
  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineShellComponents
  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel

  alias Cadence.Dashboards.ComparisonReviewQueue

  attr(:dashboard_document, :any, required: true)
  attr(:dashboard_lifecycle_events, :list, required: true)
  attr(:dashboard_comparison_review_queue, :map, default: nil)
  attr(:dashboard_source_action_events, :list, default: [])
  attr(:dashboard_recent_invalidations, :list, default: [])
  attr(:dashboard_activity_filter, :atom, default: nil)
  attr(:dashboard_activity_event_id, :string, default: nil)
  attr(:dashboard_review_placement_id, :string, default: nil)
  attr(:dashboard_readiness_return_intent, :string, default: nil)
  attr(:dashboard_comparison_review_action_outcome, :map, default: nil)
  attr(:dashboard_current_path, :string, required: true)

  def activity_timeline(assigns) do
    activity =
      dashboard_activity_view_model(
        assigns.dashboard_lifecycle_events,
        assigns.dashboard_comparison_review_queue,
        assigns.dashboard_activity_filter,
        assigns.dashboard_review_placement_id
      )

    selected_activity_event =
      ActivityEventSummary.build(
        assigns.dashboard_lifecycle_events,
        assigns.dashboard_activity_event_id,
        activity.visible_events,
        activity,
        assigns.dashboard_recent_invalidations,
        assigns.dashboard_source_action_events
      )

    activity_rows =
      ActivityEventSummary.rows(
        activity.visible_events,
        assigns.dashboard_activity_event_id,
        assigns.dashboard_recent_invalidations
      )

    assigns
    |> assign(:activity, activity)
    |> assign(:activity_rows, activity_rows)
    |> assign(:selected_activity_event, selected_activity_event)
    |> ActivityTimelineShellComponents.activity_timeline_shell()
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
