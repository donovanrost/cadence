defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineRowComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivity
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivityRow
  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityComponents

  alias Cadence.Dashboards.LifecycleEvent

  attr :row, :map, required: true
  attr :activity, :map, required: true
  attr :dashboard_lifecycle_events, :list, required: true
  attr :dashboard_review_placement_id, :string, default: nil
  attr :dashboard_current_path, :string, required: true

  def activity_row(assigns) do
    ~H"""
    <li
            id={"dashboard-activity-#{@row.event_id}"}
            data-lifecycle-event-type={@row.event_type}
            data-lifecycle-source-version={@row.source_version_text}
            data-lifecycle-reverted-version={@row.reverted_version_text}
            data-dashboard-activity-runtime-impact-state={@row.runtime_impact.state}
            data-dashboard-activity-runtime-impact-invalidation={@row.runtime_impact.invalidation_id}
            data-dashboard-activity-runtime-impact-context={@row.runtime_impact.context_match}
            data-dashboard-activity-runtime-impact-refresh={@row.runtime_impact.refresh_allowed}
            data-dashboard-activity-selected={@row.selected_text}
            data-dashboard-comparison-review-work-queue-item={
              comparison_review_work_queue_item_id(@row.event, @activity)
            }
            class={@row.class}
          >
            <div class="flex flex-wrap items-center gap-1.5">
              <span class="text-sm font-semibold">{@row.title}</span>
              <span class="badge badge-xs badge-outline">{@row.version_text}</span>
              <span
                :if={@row.selected?}
                class="badge badge-info badge-xs"
                data-dashboard-activity-selected-badge
              >
                Selected
              </span>
              <span
                :if={@row.readiness_comparison}
                class={["badge badge-xs", readiness_comparison_badge_class(@row.readiness_comparison)]}
                data-dashboard-activity-readiness-trend={@row.readiness_comparison.state}
                data-dashboard-activity-readiness-previous={@row.readiness_comparison.previous_event_id}
              >
                {@row.readiness_comparison.label}
              </span>
              <span
                :if={@row.remediation_count != 0}
                class="badge badge-info badge-outline badge-xs"
                data-dashboard-activity-remediation-count={@row.remediation_count_text}
              >
                {@row.remediation_count_text} remediation
              </span>
              <span
                :for={action <- @row.remediation_actions}
                class="badge badge-ghost badge-xs"
                data-dashboard-activity-remediation-action={action.label}
                data-dashboard-activity-remediation-target={action.target}
              >
                {action.label}
              </span>
            </div>
            <dl class="mt-2 grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1 text-xs">
              <%= for field <- @row.fields do %>
                <dt class="hud-label">{field.label}</dt>
                <dd data-activity-field={field.label} class={field.class}>
                  {field.value}
                </dd>
              <% end %>
            </dl>
            <div class="mt-2 flex flex-wrap gap-1">
              <button
                id={"dashboard-activity-select-#{@row.event_id}"}
                type="button"
                class="btn btn-ghost btn-xs"
                phx-click="select_activity_event"
                phx-value-event-id={@row.event_id}
                data-dashboard-activity-select={@row.event_id}
              >
                <.icon name="hero-bookmark-square" class="h-3.5 w-3.5" /> Select
              </button>
              <button
                id={"dashboard-activity-link-copy-#{@row.event_id}"}
                type="button"
                class="btn btn-ghost btn-xs"
                phx-hook="ClipboardButton"
                data-clipboard-text={
                  ActivityNavigation.link(@dashboard_current_path, @activity.mode, @row.event)
                }
                data-dashboard-activity-link-copy={@row.event_id}
              >
                <.icon name="hero-link" class="h-3.5 w-3.5" /> Copy link
              </button>
            </div>
            <ComparisonReviewActivity.request_details
              row={
                comparison_review_request_row(
                  @row.event,
                  @dashboard_lifecycle_events,
                  @dashboard_review_placement_id
                )
              }
            />
            <ComparisonReviewActivity.resolution_details row={comparison_review_resolution_row(@row.event)} />
            <HealthSnapshotActivityComponents.event_details event={@row.event} />
    </li>
    """
  end

  defp readiness_comparison_badge_class(%{state: "improved"}), do: "badge-success"
  defp readiness_comparison_badge_class(%{state: "regressed"}), do: "badge-error"
  defp readiness_comparison_badge_class(%{state: "unchanged"}), do: "badge-warning"
  defp readiness_comparison_badge_class(%{state: "first_check"}), do: "badge-outline"
  defp readiness_comparison_badge_class(_comparison), do: "badge-outline"

  defp comparison_review_work_queue_item_id(
         %LifecycleEvent{dashboard_lifecycle_event_id: event_id},
         %{mode: :open_comparison_reviews, open_summary: %{request_ids: request_ids}}
       ) do
    if event_id in request_ids, do: event_id
  end

  defp comparison_review_work_queue_item_id(%LifecycleEvent{}, _activity), do: nil

  defp comparison_review_request_row(event, lifecycle_events, selected_placement_id)
       when is_list(lifecycle_events) do
    ComparisonReviewActivityRow.request(event, lifecycle_events, selected_placement_id)
  end

  defp comparison_review_resolution_row(event) do
    ComparisonReviewActivityRow.resolution(event)
  end
end
