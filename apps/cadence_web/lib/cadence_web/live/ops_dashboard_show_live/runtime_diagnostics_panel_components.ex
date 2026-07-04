defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheSummaryComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDegradedSourceComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeNoRefreshSummaryComponents
  alias CadenceWeb.OpsDashboardShowLive.RuntimeRecentInvalidationsComponents

  attr :diagnostics, :map, required: true
  attr :dashboard_lifecycle_events, :list, default: []
  attr :dashboard_current_path, :string, default: nil

  def diagnostics_panel(assigns) do
    ~H"""
    <section
      id="dashboard-diagnostics-panel"
      class="space-y-5"
      data-runtime-invalidation-events={@diagnostics.invalidation_event_count}
      data-runtime-invalidation-artifacts={@diagnostics.invalidation_artifact_count}
      data-runtime-invalidation-boundaries={@diagnostics.invalidation_boundary_summary}
      data-runtime-invalidation-context-matches={@diagnostics.invalidation_context_match_count}
      data-runtime-invalidation-context-filtered={@diagnostics.invalidation_context_filtered_count}
      data-runtime-invalidation-context-filter-reasons={
        @diagnostics.invalidation_context_filter_reasons
      }
      data-runtime-invalidation-refresh-allowed={@diagnostics.invalidation_refresh_allowed_count}
      data-runtime-invalidation-refresh-suppressed={
        @diagnostics.invalidation_refresh_suppressed_count
      }
      data-runtime-invalidation-refresh-suppress-reasons={
        @diagnostics.invalidation_refresh_suppress_reasons
      }
      data-runtime-refresh-status={@diagnostics.refresh_status}
      data-runtime-refresh-reason={@diagnostics.refresh_reason}
      data-runtime-active-refresh-mode={@diagnostics.active_refresh_mode}
      data-runtime-active-refresh-started-at={@diagnostics.active_refresh_started_at}
      data-runtime-visible-refresh-action={@diagnostics.visible_refresh_action}
      data-runtime-last-refresh-started-at={@diagnostics.last_refresh_started_at}
      data-runtime-last-refresh-finished-at={@diagnostics.last_refresh_finished_at}
      data-runtime-last-refresh-duration-ms={@diagnostics.last_refresh_duration_ms}
      data-runtime-refresh-starts={@diagnostics.refresh_starts}
      data-runtime-refresh-cancellations={@diagnostics.refresh_cancellations}
      data-runtime-refresh-coalesced={@diagnostics.refresh_coalesced}
      data-runtime-refresh-noops={@diagnostics.refresh_noops}
      data-runtime-refresh-failures={@diagnostics.refresh_failures}
      data-runtime-refresh-ignored={@diagnostics.refresh_ignored}
      data-runtime-refresh-ignored-resolve-ids={@diagnostics.refresh_ignored_resolve_ids}
      data-runtime-canceled-resolves={@diagnostics.canceled_resolve_count}
      data-runtime-failed-resolves={@diagnostics.failed_resolve_count}
      data-runtime-source-execution-degraded-identities={
        @diagnostics.source_execution_degraded_identities
      }
       data-runtime-source-execution-degraded-actions={
         @diagnostics.source_execution_degraded_actions
       }
       data-runtime-source-capability-statuses={
         Map.get(@diagnostics, :source_capability_statuses_text)
       }
       data-runtime-source-capability-postures={
         Map.get(@diagnostics, :source_capability_posture_text)
       }
       data-runtime-source-dependency-evidence={Map.get(@diagnostics, :source_dependency_evidence_text)}
      data-runtime-source-dependency-degraded-count={
        Map.get(@diagnostics, :source_dependency_degraded_count)
      }
    >
      <.diagnostics_section title="Engine" rows={@diagnostics.engine_rows} />
      <RuntimeCacheSummaryComponents.cache_summary summary={@diagnostics.cache_summary} />
      <.diagnostics_section title="Runtime" rows={@diagnostics.runtime_rows} />
      <RuntimeDegradedSourceComponents.degraded_source_summary summary={
        @diagnostics.source_execution_degraded_summary
      } />
       <RuntimeDegradedSourceComponents.degraded_source_drilldowns drilldowns={
         @diagnostics.source_execution_degraded_drilldowns
       } />
       <RuntimeDegradedSourceComponents.source_capability_postures postures={
         Map.get(@diagnostics, :source_capability_postures, [])
       } />
       <RuntimeDegradedSourceComponents.source_dependency_causes dependencies={
        Map.get(@diagnostics, :source_dependency_evidence, [])
      } />
      <RuntimeNoRefreshSummaryComponents.no_refresh_summary summary={
        @diagnostics.no_refresh_summary
      } />
      <.diagnostics_section title="Invalidation" rows={@diagnostics.invalidation_rows} />
      <RuntimeRecentInvalidationsComponents.recent_invalidations
        invalidations={@diagnostics.recent_invalidations}
        dashboard_lifecycle_events={@dashboard_lifecycle_events}
        dashboard_current_path={@dashboard_current_path}
      />
    </section>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true

  defp diagnostics_section(assigns) do
    ~H"""
    <section class="space-y-2" data-diagnostics-section={@title}>
      <h3 class="hud-label">{@title}</h3>
      <dl class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <%= for row <- @rows do %>
          <dt class="text-base-content/60">{row.label}</dt>
          <dd class="font-mono text-base-content break-all" data-diagnostics-field={row.label}>
            {row.value}
          </dd>
        <% end %>
      </dl>
    </section>
    """
  end
end
