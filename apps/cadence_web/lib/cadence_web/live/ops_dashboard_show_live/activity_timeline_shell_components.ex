defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineShellComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineRowComponents
  alias CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.SelectedActivityComponents

  attr(:activity, :map, required: true)
  attr(:activity_rows, :list, required: true)
  attr(:selected_activity_event, :map, required: true)
  attr(:dashboard_document, :any, required: true)
  attr(:dashboard_lifecycle_events, :list, required: true)
  attr(:dashboard_activity_event_id, :string, default: nil)
  attr(:dashboard_review_placement_id, :string, default: nil)
  attr(:dashboard_readiness_return_intent, :string, default: nil)
  attr(:dashboard_comparison_review_action_outcome, :map, default: nil)
  attr(:dashboard_current_path, :string, required: true)

  def activity_timeline_shell(assigns) do
    action_outcome =
      DataLinkActionOutcomePresentation.for_action(
        assigns.dashboard_comparison_review_action_outcome,
        :comparison_review_bulk_decision
      )

    assigns =
      assigns
      |> assign(:dashboard_comparison_review_action, action_outcome)
      |> assign(
        :dashboard_comparison_review_action_attrs,
        DataLinkActionOutcomePresentation.stable_attrs(
          action_outcome,
          "data-dashboard-comparison-review-action",
          aliases: %{"source_request_event_id" => "source-request-id"}
        )
      )
      |> assign(
        :dashboard_comparison_review_action_rows,
        comparison_review_action_rows(action_outcome)
      )
      |> assign(:dashboard_activity_controls, activity_controls_dto(assigns.activity))

    ~H"""
    <section
      id="dashboard-activity-section"
      class="space-y-2"
      data-dashboard-activity-mode={@activity.mode}
      data-dashboard-activity-filter={@activity.filter_value}
      data-dashboard-activity-event={@dashboard_activity_event_id}
      data-dashboard-review-selected-placement={@dashboard_review_placement_id}
      data-dashboard-comparison-review-open-count={@activity.open_summary.count_text}
      data-dashboard-comparison-review-open-requests={@activity.open_summary.request_ids_attr}
      data-dashboard-comparison-review-open-placements={@activity.open_summary.placements_attr}
      data-dashboard-comparison-review-work-queue={comparison_review_work_queue?(@activity)}
      data-dashboard-comparison-review-work-queue-count={length(@activity.open_review_queue)}
      data-dashboard-comparison-review-queue-state={@activity.queue_state_value}
    >
      <.vue
        id="dashboard-activity-controls-component"
        v-component="DashboardActivityControls"
        presentation={@dashboard_activity_controls}
        v-ssr={false}
        class="contents"
      />
      <SelectedActivityComponents.selected_activity_event_summary
        summary={@selected_activity_event}
        dashboard_document={@dashboard_document}
        dashboard_current_path={@dashboard_current_path}
        readiness_return_intent={@dashboard_readiness_return_intent}
      />

      <div
        :if={@dashboard_comparison_review_action}
        id="dashboard-comparison-review-action-outcome"
        class="space-y-2 border border-base-300/70 bg-base-100/40 p-2"
        {@dashboard_comparison_review_action_attrs}
      >
        <div class="flex items-center justify-between gap-3">
          <div class="min-w-0">
            <h4 class="hud-label">Comparison Review Action</h4>
            <p class="truncate text-sm text-base-content/80">
              {@dashboard_comparison_review_action.message}
            </p>
          </div>
          <span
            class={[
              "badge badge-xs",
              comparison_review_action_badge_class(@dashboard_comparison_review_action.status)
            ]}
            data-dashboard-comparison-review-action-status-label={
              comparison_review_action_status_label(@dashboard_comparison_review_action.status)
            }
          >
            {comparison_review_action_status_label(@dashboard_comparison_review_action.status)}
          </span>
        </div>
        <dl
          :if={@dashboard_comparison_review_action_rows != []}
          class="grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs"
        >
          <%= for row <- @dashboard_comparison_review_action_rows do %>
            <dt class="text-base-content/60">{row.label}</dt>
            <dd
              class="break-all font-mono text-base-content/70"
              data-dashboard-comparison-review-action-field={row.label}
            >
              {row.value}
            </dd>
          <% end %>
        </dl>
      </div>
      <ol
        id="dashboard-activity-list"
        class="space-y-2"
        data-dashboard-comparison-review-work-queue-count={length(@activity.open_review_queue)}
      >
        <ActivityTimelineRowComponents.activity_row
          :for={row <- @activity_rows}
          row={row}
          activity={@activity}
          dashboard_lifecycle_events={@dashboard_lifecycle_events}
          dashboard_review_placement_id={@dashboard_review_placement_id}
          dashboard_current_path={@dashboard_current_path}
        />
      </ol>

      <p
        :if={comparison_review_queue_message?(@activity)}
        class="text-sm text-base-content/60"
        data-dashboard-comparison-review-queue-state-message={@activity.queue_state_value}
      >
        {@activity.queue_message}
      </p>

      <p
        :if={@dashboard_lifecycle_events == []}
        class="text-sm text-base-content/60"
        data-dashboard-activity-empty="no_lifecycle"
      >
        No lifecycle activity.
      </p>
      <p
        :if={
          @dashboard_lifecycle_events != [] and
            @activity.visible_events == [] and
            @activity.mode != :open_comparison_reviews
        }
        class="text-sm text-base-content/60"
        data-dashboard-activity-empty-filter
      >
        No activity matches the current filter.
      </p>
    </section>
    """
  end

  defp activity_controls_dto(activity) do
    filtered? = activity.mode != :all

    %{
      header: %{
        class: "flex items-center justify-between",
        leading_class: "flex items-center gap-2",
        items: [
          %{
            key: "title",
            order: 0,
            tag: "h3",
            visible: true,
            id: nil,
            type: nil,
            class: "hud-label",
            attrs: raw_attributes(%{"data-dashboard-activity-title" => activity.mode}),
            text: rendered_body(activity.title)
          },
          %{
            key: "open-review-badge",
            order: 1,
            tag: "span",
            visible: activity.open_summary.count != 0,
            id: nil,
            type: nil,
            class: "badge badge-warning badge-xs",
            attrs: raw_attributes(%{"data-dashboard-comparison-review-open-badge" => true}),
            text: "#{rendered_body(activity.open_summary.count_text)} open reviews"
          },
          %{
            key: "active-filter-badge",
            order: 2,
            tag: "span",
            visible: filtered?,
            id: nil,
            type: nil,
            class: "badge badge-info badge-outline badge-xs",
            attrs:
              raw_attributes(%{
                "data-dashboard-activity-filter-badge" => activity.filter_value
              }),
            text: rendered_body(activity.filter_label)
          },
          %{
            key: "clear-filter",
            order: 3,
            tag: "button",
            visible: filtered?,
            id: "dashboard-activity-clear-filter",
            type: "button",
            class: "btn btn-ghost btn-xs",
            attrs:
              raw_attributes(%{
                "phx-click" => "open_versions",
                "data-dashboard-activity-clear-filter" => activity.filter_value
              }),
            text: "Show all"
          }
        ],
        count: %{
          class: "font-mono text-xs text-base-content/50",
          text: "#{length(activity.visible_events)} / #{activity.total_count}"
        }
      },
      controls: %{
        id: "dashboard-activity-filter-controls",
        class: "flex flex-wrap gap-1",
        attrs: raw_attributes(%{"data-dashboard-activity-filter-controls" => true}),
        filters:
          activity.mode
          |> activity_filter_options()
          |> Enum.with_index()
          |> Enum.map(fn {filter, order} ->
            %{
              key: filter.id,
              order: order,
              tag: "button",
              id: "dashboard-activity-filter-#{filter.id}",
              type: "button",
              class: activity_filter_button_class(filter.selected?),
              attrs:
                raw_attributes(%{
                  "phx-click" => "set_activity_filter",
                  "phx-value-filter" => filter.value,
                  "data-dashboard-activity-filter-option" => filter.value,
                  "data-dashboard-activity-filter-selected" =>
                    activity_filter_selected_text(filter.selected?)
                }),
              text: rendered_body(filter.label)
            }
          end)
      }
    }
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

  defp activity_filter_options(selected_mode) do
    [
      %{id: "all", value: "", label: "All", mode: :all},
      %{
        id: "version-changes",
        value: "version_changes",
        label: "Versions",
        mode: :version_changes
      },
      %{id: "reviews", value: "comparison_reviews", label: "Reviews", mode: :comparison_reviews},
      %{
        id: "open-reviews",
        value: "open_comparison_reviews",
        label: "Open reviews",
        mode: :open_comparison_reviews
      },
      %{
        id: "health-snapshots",
        value: "health_snapshots",
        label: "Health",
        mode: :health_snapshots
      },
      %{
        id: "publish-readiness",
        value: "publish_readiness",
        label: "Readiness",
        mode: :publish_readiness
      }
    ]
    |> Enum.map(&Map.put(&1, :selected?, &1.mode == selected_mode))
  end

  defp activity_filter_button_class(true), do: "btn btn-primary btn-xs"
  defp activity_filter_button_class(false), do: "btn btn-ghost btn-xs"

  defp activity_filter_selected_text(true), do: "true"
  defp activity_filter_selected_text(false), do: "false"

  defp comparison_review_work_queue?(%{mode: :open_comparison_reviews}), do: "true"
  defp comparison_review_work_queue?(_activity), do: "false"

  defp comparison_review_queue_message?(%{
         mode: :open_comparison_reviews,
         queue_message: message
       })
       when is_binary(message),
       do: true

  defp comparison_review_queue_message?(_activity), do: false

  defp comparison_review_action_rows(nil), do: []

  defp comparison_review_action_rows(%{metadata: metadata}) when is_map(metadata) do
    [
      {"Requested", Map.get(metadata, "requested")},
      {"Applied", Map.get(metadata, "applied")},
      {"Failed", Map.get(metadata, "failed")},
      {"Scope", Map.get(metadata, "scope_kind")},
      {"Scope IDs", Map.get(metadata, "scope_ids")},
      {"Contacts", Map.get(metadata, "contact_ids")},
      {"Resources", Map.get(metadata, "resource_ids")},
      {"Transports", Map.get(metadata, "transport_ids")},
      {"Source endpoints", Map.get(metadata, "source_endpoint_ids")},
      {"Ground stations", Map.get(metadata, "ground_station_ids")},
      {"Scope links", Map.get(metadata, "scope_link_ids")},
      {"Workflow", Map.get(metadata, "workflow_id")},
      {"Request", Map.get(metadata, "source_request_event_id")},
      {"Results", Map.get(metadata, "result_event_ids")},
      {"Reason", Map.get(metadata, "decision_reason")}
    ]
    |> Enum.reject(fn {_label, value} -> is_nil(value) or value == "" end)
    |> Enum.map(fn {label, value} -> %{label: label, value: value} end)
  end

  defp comparison_review_action_rows(_action), do: []

  defp comparison_review_action_badge_class("ok"), do: "badge-success"
  defp comparison_review_action_badge_class("degraded"), do: "badge-warning"
  defp comparison_review_action_badge_class("blocked"), do: "badge-warning"
  defp comparison_review_action_badge_class("error"), do: "badge-error"
  defp comparison_review_action_badge_class(_status), do: "badge-ghost"

  defp comparison_review_action_status_label("ok"), do: "Applied"
  defp comparison_review_action_status_label("degraded"), do: "Partial"
  defp comparison_review_action_status_label("blocked"), do: "Blocked"
  defp comparison_review_action_status_label("error"), do: "Failed"

  defp comparison_review_action_status_label(status) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp comparison_review_action_status_label(_status), do: "Unknown"
end
