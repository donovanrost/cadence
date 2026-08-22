defmodule CadenceWeb.OpsDashboardShowLive.SelectedActivityComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.SelectedActivityActionComponents

  attr :summary, :map, required: true
  attr :dashboard_document, :any, required: true
  attr :dashboard_current_path, :string, required: true
  attr :readiness_return_intent, :string, default: nil

  def selected_activity_event_summary(assigns) do
    ~H"""
    <section
      :if={@summary.render?}
      id="dashboard-selected-activity-event"
      class={[
        "border border-info/40 bg-info/10 px-2 py-2 text-xs",
        @summary.visibility_class
      ]}
      data-dashboard-selected-activity-event={@summary.event_id}
      data-dashboard-selected-activity-event-found={@summary.found_text}
      data-dashboard-selected-activity-event-visible={@summary.visible_text}
      data-dashboard-selected-activity-event-filter={@summary.filter_value}
      data-dashboard-selected-activity-event-type={@summary.event_type_text}
      data-dashboard-selected-activity-runtime-impact-state={@summary.runtime_impact.state}
      data-dashboard-selected-activity-runtime-impact-invalidation={
        @summary.runtime_impact.invalidation_id
      }
      data-dashboard-selected-activity-runtime-impact-context={@summary.runtime_impact.context_match}
      data-dashboard-selected-activity-runtime-impact-refresh={
        @summary.runtime_impact.refresh_allowed
      }
    >
      <div class="flex flex-wrap items-center gap-1.5">
        <span class="font-semibold" data-dashboard-selected-activity-title>
          {@summary.title}
        </span>
        <span
          :if={@summary.found?}
          class="badge badge-xs badge-outline"
          data-dashboard-selected-activity-version
        >
          {@summary.version_text}
        </span>
        <span
          :if={@summary.filter_state == :hidden}
          class="badge badge-warning badge-xs"
          data-dashboard-selected-activity-filter-state="hidden"
        >
          Hidden by filter
        </span>
        <span
          :if={@summary.filter_state == :missing}
          class="badge badge-error badge-xs"
          data-dashboard-selected-activity-filter-state="missing"
        >
          Event unavailable
        </span>
        <span
          :if={@summary.readiness_comparison}
          class={["badge badge-xs", readiness_comparison_badge_class(@summary.readiness_comparison)]}
          data-dashboard-selected-activity-readiness-trend={@summary.readiness_comparison.state}
          data-dashboard-selected-activity-readiness-previous={
            @summary.readiness_comparison.previous_event_id
          }
        >
          {@summary.readiness_comparison.label}
        </span>
        <button
          :if={selected_activity_readiness_check?(@summary)}
          id="dashboard-selected-activity-refresh-readiness"
          type="button"
          phx-click="refresh_publish_readiness"
          class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus"
          data-dashboard-selected-activity-refresh-readiness={@summary.event_id}
          data-dashboard-selected-activity-refresh-readiness-state={
            @summary.readiness_comparison && @summary.readiness_comparison.state
          }
        >
          <.icon name="hero-arrow-path" class="h-3 w-3" /> Re-check
        </button>
      </div>

      <SelectedActivityActionComponents.readiness_return_prompt
        summary={@summary}
        readiness_return_intent={@readiness_return_intent}
      />
      <SelectedActivityActionComponents.source_actions summary={@summary} />
      <SelectedActivityActionComponents.recovery_banner
        summary={@summary}
        dashboard_current_path={@dashboard_current_path}
      />

      <dl :if={@summary.fields != []} class="mt-2 grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1">
        <%= for field <- @summary.fields do %>
          <dt class="hud-label">{field.label}</dt>
          <dd data-dashboard-selected-activity-field={field.label} class={field.class}>
            {field.value}
          </dd>
        <% end %>
      </dl>

      <SelectedActivityActionComponents.remediation_actions
        summary={@summary}
        dashboard_document={@dashboard_document}
      />
    </section>
    """
  end

  defp selected_activity_readiness_check?(%{
         found?: true,
         event_type_text: "publish_readiness_checked"
       }),
       do: true

  defp selected_activity_readiness_check?(_summary), do: false

  defp readiness_comparison_badge_class(%{state: "improved"}), do: "badge-success"
  defp readiness_comparison_badge_class(%{state: "regressed"}), do: "badge-error"
  defp readiness_comparison_badge_class(%{state: "unchanged"}), do: "badge-warning"
  defp readiness_comparison_badge_class(%{state: "first_check"}), do: "badge-outline"
  defp readiness_comparison_badge_class(_comparison), do: "badge-outline"
end
