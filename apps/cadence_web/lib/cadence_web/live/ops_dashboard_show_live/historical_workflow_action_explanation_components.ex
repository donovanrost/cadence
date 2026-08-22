defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionExplanationComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation

  attr :blocked_action_explanations, :list, default: []

  def action_explanations(assigns) do
    ~H"""
    <section
      :if={@blocked_action_explanations != []}
      id="dashboard-historical-workflow-action-explanations"
      class="space-y-1 rounded border border-base-300/70 bg-base-100/60 p-2 text-xs"
    >
      <div class="flex items-center justify-between gap-2">
        <h4 class="hud-label">Unavailable Actions</h4>
        <span class="badge badge-xs badge-outline">
          {length(@blocked_action_explanations)}
        </span>
      </div>
      <div class="space-y-1">
        <div
          :for={explanation <- @blocked_action_explanations}
          class="rounded border border-base-300/60 bg-base-200/40 px-2 py-1"
          data-workflow-action-explanation-id={explanation.id}
          data-workflow-action-explanation-kind={explanation.kind}
          data-workflow-action-explanation-reason={explanation.reason}
          data-workflow-action-explanation-state={explanation.state_summary}
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-mono text-base-content">{explanation.label}</span>
            <span class="font-mono text-base-content/60">{explanation.reason}</span>
          </div>
          <p class="mt-1 text-base-content/75">{explanation.explanation}</p>
          <p
            :if={DataLinkInspectorPanelPresentation.present_text?(explanation.state_summary)}
            class="mt-1 font-mono text-base-content/65"
          >
            {explanation.state_summary}
          </p>
          <p
            :if={DataLinkInspectorPanelPresentation.present_text?(explanation.available_when)}
            class="mt-1 text-base-content/60"
          >
            {explanation.available_when}
          </p>
        </div>
      </div>
    </section>
    """
  end
end
