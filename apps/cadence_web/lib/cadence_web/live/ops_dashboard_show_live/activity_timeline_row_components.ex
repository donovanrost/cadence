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
    presentation =
      presentation(
        assigns.row,
        assigns.activity,
        assigns.dashboard_lifecycle_events,
        assigns.dashboard_review_placement_id,
        assigns.dashboard_current_path
      )

    assigns =
      assigns
      |> assign(:component_id, component_id(assigns.row))
      |> assign(:presentation, presentation)

    ~H"""
    <.vue
      id={@component_id}
      v-component="ActivityTimelineRow"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(
        row,
        activity,
        dashboard_lifecycle_events,
        dashboard_review_placement_id,
        dashboard_current_path
      ) do
    event_id = rendered_body(row.event_id)

    request_row =
      comparison_review_request_row(
        row.event,
        dashboard_lifecycle_events,
        dashboard_review_placement_id
      )

    resolution_row = comparison_review_resolution_row(row.event)

    %{
      root: %{
        id: "dashboard-activity-#{event_id}",
        class: row.class,
        attrs:
          raw_attributes(%{
            "data-lifecycle-event-type" => row.event_type,
            "data-lifecycle-source-version" => row.source_version_text,
            "data-lifecycle-reverted-version" => row.reverted_version_text,
            "data-dashboard-activity-runtime-impact-state" => row.runtime_impact.state,
            "data-dashboard-activity-runtime-impact-invalidation" =>
              row.runtime_impact.invalidation_id,
            "data-dashboard-activity-runtime-impact-context" => row.runtime_impact.context_match,
            "data-dashboard-activity-runtime-impact-refresh" =>
              row.runtime_impact.refresh_allowed,
            "data-dashboard-activity-selected" => row.selected_text,
            "data-dashboard-comparison-review-work-queue-item" =>
              comparison_review_work_queue_item_id(row.event, activity)
          })
      },
      header: %{
        class: "flex flex-wrap items-center gap-1.5",
        title: %{class: "text-sm font-semibold", text: rendered_body(row.title)},
        version: %{class: "badge badge-xs badge-outline", text: rendered_body(row.version_text)},
        selected_badge: %{
          visible: row.selected?,
          class: "badge badge-info badge-xs",
          attrs: raw_attributes(%{"data-dashboard-activity-selected-badge" => row.selected?}),
          text: "Selected"
        },
        readiness_badge: readiness_badge_presentation(row.readiness_comparison),
        remediation_badge: %{
          visible: row.remediation_count != 0,
          class: "badge badge-info badge-outline badge-xs",
          attrs:
            raw_attributes(%{
              "data-dashboard-activity-remediation-count" => row.remediation_count_text
            }),
          text: "#{rendered_body(row.remediation_count_text)} remediation"
        },
        remediation_actions:
          row.remediation_actions
          |> Enum.with_index()
          |> Enum.map(fn {action, order} ->
            %{
              key: "#{event_id}-remediation-#{order}",
              order: order,
              class: "badge badge-ghost badge-xs",
              attrs:
                raw_attributes(%{
                  "data-dashboard-activity-remediation-action" => action.label,
                  "data-dashboard-activity-remediation-target" => action.target
                }),
              text: rendered_body(action.label)
            }
          end)
      },
      fields: %{
        class: "mt-2 grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1 text-xs",
        rows:
          row.fields
          |> Enum.with_index()
          |> Enum.map(fn {field, order} ->
            %{
              key: "#{event_id}-field-#{order}",
              order: order,
              label: %{class: "hud-label", text: rendered_body(field.label)},
              value: %{
                class: field.class,
                attrs: raw_attributes(%{"data-activity-field" => field.label}),
                text: rendered_body(field.value)
              }
            }
          end)
      },
      actions: %{
        class: "mt-2 flex flex-wrap gap-1",
        select: %{
          id: "dashboard-activity-select-#{event_id}",
          type: "button",
          class: "btn btn-ghost btn-xs",
          attrs:
            raw_attributes(%{
              "phx-click" => "select_activity_event",
              "phx-value-event-id" => row.event_id,
              "data-dashboard-activity-select" => row.event_id
            }),
          icon: %{name: "hero-bookmark-square", class: "h-3.5 w-3.5"},
          text: "Select"
        },
        copy_host: %{
          id: "dashboard-activity-link-copy-#{event_id}-component",
          class: "contents",
          attrs: raw_attributes(%{"data-name" => "ClipboardButton"})
        },
        copy_props: %{
          button_id: "dashboard-activity-link-copy-#{event_id}",
          clipboard_text:
            ActivityNavigation.link(dashboard_current_path, activity.mode, row.event),
          button_class: "btn btn-ghost btn-xs",
          icon: "hero-link",
          icon_class: "h-3.5 w-3.5",
          label: "Copy link",
          data_attrs: raw_attributes(%{"data-dashboard-activity-link-copy" => row.event_id})
        }
      },
      comparison_review: %{
        request:
          child_presentation(
            "ComparisonReviewActivityDetails",
            ComparisonReviewActivity.component_id("request", request_row),
            ComparisonReviewActivity.request_presentation(request_row)
          ),
        resolution:
          child_presentation(
            "ComparisonReviewActivityDetails",
            ComparisonReviewActivity.component_id("resolution", resolution_row),
            ComparisonReviewActivity.resolution_presentation(resolution_row)
          )
      },
      health_snapshot:
        child_presentation(
          "HealthSnapshotActivity",
          HealthSnapshotActivityComponents.component_id(row.event),
          HealthSnapshotActivityComponents.presentation(row.event)
        )
    }
  end

  def component_id(%{event_id: event_id}) do
    "dashboard-activity-row-#{rendered_body(event_id)}-component"
  end

  defp child_presentation(_component, _id, nil), do: nil

  defp child_presentation(component, id, presentation) do
    %{
      id: id,
      class: "contents",
      attrs: raw_attributes(%{"data-name" => component}),
      presentation: presentation
    }
  end

  defp readiness_badge_presentation(nil), do: nil

  defp readiness_badge_presentation(readiness_comparison) do
    %{
      class: ["badge badge-xs", readiness_comparison_badge_class(readiness_comparison)],
      attrs:
        raw_attributes(%{
          "data-dashboard-activity-readiness-trend" => readiness_comparison.state,
          "data-dashboard-activity-readiness-previous" => readiness_comparison.previous_event_id
        }),
      text: rendered_body(readiness_comparison.label)
    }
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

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_body(value))
    end)
  end

  defp rendered_body(nil), do: ""
  defp rendered_body(value), do: to_string(value)
end
