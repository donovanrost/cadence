defmodule CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.LifecycleEvent
  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.LifecycleRuntimeCorrelation
  alias CadenceWeb.OpsDashboardShowLive.RuntimeAdminDecisionLink

  attr :invalidations, :list, required: true
  attr :dashboard_lifecycle_events, :list, default: []
  attr :dashboard_current_path, :string, default: nil

  def recent_invalidations(assigns) do
    ~H"""
    <section class="space-y-2" data-diagnostics-section="Recent invalidations">
      <div class="flex items-center justify-between">
        <h3 class="hud-label">Recent invalidations</h3>
        <span class="font-mono text-xs text-base-content/50">{length(@invalidations)}</span>
      </div>
      <ol id="dashboard-recent-invalidations" class="space-y-2">
        <li
          :for={event <- @invalidations}
          id={"dashboard-runtime-invalidation-#{event.id}"}
          data-runtime-invalidation-dashboard={invalidation_field(event, :dashboard_id)}
          data-runtime-invalidation-mission={invalidation_field(event, :mission_id)}
          data-runtime-invalidation-boundary={event.boundary}
          data-runtime-invalidation-source={event.logical_source}
          data-runtime-invalidation-realm={event.realm}
          data-runtime-invalidation-data-source={event.data_source_id}
          data-runtime-invalidation-binding={event.source_binding_id}
          data-runtime-invalidation-replay-run-id={event.replay_run_id}
          data-runtime-invalidation-observable={event.observable}
          data-runtime-invalidation-lifecycle-action={event.lifecycle_action}
          data-runtime-invalidation-lifecycle-correlation-state={
            invalidation_field(event, :lifecycle_correlation_state)
          }
          data-runtime-invalidation-lifecycle-correlation-label={
            invalidation_field(event, :lifecycle_correlation_label)
          }
          data-runtime-invalidation-lifecycle-target-version={
            invalidation_field(event, :lifecycle_correlation_target_version)
          }
          data-runtime-invalidation-lifecycle-source-version={
            invalidation_field(event, :lifecycle_correlation_source_version)
          }
          data-runtime-invalidation-activity-event-id={
            activity_event_id(event, @dashboard_lifecycle_events)
          }
          data-runtime-invalidation-activity-link={
            activity_event_link(event, @dashboard_lifecycle_events, @dashboard_current_path)
          }
          data-runtime-invalidation-admin-decision-link={admin_decision_link(event)}
          data-runtime-invalidation-source-version={event.source_version}
          data-runtime-invalidation-document-version={event.document_version}
          data-runtime-invalidation-context-match={event.context_match}
          data-runtime-invalidation-context-reason={event.context_reason}
          data-runtime-invalidation-refresh-allowed={event.refresh_allowed}
          data-runtime-invalidation-refresh-allowed-reason={event.refresh_allowed_reason}
          data-runtime-invalidation-refresh-reason={event.refresh_reason}
          data-runtime-invalidation-refresh-action={event.refresh_action}
          data-runtime-invalidation-decision-status={event.decision_status}
          data-runtime-invalidation-decision-source={event.decision_source}
          data-runtime-invalidation-decision-event-id={event.decision_event_id}
          data-runtime-invalidation-decision-observed-at={event.decision_observed_at}
          data-runtime-invalidation-affected-placement-count={event.affected_placement_count}
          data-runtime-invalidation-affected-placement-ids={event.affected_placement_ids}
          data-runtime-invalidation-affected-widget-types={event.affected_widget_type_ids}
          data-runtime-invalidation-affected-impact-reasons={event.affected_impact_reasons}
          data-runtime-invalidation-selection-state={invalidation_field(event, :selection_state)}
          data-runtime-invalidation-selected-link={invalidation_field(event, :selected_link_id)}
          data-runtime-invalidation-selected-target={invalidation_field(event, :selected_target)}
          data-runtime-invalidation-selected-target-id={invalidation_field(event, :selected_target_id)}
          data-runtime-invalidation-selected-placement-id={
            invalidation_field(event, :selected_placement_id)
          }
          data-runtime-invalidation-selected-observable={
            invalidation_field(event, :selected_observable_id)
          }
          data-runtime-invalidation-selected-data-view={
            invalidation_field(event, :selected_data_view)
          }
          data-runtime-invalidation-selection-affected={
            invalidation_field(event, :selection_affected)
          }
          data-runtime-invalidation-selection-impact-reason={
            invalidation_field(event, :selection_impact_reason)
          }
          data-runtime-invalidation-source-cache-evidence-total={
            invalidation_field(event, :source_cache_evidence_total)
          }
          data-runtime-invalidation-source-cache-evidence-resolved={
            invalidation_field(event, :source_cache_evidence_resolved)
          }
          data-runtime-invalidation-source-cache-evidence-context-only={
            invalidation_field(event, :source_cache_evidence_context_only)
          }
          data-runtime-invalidation-source-cache-evidence-missing={
            invalidation_field(event, :source_cache_evidence_missing)
          }
          data-runtime-invalidation-source-cache-evidence-targets={
            invalidation_field(event, :source_cache_evidence_target_ids)
          }
          data-runtime-invalidation-source-cache-evidence-requests={
            invalidation_field(event, :source_cache_evidence_request_ids)
          }
          data-runtime-invalidation-source-execution-retryable={
            invalidation_field(event, :source_execution_retryable_count)
          }
          data-runtime-invalidation-source-execution-actionable={
            invalidation_field(event, :source_execution_actionable_count)
          }
          data-runtime-invalidation-source-execution-degraded={
            invalidation_field(event, :source_execution_degraded_count)
          }
          data-runtime-invalidation-source-execution-statuses={
            invalidation_field(event, :source_execution_status_summary)
          }
          data-runtime-invalidation-source-execution-actions={
            invalidation_field(event, :source_execution_runtime_actions)
          }
          data-runtime-invalidation-source-execution-degraded-identities={
            invalidation_field(event, :source_execution_degraded_identities)
          }
          data-runtime-invalidation-source-execution-degraded-actions={
            invalidation_field(event, :source_execution_degraded_actions)
          }
          data-runtime-invalidation-source-dependency-degraded={
            invalidation_field(event, :source_dependency_degraded_count)
          }
          data-runtime-invalidation-source-dependency-evidence={
            invalidation_field(event, :source_dependency_evidence)
          }
          data-runtime-invalidation-artifacts={event.artifacts}
          data-runtime-invalidation-occurred-at={event.occurred_at}
          class="border border-base-300/70 bg-base-100/40 px-2 py-2"
        >
          <div class="flex flex-wrap items-center gap-1.5">
            <span class="badge badge-xs badge-outline">{event.boundary}</span>
            <span class="badge badge-xs">{event.logical_source}</span>
            <span class="font-mono text-xs text-base-content/60">{event.artifacts}</span>
          </div>
          <.link
            :if={activity_event_link(event, @dashboard_lifecycle_events, @dashboard_current_path)}
            navigate={activity_event_link(event, @dashboard_lifecycle_events, @dashboard_current_path)}
            class="btn btn-ghost btn-xs mt-2"
            data-runtime-invalidation-activity-link-action
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" /> Open activity
          </.link>
          <.link
            :if={admin_decision_link(event)}
            navigate={admin_decision_link(event)}
            class="btn btn-ghost btn-xs mt-2"
            data-runtime-invalidation-admin-decision-link-action
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" /> Runtime decision
          </.link>
          <dl class="mt-2 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
            <dt class="text-base-content/60">Observable</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Observable">
              {event.observable}
            </dd>
            <dt class="text-base-content/60">Realm</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Realm">
              {event.realm}
            </dd>
            <dt class="text-base-content/60">Source</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Source">
              {event.data_source_id}
            </dd>
            <dt class="text-base-content/60">Binding</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Binding">
              {event.source_binding_id}
            </dd>
            <dt class="text-base-content/60">Replay</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Replay">
              {event.replay_run_id}
            </dd>
            <dt class="text-base-content/60">Context</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Context">
              {event.context_match}
            </dd>
            <dt class="text-base-content/60">Ctx reason</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Context reason"
            >
              {event.context_reason_label}
            </dd>
            <dt class="text-base-content/60">Allowed</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Allowed">
              {event.refresh_allowed}
            </dd>
            <dt class="text-base-content/60">Allow reason</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Allowed reason"
            >
              {event.refresh_allowed_reason_label}
            </dd>
            <dt class="text-base-content/60">Decision</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Decision">
              {event.decision_status}
            </dd>
            <dt class="text-base-content/60">Source</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Decision source"
            >
              {event.decision_source}
            </dd>
            <dt class="text-base-content/60">Decision ID</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Decision ID"
            >
              {event.decision_event_id}
            </dd>
            <dt class="text-base-content/60">Decision at</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Decision observed"
            >
              {event.decision_observed_at}
            </dd>
            <dt class="text-base-content/60">Impacted</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Impacted">
              {event.affected_placement_count}
            </dd>
            <dt class="text-base-content/60">Placements</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Placements">
              {event.affected_placement_ids}
            </dd>
            <dt class="text-base-content/60">Widgets</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Widgets">
              {event.affected_widget_type_ids}
            </dd>
            <dt class="text-base-content/60">Impact</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Impact">
              {event.affected_impact_reasons}
            </dd>
            <dt class="text-base-content/60">Selection</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Selection"
            >
              {invalidation_field(event, :selection_affected)}
            </dd>
            <dt class="text-base-content/60">Sel reason</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Selection reason"
            >
              {invalidation_field(event, :selection_impact_reason)}
            </dd>
            <dt class="text-base-content/60">Sel target</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Selection target"
            >
              {invalidation_field(event, :selected_target)}
            </dd>
            <dt class="text-base-content/60">Sel ID</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Selection ID"
            >
              {invalidation_field(event, :selected_target_id)}
            </dd>
            <dt class="text-base-content/60">Evidence</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source cache evidence"
            >
              {source_cache_evidence_summary(event)}
            </dd>
            <dt class="text-base-content/60">Ev targets</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source cache evidence targets"
            >
              {invalidation_field(event, :source_cache_evidence_target_ids)}
            </dd>
            <dt class="text-base-content/60">Ev requests</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source cache evidence requests"
            >
              {invalidation_field(event, :source_cache_evidence_request_ids)}
            </dd>
            <dt class="text-base-content/60">Src exec</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source execution"
            >
              {invalidation_field(event, :source_execution_status_summary)}
            </dd>
            <dt class="text-base-content/60">Src actions</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source execution actions"
            >
              {invalidation_field(event, :source_execution_runtime_actions)}
            </dd>
            <dt class="text-base-content/60">Src degraded</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source execution degraded"
            >
              {invalidation_field(event, :source_execution_degraded_identities)}
            </dd>
            <dt class="text-base-content/60">Src d-actions</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source execution degraded actions"
            >
              {invalidation_field(event, :source_execution_degraded_actions)}
            </dd>
            <dt class="text-base-content/60">Src deps</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source dependency degraded"
            >
              {invalidation_field(event, :source_dependency_degraded_count)}
            </dd>
            <dt class="text-base-content/60">Src dep ev</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-invalidation-field="Source dependency evidence"
            >
              {invalidation_field(event, :source_dependency_evidence)}
            </dd>
            <dt class="text-base-content/60">Action</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Action">
              {event.lifecycle_action}
            </dd>
            <dt class="text-base-content/60">Lifecycle</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Lifecycle">
              {invalidation_field(event, :lifecycle_correlation_label)}
            </dd>
            <dt class="text-base-content/60">Version</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Version">
              {event.document_version}
            </dd>
            <dt class="text-base-content/60">Reason</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Reason">
              {event.refresh_reason}
            </dd>
            <dt class="text-base-content/60">Refresh</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Refresh">
              {event.refresh_action}
            </dd>
            <dt class="text-base-content/60">Time</dt>
            <dd class="font-mono text-base-content break-all" data-invalidation-field="Time">
              {event.occurred_at}
            </dd>
          </dl>
        </li>
      </ol>
      <p :if={@invalidations == []} class="text-sm text-base-content/60">
        No runtime invalidations.
      </p>
    </section>
    """
  end

  defp invalidation_field(event, key) when is_map(event), do: Map.get(event, key, "-")
  defp invalidation_field(_event, _key), do: "-"

  defp source_cache_evidence_summary(event) do
    [
      {"total", invalidation_field(event, :source_cache_evidence_total)},
      {"resolved", invalidation_field(event, :source_cache_evidence_resolved)},
      {"context", invalidation_field(event, :source_cache_evidence_context_only)},
      {"missing", invalidation_field(event, :source_cache_evidence_missing)}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, "", "-"] end)
    |> case do
      [] -> "-"
      parts -> Enum.map_join(parts, " ", fn {label, value} -> "#{label}:#{value}" end)
    end
  end

  defp activity_event_link(event, lifecycle_events, current_path) when is_binary(current_path) do
    case LifecycleRuntimeCorrelation.activity_event(event, lifecycle_events) do
      %LifecycleEvent{} = lifecycle_event ->
        ActivityNavigation.link(current_path, :version_changes, lifecycle_event)

      nil ->
        nil
    end
  end

  defp activity_event_link(_event, _lifecycle_events, _current_path), do: nil

  defp activity_event_id(event, lifecycle_events) do
    LifecycleRuntimeCorrelation.activity_event_id(event, lifecycle_events)
  end

  defp admin_decision_link(event) do
    RuntimeAdminDecisionLink.from_runtime_invalidation(event)
  end
end
