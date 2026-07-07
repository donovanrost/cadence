defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewActivity do
  @moduledoc false

  use CadenceWeb, :html

  attr :row, :map, required: true

  def request_details(assigns) do
    ~H"""
    <div
      :if={@row.render?}
      class="mt-2 border-t border-base-300/60 pt-2 text-xs"
      data-dashboard-comparison-review-request={@row.event_id}
      data-dashboard-comparison-review-status={@row.status}
      data-dashboard-comparison-review-resolution-event={@row.resolution_event_id}
      data-dashboard-comparison-review-result-event-id={@row.result_event_id}
      data-dashboard-comparison-review-target-event-id={@row.target_event_id}
      data-dashboard-comparison-review-schema={@row.schema}
      data-dashboard-comparison-review-kind={@row.kind}
      data-dashboard-comparison-review-open-count={@row.open_count_text}
      data-dashboard-comparison-review-placements={@row.placements_attr}
      data-dashboard-comparison-review-bulk-decision-skipped-count={
        @row.bulk_decision_skipped_count_text
      }
      data-dashboard-comparison-review-bulk-decision-skipped-placements={
        @row.bulk_decision_skipped_placement_ids_attr
      }
      data-dashboard-comparison-review-bulk-decision-skipped-reasons={
        @row.bulk_decision_skipped_reasons_attr
      }
    >
      <dl class="grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1">
        <dt class="hud-label">Request</dt>
        <dd data-activity-field="Request" class="font-mono text-base-content/70">
          {@row.kind}
        </dd>
        <dt class="hud-label">Open</dt>
        <dd data-activity-field="Open findings" class="font-mono text-base-content/70">
          {@row.open_count_text}
        </dd>
        <dt class="hud-label">Placements</dt>
        <dd data-activity-field="Open placements" class="break-all font-mono text-base-content/70">
          <div class="flex flex-wrap gap-1">
            <a
              :for={placement <- @row.placement_links}
              href={placement.href}
              class="link link-hover"
              phx-click="select_review_placement"
              phx-value-placement-id={placement.placement_id}
              data-dashboard-comparison-review-placement-link={placement.placement_id}
              data-dashboard-review-placement-selected={placement.selected_text}
            >
              {placement.placement_id}
            </a>
            <span :if={@row.placement_links == []}>-</span>
          </div>
        </dd>
      </dl>
      <div class="mt-2 flex items-center justify-between gap-2">
        <span
          :if={@row.resolved?}
          class="badge badge-success badge-outline badge-xs"
          data-dashboard-comparison-review-resolved={@row.event_id}
        >
          Resolved
        </span>
        <button
          :if={not @row.resolved? and @row.workflow_request_available?}
          id={"dashboard-comparison-review-workflow-request-#{@row.event_id}"}
          type="button"
          class="btn btn-ghost btn-xs gap-1"
          phx-click="open_comparison_review_workflow_request"
          phx-value-request-event-id={@row.event_id}
          data-dashboard-comparison-review-workflow-request={@row.event_id}
          data-dashboard-comparison-review-workflow-point-count={
            @row.workflow_request_point_count_text
          }
          data-dashboard-comparison-review-workflow-point-ids={
            @row.workflow_request_point_ids_attr
          }
        >
          <.icon name="hero-document-plus" class="h-3.5 w-3.5" /> Prepare workflow
        </button>
        <span
          :if={not @row.resolved? and @row.bulk_decision_skipped_label}
          class="badge badge-neutral badge-outline badge-xs gap-1"
          data-dashboard-comparison-review-bulk-decision-skipped={@row.event_id}
          data-dashboard-comparison-review-bulk-decision-skipped-count={
            @row.bulk_decision_skipped_count_text
          }
          data-dashboard-comparison-review-bulk-decision-skipped-placements={
            @row.bulk_decision_skipped_placement_ids_attr
          }
          data-dashboard-comparison-review-bulk-decision-skipped-reasons={
            @row.bulk_decision_skipped_reasons_attr
          }
        >
          <.icon name="hero-information-circle" class="h-3.5 w-3.5" />
          {@row.bulk_decision_skipped_label}
        </span>
        <span
          :if={not @row.resolved? and @row.bulk_decision_unavailable?}
          class="badge badge-warning badge-outline badge-xs gap-1"
          data-dashboard-comparison-review-bulk-decision-unavailable={@row.event_id}
          data-dashboard-comparison-review-bulk-decision-unavailable-reason={
            @row.bulk_decision_unavailable_reason
          }
          data-dashboard-comparison-review-bulk-decision-unavailable-count={
            @row.bulk_decision_count_text
          }
          data-dashboard-comparison-review-bulk-decision-unavailable-placements={
            @row.bulk_decision_placement_ids_attr
          }
        >
          <.icon name="hero-exclamation-triangle" class="h-3.5 w-3.5" />
          {@row.bulk_decision_unavailable_label}
        </span>
        <form
          :if={not @row.resolved? and @row.bulk_decision_available?}
          id={"dashboard-comparison-review-bulk-decision-form-#{@row.event_id}"}
          phx-submit="apply_comparison_review_bulk_decision"
          class="flex items-center gap-1"
          data-dashboard-comparison-review-bulk-decision-form={@row.event_id}
          data-dashboard-comparison-review-bulk-decision-count={@row.bulk_decision_count_text}
          data-dashboard-comparison-review-bulk-decision-placements={
            @row.bulk_decision_placement_ids_attr
          }
        >
          <input type="hidden" name="review[source_request_event_id]" value={@row.event_id} />
          <input type="hidden" name="review[decision]" value="mark_conflict" />
          <input type="hidden" name="review[confirmed]" value="confirmed" />
          <input
            type="hidden"
            name="review[decision_reason]"
            value="dashboard_comparison_review_mark_conflict"
          />
          <button
            id={"dashboard-comparison-review-bulk-decision-#{@row.event_id}"}
            type="submit"
            class="btn btn-ghost btn-xs gap-1"
            data-dashboard-comparison-review-bulk-decision={@row.event_id}
            data-dashboard-comparison-review-bulk-decision-kind="mark_conflict"
          >
            <.icon name="hero-shield-exclamation" class="h-3.5 w-3.5" /> Mark conflicts
          </button>
        </form>
        <form
          :if={not @row.resolved?}
          id={"dashboard-comparison-review-resolve-form-#{@row.event_id}"}
          phx-submit="resolve_comparison_review"
          class="ml-auto flex items-center gap-1"
          data-dashboard-comparison-review-resolve-form={@row.event_id}
        >
          <input type="hidden" name="review[source_request_event_id]" value={@row.event_id} />
          <input type="hidden" name="review[disposition]" value="review_completed" />
          <input
            type="hidden"
            name="review[selected_placement_id]"
            value={@row.selected_placement_id}
          />
          <input
            type="hidden"
            name="review[affected_placement_ids]"
            value={@row.placements_attr}
          />
          <.input
            id={"dashboard-comparison-review-resolution-reason-#{@row.event_id}"}
            name="review[resolution_reason]"
            type="text"
            value=""
            placeholder="Resolution note"
            maxlength="240"
            compact
            class="input-xs w-40"
            data-dashboard-comparison-review-resolution-reason={@row.event_id}
          />
          <button
            id={"dashboard-comparison-review-resolve-#{@row.event_id}"}
            type="submit"
            class="btn btn-ghost btn-xs gap-1"
            data-dashboard-comparison-review-resolve={@row.event_id}
          >
            <.icon name="hero-check-circle" class="h-3.5 w-3.5" /> Resolve
          </button>
        </form>
      </div>
      <ul
        :if={@row.findings != []}
        class="mt-2 space-y-1"
        data-dashboard-comparison-review-findings={length(@row.findings)}
      >
        <li
          :for={finding <- @row.findings}
          class="grid grid-cols-[1fr_auto] gap-2 rounded bg-base-200/60 px-2 py-1"
          data-dashboard-comparison-review-finding={finding.placement_id}
          data-dashboard-comparison-review-finding-state={finding.state}
          data-dashboard-comparison-review-finding-status={finding.decision_status}
          data-dashboard-comparison-review-finding-observation-identity={
            finding.observation_identity_id
          }
          data-dashboard-comparison-review-finding-bulk-decision={
            finding.bulk_decision_status
          }
          data-dashboard-comparison-review-finding-bulk-decision-reason={
            finding.bulk_decision_reason
          }
          data-dashboard-comparison-review-finding-bulk-decision-label={
            finding.bulk_decision_label
          }
        >
          <a
            href={finding.placement_href}
            class="link link-hover min-w-0 truncate"
            phx-click="select_review_placement"
            phx-value-placement-id={finding.placement_id}
            data-dashboard-comparison-review-finding-placement-link={finding.placement_id}
            data-dashboard-review-placement-selected={finding.placement_selected_text}
          >
            {finding.title}
          </a>
          <div class="flex flex-wrap items-center justify-end gap-1">
            <span class="font-mono text-base-content/60">
              {finding.decision_status}
            </span>
            <span
              class="badge badge-outline badge-xs"
              data-dashboard-comparison-review-finding-bulk-decision-badge={
                finding.placement_id
              }
            >
              {finding.bulk_decision_label}
            </span>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :row, :map, required: true

  def resolution_details(assigns) do
    ~H"""
    <div
      :if={@row.render?}
      class="mt-2 border-t border-base-300/60 pt-2 text-xs"
      data-dashboard-comparison-review-resolution={@row.event_id}
      data-dashboard-comparison-review-resolution-result-event-id={@row.result_event_id}
      data-dashboard-comparison-review-resolution-target-event-id={@row.target_event_id}
      data-dashboard-comparison-review-resolution-source={@row.source_request_event_id}
      data-dashboard-comparison-review-resolution-disposition={@row.disposition}
      data-dashboard-comparison-review-resolution-selected-placement={@row.selected_placement_id}
      data-dashboard-comparison-review-resolution-affected-placements={@row.affected_placements_attr}
      data-dashboard-comparison-review-resolution-workflow-kind={@row.workflow_intent_kind}
      data-dashboard-comparison-review-resolution-workflow-action={@row.workflow_intent_action}
      data-dashboard-comparison-review-resolution-workflow-selection-count={
        @row.workflow_selection_count_text
      }
      data-dashboard-comparison-review-resolution-source-open-count={@row.source_open_count_text}
      data-dashboard-comparison-review-resolution-source-open-placements={
        @row.source_open_placements_attr
      }
      data-dashboard-comparison-review-resolution-source-actionable-count={
        @row.source_bulk_decision_actionable_count_text
      }
      data-dashboard-comparison-review-resolution-source-actionable-placements={
        @row.source_bulk_decision_actionable_placements_attr
      }
      data-dashboard-comparison-review-resolution-source-skipped-count={
        @row.source_bulk_decision_skipped_count_text
      }
      data-dashboard-comparison-review-resolution-source-skipped-placements={
        @row.source_bulk_decision_skipped_placements_attr
      }
      data-dashboard-comparison-review-resolution-source-skipped-reasons={
        @row.source_bulk_decision_skipped_reasons_attr
      }
    >
      <dl class="grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1">
        <dt class="hud-label">Request</dt>
        <dd data-activity-field="Resolved request" class="font-mono text-base-content/70">
          {@row.source_request_event_id}
        </dd>
        <dt class="hud-label">Result</dt>
        <dd data-activity-field="Resolution disposition" class="font-mono text-base-content/70">
          {@row.disposition}
        </dd>
        <dt :if={@row.resolution_reason != "-"} class="hud-label">
          Reason
        </dt>
        <dd
          :if={@row.resolution_reason != "-"}
          data-activity-field="Resolution reason"
          class="text-base-content/70"
        >
          {@row.resolution_reason}
        </dd>
        <dt :if={@row.selected_placement_id != "-"} class="hud-label">
          Placement
        </dt>
        <dd
          :if={@row.selected_placement_id != "-"}
          data-activity-field="Resolution placement"
          class="font-mono text-base-content/70"
        >
          {@row.selected_placement_id}
        </dd>
        <dt :if={@row.affected_placements_text != "-"} class="hud-label">
          Affected
        </dt>
        <dd
          :if={@row.affected_placements_text != "-"}
          data-activity-field="Resolution affected placements"
          class="break-all font-mono text-base-content/70"
        >
          {@row.affected_placements_text}
        </dd>
        <dt :if={@row.workflow_intent_kind != "-"} class="hud-label">
          Workflow
        </dt>
        <dd
          :if={@row.workflow_intent_kind != "-"}
          data-activity-field="Resolution workflow"
          class="break-all font-mono text-base-content/70"
        >
          {@row.workflow_intent_kind} / {@row.workflow_selection_count_text}
        </dd>
        <dt :if={@row.source_bulk_decision_summary_text != "-"} class="hud-label">
          Bulk action
        </dt>
        <dd
          :if={@row.source_bulk_decision_summary_text != "-"}
          data-activity-field="Resolution bulk decision source"
          class="break-all font-mono text-base-content/70"
        >
          {@row.source_bulk_decision_summary_text}
        </dd>
      </dl>
    </div>
    """
  end
end
