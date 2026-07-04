defmodule CadenceWeb.OpsDashboardShowLive.SelectedActivityActionComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.VersionActionNavigation

  attr :summary, :map, required: true
  attr :readiness_return_intent, :string, default: nil

  def readiness_return_prompt(assigns) do
    ~H"""
    <div
      :if={selected_activity_readiness_return?(@summary, @readiness_return_intent)}
      id="dashboard-selected-activity-readiness-return"
      class="mt-2 flex flex-wrap items-center gap-2 border-l-2 border-primary/70 pl-2 text-base-content/70"
      data-dashboard-selected-activity-readiness-return={@readiness_return_intent}
      data-dashboard-selected-activity-readiness-return-event={@summary.event_id}
    >
      <p class="min-w-0 flex-1">
        Source evidence changed or was reviewed. Re-check publish readiness before publishing this draft.
      </p>
      <button
        type="button"
        phx-click="refresh_publish_readiness"
        class="inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus"
        data-dashboard-selected-activity-readiness-return-refresh={@summary.event_id}
      >
        <.icon name="hero-arrow-path" class="h-3 w-3" /> Re-check readiness
      </button>
    </div>
    """
  end

  attr :summary, :map, required: true

  def source_actions(assigns) do
    ~H"""
    <div
      :if={selected_activity_source_actions?(@summary)}
      id="dashboard-selected-activity-source-actions"
      class="mt-2 space-y-1 border-l-2 border-success/70 pl-2 text-base-content/70"
      data-dashboard-selected-activity-source-actions={@summary.source_actions.count_text}
      data-dashboard-selected-activity-source-action-latest-kind={@summary.source_actions.latest.kind}
      data-dashboard-selected-activity-source-action-latest-at={@summary.source_actions.latest.occurred_at}
    >
      <p class="font-semibold">{@summary.source_actions.latest.message}</p>
      <div
        :for={source_action <- @summary.source_actions.rows}
        class="flex flex-wrap items-center gap-x-2 gap-y-0.5"
        data-dashboard-selected-activity-source-action={source_action.kind}
        data-dashboard-selected-activity-source-action-at={source_action.occurred_at}
        data-dashboard-selected-activity-source-action-source={source_action.source}
      >
        <span>{source_action.message}</span>
        <span class="font-mono text-base-content/60">{source_action.occurred_at}</span>
        <span :if={source_action.source != ""} class="font-mono text-base-content/60">
          {source_action.source}
        </span>
      </div>
    </div>
    """
  end

  attr :summary, :map, required: true
  attr :dashboard_current_path, :string, required: true

  def recovery_banner(assigns) do
    assigns =
      assign(
        assigns,
        :recovery_href,
        selected_activity_recovery_href(assigns.summary, assigns.dashboard_current_path)
      )

    ~H"""
    <div
      :if={@recovery_href}
      id="dashboard-selected-activity-recovery"
      class="mt-2 flex flex-wrap items-center gap-2 border-l-2 border-warning/70 pl-2 text-base-content/70"
      data-dashboard-selected-activity-recovery={@summary.filter_state_text}
      data-dashboard-selected-activity-recovery-href={@recovery_href}
    >
      <p class="min-w-0 flex-1">
        {selected_activity_recovery_message(@summary)}
      </p>
      <.link
        id="dashboard-selected-activity-recovery-link"
        navigate={@recovery_href}
        class="inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus"
      >
        <.icon name={selected_activity_recovery_icon(@summary)} class="h-3 w-3" />
        {selected_activity_recovery_label(@summary)}
      </.link>
    </div>
    """
  end

  attr :summary, :map, required: true
  attr :dashboard_document, :any, required: true

  def remediation_actions(assigns) do
    ~H"""
    <div :if={@summary.remediation_actions != []} class="mt-3 space-y-2">
      <div class="hud-label">Remediation</div>
      <div
        :for={action <- @summary.remediation_actions}
        class="border-l-2 border-info/70 pl-2"
        data-dashboard-selected-activity-remediation={action.label}
        data-dashboard-selected-activity-remediation-target={action.target}
        data-dashboard-selected-activity-remediation-issue={action[:issue_id] || ""}
      >
        <div class="font-semibold">{action.label}</div>
        <p :if={action.message} class="mt-0.5 text-base-content/70">{action.message}</p>
        <.link
          :if={
            action.target == "data_sources" &&
              selected_activity_action_href(action, @dashboard_document, @summary)
          }
          navigate={selected_activity_action_href(action, @dashboard_document, @summary)}
          class="mt-1 inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus"
          data-dashboard-selected-activity-remediation-link={action.label}
          data-dashboard-selected-activity-remediation-href={
            selected_activity_action_href(action, @dashboard_document, @summary)
          }
        >
          <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
          Open Data Sources
        </.link>
        <.link
          :if={
            action.target == "dashboard_editor" &&
              selected_activity_action_href(action, @dashboard_document, @summary)
          }
          patch={selected_activity_action_href(action, @dashboard_document, @summary)}
          class="mt-1 inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus"
          data-dashboard-selected-activity-remediation-link={action.label}
          data-dashboard-selected-activity-remediation-href={
            selected_activity_action_href(action, @dashboard_document, @summary)
          }
        >
          <.icon name="hero-pencil-square" class="h-3 w-3" />
          Open Widget Editor
        </.link>
      </div>
    </div>
    """
  end

  defp selected_activity_action_href(action, dashboard_document, summary) do
    VersionActionNavigation.selected_activity_action_href(
      action,
      dashboard_document,
      summary
    )
  end

  defp selected_activity_recovery_href(%{filter_state: :hidden, event_id: event_id}, current_path)
       when is_binary(event_id) and event_id != "" and is_binary(current_path) do
    ActivityNavigation.link(current_path, :all, event_id)
  end

  defp selected_activity_recovery_href(%{filter_state: :missing}, current_path)
       when is_binary(current_path) do
    ActivityNavigation.link(current_path, :all, nil)
  end

  defp selected_activity_recovery_href(_summary, _current_path), do: nil

  defp selected_activity_recovery_message(%{filter_state: :hidden}),
    do: "This event exists but is hidden by the current activity filter."

  defp selected_activity_recovery_message(%{filter_state: :missing}),
    do: "This event is no longer available in the dashboard activity log."

  defp selected_activity_recovery_message(_summary), do: nil

  defp selected_activity_recovery_label(%{filter_state: :hidden}), do: "Show all activity"
  defp selected_activity_recovery_label(%{filter_state: :missing}), do: "Clear selection"
  defp selected_activity_recovery_label(_summary), do: nil

  defp selected_activity_recovery_icon(%{filter_state: :hidden}), do: "hero-list-bullet"
  defp selected_activity_recovery_icon(%{filter_state: :missing}), do: "hero-x-mark"
  defp selected_activity_recovery_icon(_summary), do: "hero-arrow-top-right-on-square"

  defp selected_activity_readiness_return?(
         %{found?: true, event_type_text: "publish_readiness_checked"},
         "source_return"
       ),
       do: true

  defp selected_activity_readiness_return?(_summary, _intent), do: false

  defp selected_activity_source_actions?(%{source_actions: %{present?: true}}), do: true
  defp selected_activity_source_actions?(_summary), do: false
end
