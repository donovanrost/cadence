defmodule CadenceWeb.OpsDashboardShowLive.RuntimeNoRefreshSummaryComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.RuntimeAdminDecisionLink

  attr :summary, :map, required: true

  def no_refresh_summary(%{summary: %{visible?: true}} = assigns) do
    ~H"""
    <section
      id="dashboard-no-refresh-summary"
      class="border border-warning/30 bg-warning/10 px-3 py-2 text-sm"
      data-diagnostics-section="No refresh summary"
      data-no-refresh-status={@summary.status}
      data-no-refresh-context={@summary.context}
      data-no-refresh-refresh={@summary.refresh}
      data-no-refresh-blocking-boundary={no_refresh_blocker_value(@summary, :boundary)}
      data-no-refresh-blocking-refresh-action={
        no_refresh_blocker_value(@summary, :refresh_action)
      }
      data-no-refresh-blocking-logical-source={
        no_refresh_blocker_value(@summary, :logical_source)
      }
      data-no-refresh-blocking-realm={no_refresh_blocker_value(@summary, :realm)}
      data-no-refresh-blocking-data-source={no_refresh_blocker_value(@summary, :data_source_id)}
      data-no-refresh-blocking-source-binding={
        no_refresh_blocker_value(@summary, :source_binding_id)
      }
      data-no-refresh-blocking-source={no_refresh_blocker_value(@summary, :decision_source)}
      data-no-refresh-blocking-decision-id={no_refresh_blocker_value(@summary, :decision_event_id)}
      data-no-refresh-blocking-admin-decision-link={admin_decision_link(@summary)}
      data-no-refresh-blocking-observable={no_refresh_blocker_value(@summary, :observable)}
      data-no-refresh-blocking-lifecycle-action={
        no_refresh_blocker_value(@summary, :lifecycle_action)
      }
      data-no-refresh-blocking-context={no_refresh_blocker_value(@summary, :context_reason)}
      data-no-refresh-blocking-refresh={no_refresh_blocker_value(@summary, :refresh_reason)}
      data-no-refresh-blocking-placements={
        no_refresh_blocker_value(@summary, :affected_placement_ids)
      }
      data-no-refresh-blocking-impact={no_refresh_blocker_value(@summary, :affected_impact_reasons)}
      data-no-refresh-blocking-source-cache-evidence-total={
        no_refresh_blocker_value(@summary, :source_cache_evidence_total)
      }
      data-no-refresh-blocking-source-cache-evidence-resolved={
        no_refresh_blocker_value(@summary, :source_cache_evidence_resolved)
      }
      data-no-refresh-blocking-source-cache-evidence-context-only={
        no_refresh_blocker_value(@summary, :source_cache_evidence_context_only)
      }
      data-no-refresh-blocking-source-cache-evidence-missing={
        no_refresh_blocker_value(@summary, :source_cache_evidence_missing)
      }
      data-no-refresh-blocking-source-cache-evidence-targets={
        no_refresh_blocker_value(@summary, :source_cache_evidence_target_ids)
      }
      data-no-refresh-blocking-source-cache-evidence-requests={
        no_refresh_blocker_value(@summary, :source_cache_evidence_request_ids)
      }
      data-no-refresh-blocking-source-execution-retryable={
        no_refresh_blocker_value(@summary, :source_execution_retryable_count)
      }
      data-no-refresh-blocking-source-execution-actionable={
        no_refresh_blocker_value(@summary, :source_execution_actionable_count)
      }
      data-no-refresh-blocking-source-execution-degraded={
        no_refresh_blocker_value(@summary, :source_execution_degraded_count)
      }
      data-no-refresh-blocking-source-execution-statuses={
        no_refresh_blocker_value(@summary, :source_execution_status_summary)
      }
      data-no-refresh-blocking-source-execution-actions={
        no_refresh_blocker_value(@summary, :source_execution_runtime_actions)
      }
      data-no-refresh-blocking-source-execution-degraded-identities={
        no_refresh_blocker_value(@summary, :source_execution_degraded_identities)
      }
      data-no-refresh-blocking-source-execution-degraded-actions={
        no_refresh_blocker_value(@summary, :source_execution_degraded_actions)
      }
      data-no-refresh-blocking-source-dependency-degraded={
        no_refresh_blocker_value(@summary, :source_dependency_degraded_count)
      }
      data-no-refresh-blocking-source-dependency-evidence={
        no_refresh_blocker_value(@summary, :source_dependency_evidence)
      }
    >
      <h3 class="hud-label">Why no refresh?</h3>
      <p class="mt-1 text-base-content">{@summary.headline}</p>
      <dl class="mt-2 grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <dt class="text-base-content/60">Context</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-field="Context">
          {@summary.context}
        </dd>
        <dt class="text-base-content/60">Refresh</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-field="Refresh">
          {@summary.refresh}
        </dd>
      </dl>
      <dl
        :if={no_refresh_blocker?(@summary)}
        id="dashboard-no-refresh-blocker"
        class="mt-3 grid grid-cols-[5.75rem_minmax(0,1fr)] gap-x-2 gap-y-1 border-t border-warning/30 pt-2 text-xs"
      >
        <dt class="text-base-content/60">Boundary</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Boundary">
          {no_refresh_blocker_value(@summary, :boundary)}
        </dd>
        <dt class="text-base-content/60">Observable</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Observable">
          {no_refresh_blocker_value(@summary, :observable)}
        </dd>
        <dt class="text-base-content/60">Action</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Action">
          {no_refresh_blocker_value(@summary, :refresh_action)}
        </dd>
        <dt class="text-base-content/60">Identity</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Identity">
          {no_refresh_blocker_identity(@summary)}
        </dd>
        <dt class="text-base-content/60">Lifecycle</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Lifecycle">
          {no_refresh_blocker_value(@summary, :lifecycle_action)}
        </dd>
        <dt class="text-base-content/60">Source</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Decision source"
        >
          {no_refresh_blocker_value(@summary, :decision_source)}
        </dd>
        <dt class="text-base-content/60">Decision ID</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Decision ID"
        >
          {no_refresh_blocker_value(@summary, :decision_event_id)}
        </dd>
        <dt class="text-base-content/60">Context</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Context">
          {no_refresh_blocker_value(@summary, :context_reason)}
        </dd>
        <dt class="text-base-content/60">Refresh</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Refresh">
          {no_refresh_blocker_value(@summary, :refresh_reason)}
        </dd>
        <dt class="text-base-content/60">Placements</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Placements"
        >
          {no_refresh_blocker_value(@summary, :affected_placement_ids)}
        </dd>
        <dt class="text-base-content/60">Impact</dt>
        <dd class="font-mono text-base-content break-all" data-no-refresh-blocker-field="Impact">
          {no_refresh_blocker_value(@summary, :affected_impact_reasons)}
        </dd>
        <dt class="text-base-content/60">Evidence</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source cache evidence"
        >
          {source_cache_evidence_summary(@summary)}
        </dd>
        <dt class="text-base-content/60">Ev targets</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source cache evidence targets"
        >
          {no_refresh_blocker_value(@summary, :source_cache_evidence_target_ids)}
        </dd>
        <dt class="text-base-content/60">Ev requests</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source cache evidence requests"
        >
          {no_refresh_blocker_value(@summary, :source_cache_evidence_request_ids)}
        </dd>
        <dt class="text-base-content/60">Src exec</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source execution"
        >
          {no_refresh_blocker_value(@summary, :source_execution_status_summary)}
        </dd>
        <dt class="text-base-content/60">Src actions</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source execution actions"
        >
          {no_refresh_blocker_value(@summary, :source_execution_runtime_actions)}
        </dd>
        <dt class="text-base-content/60">Src degraded</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source execution degraded"
        >
          {no_refresh_blocker_value(@summary, :source_execution_degraded_identities)}
        </dd>
        <dt class="text-base-content/60">Src d-actions</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source execution degraded actions"
        >
          {no_refresh_blocker_value(@summary, :source_execution_degraded_actions)}
        </dd>
        <dt class="text-base-content/60">Src deps</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source dependency degraded"
        >
          {no_refresh_blocker_value(@summary, :source_dependency_degraded_count)}
        </dd>
        <dt class="text-base-content/60">Src dep ev</dt>
        <dd
          class="font-mono text-base-content break-all"
          data-no-refresh-blocker-field="Source dependency evidence"
        >
          {no_refresh_blocker_value(@summary, :source_dependency_evidence)}
        </dd>
      </dl>
      <.link
        :if={admin_decision_link(@summary)}
        navigate={admin_decision_link(@summary)}
        class="btn btn-ghost btn-xs mt-2"
        data-no-refresh-admin-decision-link-action
      >
        <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" /> Runtime decision
      </.link>
    </section>
    """
  end

  def no_refresh_summary(assigns), do: ~H""

  defp no_refresh_blocker?(summary), do: is_map(Map.get(summary, :blocker))

  defp no_refresh_blocker_value(summary, key) when is_map(summary) and is_atom(key) do
    summary
    |> Map.get(:blocker, %{})
    |> case do
      blocker when is_map(blocker) -> blocker |> Map.get(key, "-") |> no_refresh_blocker_display()
      _other -> "-"
    end
  end

  defp no_refresh_blocker_display(value) when value in [nil, ""], do: "-"
  defp no_refresh_blocker_display(value), do: value

  defp source_cache_evidence_summary(summary) do
    [
      {"total", no_refresh_blocker_value(summary, :source_cache_evidence_total)},
      {"resolved", no_refresh_blocker_value(summary, :source_cache_evidence_resolved)},
      {"context", no_refresh_blocker_value(summary, :source_cache_evidence_context_only)},
      {"missing", no_refresh_blocker_value(summary, :source_cache_evidence_missing)}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, "", "-"] end)
    |> case do
      [] -> "-"
      parts -> Enum.map_join(parts, " ", fn {label, value} -> "#{label}:#{value}" end)
    end
  end

  defp no_refresh_blocker_identity(summary) do
    [
      no_refresh_blocker_value(summary, :logical_source),
      no_refresh_blocker_value(summary, :realm),
      no_refresh_blocker_value(summary, :data_source_id),
      no_refresh_blocker_value(summary, :source_binding_id)
    ]
    |> Enum.reject(&(&1 == "-"))
    |> case do
      [] -> "-"
      parts -> Enum.join(parts, ":")
    end
  end

  defp admin_decision_link(summary) do
    RuntimeAdminDecisionLink.from_no_refresh_summary(summary)
  end
end
