defmodule CadenceWeb.OpsDashboardShowLive.RuntimeCacheSummaryComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs

  attr :summary, :map, required: true

  def cache_summary(%{summary: %{visible?: true}} = assigns) do
    ~H"""
    <section
      id="dashboard-cache-summary"
      class="border border-base-300/70 bg-base-100/40 px-3 py-2 text-sm"
      data-diagnostics-section="Cache state"
      data-cache-classification={@summary.classification}
      data-cache-plan={@summary.plan}
      data-cache-source={@summary.source}
      data-cache-frame={@summary.frame}
    >
      <h3 class="hud-label">Cache state</h3>
      <p class="mt-1 text-base-content">{@summary.headline}</p>
      <dl class="mt-2 grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <dt class="text-base-content/60">Plan</dt>
        <dd class="font-mono text-base-content break-all" data-cache-field="Plan">
          {@summary.plan}
        </dd>
        <dt class="text-base-content/60">Source</dt>
        <dd class="font-mono text-base-content break-all" data-cache-field="Source">
          {@summary.source}
        </dd>
        <dt class="text-base-content/60">Frame</dt>
        <dd class="font-mono text-base-content break-all" data-cache-field="Frame">
          {@summary.frame}
        </dd>
      </dl>
      <div
        :if={@summary.drilldowns != []}
        id="dashboard-cache-evidence"
        class="mt-3 border-t border-base-300/70 pt-2"
        data-cache-evidence-count={length(@summary.drilldowns)}
        data-cache-evidence-resolved={@summary.evidence_state_summary.resolved}
        data-cache-evidence-context-only={@summary.evidence_state_summary.context_only}
        data-cache-evidence-missing={@summary.evidence_state_summary.missing}
      >
        <h4 class="hud-label text-[0.65rem]">Cache evidence</h4>
        <dl class="mt-2 grid grid-cols-3 gap-2 text-xs">
          <div>
            <dt class="text-base-content/60">Resolved</dt>
            <dd class="font-mono text-base-content" data-cache-evidence-state-field="Resolved">
              {@summary.evidence_state_summary.resolved}
            </dd>
          </div>
          <div>
            <dt class="text-base-content/60">Context</dt>
            <dd class="font-mono text-base-content" data-cache-evidence-state-field="Context only">
              {@summary.evidence_state_summary.context_only}
            </dd>
          </div>
          <div>
            <dt class="text-base-content/60">Missing</dt>
            <dd class="font-mono text-base-content" data-cache-evidence-state-field="Missing">
              {@summary.evidence_state_summary.missing}
            </dd>
          </div>
        </dl>
        <ul class="mt-2 space-y-2">
          <li
            :for={item <- @summary.drilldowns}
            data-cache-evidence-id={item.evidence_id}
            data-cache-evidence-layer={item.layer}
            data-cache-evidence-status={item.status}
            data-cache-evidence-request-id={item.request_id}
            data-cache-evidence-placement-id={item.placement_id}
            data-cache-evidence-source={item.logical_source}
            data-cache-evidence-source-binding-id={item.source_binding_id}
            data-cache-evidence-data-source-id={item.data_source_id}
            data-cache-evidence-reasons={item.reasons}
            data-cache-evidence-state={item.evidence_state}
            data-cache-evidence-incident-status={item.incident_status_text}
            data-cache-evidence-incident-severity={item.incident_severity}
            data-cache-evidence-incident-action={item.incident_operator_action}
            data-cache-evidence-incident-runtime-action={item.incident_runtime_action}
            data-cache-evidence-incident-target={item.incident_evidence_target}
            data-cache-evidence-incident-target-id={item.incident_evidence_target_id}
            data-cache-evidence-incident-kind={item.incident_evidence_kind}
          >
            <button
              type="button"
              class="grid w-full grid-cols-[3.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 border border-base-300/60 bg-base-200/20 px-2 py-2 text-left text-xs hover:bg-base-200/50"
              phx-click="open_evidence"
              {EvidenceAttrs.cache(item)}
              data-cache-evidence-open={item.evidence_id}
            >
              <span class="text-base-content/60">Layer</span>
              <span class="font-mono text-base-content break-all" data-cache-evidence-field="Layer">
                {item.layer}
              </span>
              <span class="text-base-content/60">Status</span>
              <span class="font-mono text-base-content break-all" data-cache-evidence-field="Status">
                {item.status}
              </span>
              <span class="text-base-content/60">Request</span>
              <span class="font-mono text-base-content break-all" data-cache-evidence-field="Request">
                {item.request_id}
              </span>
              <span :if={item.placement_id != "-"} class="text-base-content/60">Placement</span>
              <span
                :if={item.placement_id != "-"}
                class="font-mono text-base-content break-all"
                data-cache-evidence-field="Placement"
              >
                {item.placement_id}
              </span>
              <span class="text-base-content/60">Source</span>
              <span class="font-mono text-base-content break-all" data-cache-evidence-field="Source">
                {item.logical_source}
              </span>
              <span class="text-base-content/60">Binding</span>
              <span class="font-mono text-base-content break-all" data-cache-evidence-field="Binding">
                {item.source_binding_id}
              </span>
              <span class="text-base-content/60">Data</span>
              <span class="font-mono text-base-content break-all" data-cache-evidence-field="Data source">
                {item.data_source_id}
              </span>
              <span class="text-base-content/60">Why</span>
              <span class="font-mono text-base-content break-all" data-cache-evidence-field="Reasons">
                {item.reasons}
              </span>
              <span :if={item.incident_status_text != "-"} class="text-base-content/60">Incident</span>
              <span
                :if={item.incident_status_text != "-"}
                class="font-mono text-base-content break-all"
                data-cache-evidence-field="Incident"
              >
                {item.incident_status_text}
              </span>
              <span :if={item.incident_operator_action != "-"} class="text-base-content/60">Action</span>
              <span
                :if={item.incident_operator_action != "-"}
                class="font-mono text-base-content break-all"
                data-cache-evidence-field="Action"
              >
                {item.incident_operator_action}
              </span>
              <span :if={item.incident_evidence_target_id != "-"} class="text-base-content/60">
                Evidence
              </span>
              <span
                :if={item.incident_evidence_target_id != "-"}
                class="font-mono text-base-content break-all"
                data-cache-evidence-field="Evidence"
              >
                {item.incident_evidence_kind_text}:{item.incident_evidence_target_id}
              </span>
            </button>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  def cache_summary(assigns), do: ~H""
end
