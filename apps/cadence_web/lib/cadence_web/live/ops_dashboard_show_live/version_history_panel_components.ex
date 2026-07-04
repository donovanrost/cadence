defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineComponents
  alias CadenceWeb.OpsDashboardShowLive.PublishValidationComponents
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPresentation
  alias CadenceWeb.OpsDashboardShowLive.VersionListComponents

  attr :dashboard_document, :any, required: true
  attr :dashboard_summary, :any, required: true
  attr :dashboard_versions, :list, required: true
  attr :dashboard_lifecycle_events, :list, required: true
  attr :dashboard_comparison_review_queue, :map, default: nil
  attr :dashboard_source_action_events, :list, default: []
  attr :dashboard_recent_invalidations, :list, default: []
  attr :dashboard_activity_filter, :atom, default: nil
  attr :dashboard_activity_event_id, :string, default: nil
  attr :dashboard_review_placement_id, :string, default: nil
  attr :dashboard_readiness_return_intent, :string, default: nil
  attr :dashboard_selected_publish_issue_id, :string, default: nil
  attr :dashboard_comparison_review_action_outcome, :map, default: nil
  attr :dashboard_publish_readiness, :map, default: nil
  attr :dashboard_current_path, :string, required: true

  def versions_panel(assigns) do
    assigns =
      assign(
        assigns,
        :version_history,
        VersionHistoryPresentation.build(assigns.dashboard_summary, assigns.dashboard_versions)
      )

    ~H"""
    <div id="dashboard-versions-panel" class="space-y-5">
      <VersionListComponents.version_overview version_history={@version_history} />

      <PublishValidationComponents.publish_validation
        publish_readiness={@dashboard_publish_readiness}
        selected_publish_issue_id={@dashboard_selected_publish_issue_id}
        dashboard_document={@dashboard_document}
        dashboard_current_path={@dashboard_current_path}
      />

      <.publish_impact impact={@version_history.runtime_defaults.publish_impact} />

      <.runtime_defaults_summary summary={@version_history.runtime_defaults} />
    <ActivityTimelineComponents.activity_timeline
    dashboard_document={@dashboard_document}
    dashboard_lifecycle_events={@dashboard_lifecycle_events}
    dashboard_comparison_review_queue={@dashboard_comparison_review_queue}
    dashboard_source_action_events={@dashboard_source_action_events}
    dashboard_recent_invalidations={@dashboard_recent_invalidations}
    dashboard_activity_filter={@dashboard_activity_filter}
    dashboard_activity_event_id={@dashboard_activity_event_id}
    dashboard_review_placement_id={@dashboard_review_placement_id}
    dashboard_readiness_return_intent={@dashboard_readiness_return_intent}
    dashboard_comparison_review_action_outcome={@dashboard_comparison_review_action_outcome}
    dashboard_current_path={@dashboard_current_path}
    />
    </div>
    """
  end

  attr :impact, :map, required: true

  defp publish_impact(assigns) do
    ~H"""
    <section
      :if={@impact.present?}
      id="dashboard-publish-impact"
      data-dashboard-publish-impact-state={@impact.state}
      data-dashboard-publish-impact-severity={@impact.severity}
      data-dashboard-publish-impact-from-version={@impact.from.version_text}
      data-dashboard-publish-impact-to-version={@impact.to.version_text}
      data-dashboard-publish-impact-from-realm={@impact.from.realm}
      data-dashboard-publish-impact-to-realm={@impact.to.realm}
      data-dashboard-publish-impact-from-source-binding={@impact.from.source_binding_attr}
      data-dashboard-publish-impact-to-source-binding={@impact.to.source_binding_attr}
      data-dashboard-publish-impact-from-data-view={@impact.from.data_view}
      data-dashboard-publish-impact-to-data-view={@impact.to.data_view}
      class="space-y-2 border border-base-300/70 bg-base-100/40 p-2"
    >
      <div class="flex items-center justify-between gap-3">
        <h3 class="hud-label">Publish Impact</h3>
        <span
          class={[
            "badge badge-xs",
            publish_impact_badge_class(@impact.severity)
          ]}
          data-dashboard-publish-impact-label={@impact.label}
        >
          {@impact.label}
        </span>
      </div>
      <p class="text-xs text-base-content/70" data-dashboard-publish-impact-message>
        {@impact.message}
      </p>
    </section>
    """
  end

  defp publish_impact_badge_class("warning"), do: "badge-warning"
  defp publish_impact_badge_class("success"), do: "badge-success"
  defp publish_impact_badge_class("info"), do: "badge-info"
  defp publish_impact_badge_class(_severity), do: "badge-ghost"

  attr :summary, :map, required: true

  defp runtime_defaults_summary(assigns) do
    ~H"""
    <section
      :if={@summary.present?}
      id="dashboard-runtime-defaults-summary"
      data-dashboard-runtime-defaults-differ={@summary.differ_text}
      data-dashboard-runtime-defaults-published-version={@summary.published.version_text}
      data-dashboard-runtime-defaults-draft-version={@summary.draft.version_text}
      data-dashboard-runtime-defaults-published-realm={@summary.published.realm}
      data-dashboard-runtime-defaults-draft-realm={@summary.draft.realm}
      data-dashboard-runtime-defaults-published-source-binding={
        @summary.published.source_binding_attr
      }
      data-dashboard-runtime-defaults-draft-source-binding={@summary.draft.source_binding_attr}
      data-dashboard-runtime-defaults-published-data-source={@summary.published.data_source_attr}
      data-dashboard-runtime-defaults-draft-data-source={@summary.draft.data_source_attr}
      data-dashboard-runtime-defaults-published-data-view={@summary.published.data_view}
      data-dashboard-runtime-defaults-draft-data-view={@summary.draft.data_view}
      class="space-y-2 border border-base-300/70 bg-base-100/40 p-2"
    >
      <div class="flex items-center justify-between gap-3">
        <h3 class="hud-label">Runtime Defaults</h3>
        <span
          class={[
            "badge badge-xs",
            if(@summary.differ?, do: "badge-warning", else: "badge-success")
          ]}
          data-dashboard-runtime-defaults-status={@summary.status_label}
        >
          {@summary.status_label}
        </span>
      </div>
      <div class="grid gap-2 md:grid-cols-2">
        <.runtime_default_context label="Published" context={@summary.published} />
        <.runtime_default_context label="Draft" context={@summary.draft} />
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :context, :map, required: true

  defp runtime_default_context(assigns) do
    ~H"""
    <dl
      class="grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 text-xs"
      data-dashboard-runtime-default-context={@label}
    >
      <dt class="hud-label">{@label}</dt>
      <dd data-runtime-default-field="Version" class="font-mono text-base-content/70">
        {@context.version_text}
      </dd>
      <dt class="hud-label">Realm</dt>
      <dd data-runtime-default-field="Realm" class="font-mono text-base-content/70">
        {@context.realm}
      </dd>
      <dt class="hud-label">Source</dt>
      <dd data-runtime-default-field="Source" class="truncate font-mono text-base-content/70">
        {@context.source_binding_text}
      </dd>
      <dt class="hud-label">View</dt>
      <dd data-runtime-default-field="View" class="font-mono text-base-content/70">
        {@context.data_view}
      </dd>
    </dl>
    """
  end
end
