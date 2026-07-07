defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryFormPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupRecoveryPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementRecovery
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true
  attr :dashboard_current_path, :string, default: nil

  def group_status(assigns) do
    assigns =
      assign(
        assigns,
        :comparison_review_links,
        HistoricalWorkflowStatusNavigationPresentation.comparison_review_links(
          assigns.workflow_context,
          assigns.dashboard_current_path
        )
      )
      |> assign(
        :failed_item_handoffs,
        HistoricalWorkflowStatusNavigationPresentation.group_failed_item_handoffs(
          assigns.workflow_context,
          assigns.dashboard_current_path
        )
      )
      |> assign(
        :replacement_recovery,
        HistoricalWorkflowReplacementRecovery.build(
          assigns.workflow_context,
          assigns.workflow_controls
        )
      )
      |> then(fn assigns ->
        assign(
          assigns,
          :closure_readiness,
          assigns.replacement_recovery.closure_readiness
        )
      end)
      |> then(fn assigns ->
        assign(
          assigns,
          :group_recovery_forms,
          HistoricalWorkflowGroupRecoveryFormPresentation.build(
            assigns.workflow_context,
            assigns.replacement_recovery
          )
        )
      end)
      |> assign(
        :group_recovery,
        HistoricalWorkflowGroupRecoveryPresentation.build(assigns.workflow_context)
      )

    ~H"""
    <div
      :if={@workflow_controls.group_summary}
      id="dashboard-historical-workflow-group-summary"
      class="rounded border border-primary/30 bg-primary/5 p-2 text-xs"
      data-historical-workflow-group-id={@workflow_context.request_group_id}
      data-historical-workflow-group-state={@workflow_context.request_group_state}
      data-historical-workflow-group-terminal={@workflow_context.request_group_terminal}
      data-historical-workflow-group-size={@workflow_context.request_group_size}
      data-historical-workflow-group-progress={@workflow_context.request_group_progress}
      data-historical-workflow-group-requested={@workflow_context.request_group_requested}
      data-historical-workflow-group-approved={@workflow_context.request_group_approved}
      data-historical-workflow-group-started={@workflow_context.request_group_started}
      data-historical-workflow-group-completed={@workflow_context.request_group_completed}
      data-historical-workflow-group-failed={@workflow_context.request_group_failed}
      data-historical-workflow-group-resolved-failed={
        @workflow_context.request_group_resolved_failed
      }
      data-historical-workflow-group-retry-resolved={
        @workflow_context.request_group_retry_resolved
      }
      data-historical-workflow-group-correction-requested={
        @workflow_context.request_group_correction_requested
      }
      data-historical-workflow-group-correction-started={
        @workflow_context.request_group_correction_started
      }
      data-historical-workflow-group-correction-completed={
        @workflow_context.request_group_correction_completed
      }
      data-historical-workflow-group-correction-superseded={
        @workflow_context.request_group_correction_superseded
      }
      data-historical-workflow-group-request-eligible={
        @workflow_context.request_group_request_eligible
      }
      data-historical-workflow-group-approve-eligible={
        @workflow_context.request_group_approve_eligible
      }
      data-historical-workflow-group-reject-eligible={
        @workflow_context.request_group_reject_eligible
      }
      data-historical-workflow-group-start-eligible={
        @workflow_context.request_group_start_eligible
      }
      data-historical-workflow-group-complete-eligible={
        @workflow_context.request_group_complete_eligible
      }
      data-historical-workflow-group-fail-eligible={
        @workflow_context.request_group_fail_eligible
      }
      data-historical-workflow-group-retryable-failed={
        @workflow_context.request_group_retryable_failed
      }
      data-historical-workflow-group-nonretryable-failed={
        @workflow_context.request_group_nonretryable_failed
      }
      data-historical-workflow-group-comparison-review-request={
        @workflow_context.comparison_review_request_event_id
      }
      data-historical-workflow-group-comparison-review-kind={
        @workflow_context.comparison_review_request_kind
      }
      data-historical-workflow-group-comparison-review-open-count={
        @workflow_context.comparison_review_open_count
      }
      data-historical-workflow-group-comparison-review-placements={
        @workflow_context.comparison_review_open_placement_ids
      }
      data-historical-workflow-group-comparison-review-workflow-kind={
        Map.get(@workflow_context, :comparison_review_workflow_kind)
      }
      data-historical-workflow-group-comparison-review-workflow-action={
        Map.get(@workflow_context, :comparison_review_workflow_action)
      }
      data-historical-workflow-group-comparison-review-workflow-selection-kind={
        Map.get(@workflow_context, :comparison_review_workflow_selection_kind)
      }
      data-historical-workflow-group-comparison-review-workflow-selection-count={
        Map.get(@workflow_context, :comparison_review_workflow_selection_count)
      }
      data-historical-workflow-group-comparison-review-primary-data-view={
        Map.get(@workflow_context, :comparison_review_primary_data_view)
      }
      data-historical-workflow-group-comparison-review-compare-data-view={
        Map.get(@workflow_context, :comparison_review_compare_data_view)
      }
      data-historical-workflow-group-handoff-summary={@group_recovery.handoff_summary}
    >
      <div class="flex items-center justify-between gap-2">
        <span class="hud-label">Group Status</span>
        <span class="font-mono">{@workflow_context.request_group_state}</span>
      </div>
      <section
        :if={
          DataLinkInspectorPanelPresentation.present_text?(
            Map.get(@workflow_context, :request_group_job_progress)
          )
        }
        id="dashboard-historical-workflow-group-job-progress"
        class="mt-2 space-y-1 rounded border border-base-300/60 bg-base-100/70 p-2"
        data-historical-workflow-group-job-progress={
          Map.get(@workflow_context, :request_group_job_progress)
        }
        data-historical-workflow-group-job-progress-queued={
          job_progress_count(@workflow_context, "queued")
        }
        data-historical-workflow-group-job-progress-running={
          job_progress_count(@workflow_context, "running")
        }
        data-historical-workflow-group-job-progress-completed={
          job_progress_count(@workflow_context, "completed")
        }
        data-historical-workflow-group-job-progress-failed={
          job_progress_count(@workflow_context, "failed")
        }
        data-historical-workflow-group-job-progress-missing={
          job_progress_count(@workflow_context, "missing")
        }
        data-historical-workflow-group-job-items={
          Map.get(@workflow_context, :request_group_job_items)
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Job Progress</span>
          <span class="font-mono text-base-content/70">
            {Map.get(@workflow_context, :request_group_job_progress)}
          </span>
        </div>
        <div class="space-y-1">
          <div
            :for={item <- @group_recovery.job_items}
            class="rounded border border-base-300/50 bg-base-200/40 px-2 py-1 font-mono text-base-content/75 break-all"
            data-historical-workflow-group-job-item={item}
          >
            {item}
          </div>
        </div>
      </section>
      <section
        :if={@group_recovery.execution_audit_entries != []}
        id="dashboard-historical-workflow-group-execution-audit"
        class="mt-2 space-y-2 rounded border border-base-300/60 bg-base-100/70 p-2"
        data-historical-workflow-group-execution-audit-count={
          Integer.to_string(length(@group_recovery.execution_audit_entries))
        }
        data-historical-workflow-group-execution-audit-summary={
          @group_recovery.execution_audit_summary
        }
        data-historical-workflow-group-execution-audit-request-group={
          Map.get(@workflow_context, :request_group_id)
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Execution Audit</span>
          <span class="font-mono text-base-content/70">
            {Integer.to_string(length(@group_recovery.execution_audit_entries))}
          </span>
        </div>
        <div class="space-y-1">
          <div
            :for={entry <- @group_recovery.execution_audit_entries}
            class="rounded border border-base-300/50 bg-base-200/40 px-2 py-1"
            data-historical-workflow-group-execution-step={entry.key}
            data-historical-workflow-group-execution-count={entry.count}
            data-historical-workflow-group-execution-detail={entry.detail}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="font-mono text-base-content">{entry.label}</span>
              <span class="badge badge-xs badge-outline font-mono">{entry.count}</span>
            </div>
            <p
              :if={DataLinkInspectorPanelPresentation.present_text?(entry.detail)}
              class="mt-1 font-mono text-base-content/65 break-all"
            >
              {entry.detail}
            </p>
          </div>
        </div>
      </section>
      <section
        :if={@comparison_review_links.review_href}
        id="dashboard-historical-workflow-review-origin"
        class="mt-2 space-y-2 rounded border border-info/40 bg-info/10 p-2"
        data-historical-workflow-review-origin-request={
          @workflow_context.comparison_review_request_event_id
        }
        data-historical-workflow-review-origin-kind={
          @workflow_context.comparison_review_request_kind
        }
        data-historical-workflow-review-origin-open-count={
          @workflow_context.comparison_review_open_count
        }
        data-historical-workflow-review-origin-placements={
          @workflow_context.comparison_review_open_placement_ids
        }
        data-historical-workflow-review-origin-workflow-kind={
          Map.get(@workflow_context, :comparison_review_workflow_kind)
        }
        data-historical-workflow-review-origin-workflow-action={
          Map.get(@workflow_context, :comparison_review_workflow_action)
        }
        data-historical-workflow-review-origin-workflow-selection-kind={
          Map.get(@workflow_context, :comparison_review_workflow_selection_kind)
        }
        data-historical-workflow-review-origin-workflow-selection-count={
          Map.get(@workflow_context, :comparison_review_workflow_selection_count)
        }
        data-historical-workflow-review-origin-primary-data-view={
          Map.get(@workflow_context, :comparison_review_primary_data_view)
        }
        data-historical-workflow-review-origin-compare-data-view={
          Map.get(@workflow_context, :comparison_review_compare_data_view)
        }
        data-historical-workflow-review-origin-placement-count={
          Integer.to_string(length(@comparison_review_links.placement_links))
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Review Origin</span>
          <.link
            patch={@comparison_review_links.review_href}
            class="inline-flex items-center gap-1 font-mono text-primary hover:text-primary-focus"
            data-historical-workflow-review-origin-link={
              @workflow_context.comparison_review_request_event_id
            }
            data-historical-workflow-review-origin-href={@comparison_review_links.review_href}
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" /> Open review
          </.link>
        </div>
        <div
          :if={@comparison_review_links.placement_links != []}
          class="flex flex-wrap gap-1"
          data-historical-workflow-review-origin-placement-count={
            Integer.to_string(length(@comparison_review_links.placement_links))
          }
        >
          <.link
            :for={link <- @comparison_review_links.placement_links}
            patch={link.href}
            class="badge badge-xs badge-outline"
            data-historical-workflow-review-origin-placement={link.placement_id}
            data-historical-workflow-review-origin-placement-href={link.href}
          >
            {link.placement_id}
          </.link>
        </div>
      </section>
      <dl class="mt-2 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1">
        <dt class="text-base-content/60">Group</dt>
        <dd class="font-mono break-all">{@workflow_context.request_group_id}</dd>
        <dt class="text-base-content/60">State</dt>
        <dd class="font-mono">{@workflow_context.request_group_state}</dd>
        <dt class="text-base-content/60">Terminal</dt>
        <dd class="font-mono">{@workflow_context.request_group_terminal}</dd>
        <dt class="text-base-content/60">Progress</dt>
        <dd class="font-mono">{@workflow_context.request_group_progress}</dd>
        <dt class="text-base-content/60">Handoff</dt>
        <dd class="font-mono break-all">{@group_recovery.handoff_summary}</dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.comparison_review_request_event_id)}
          class="text-base-content/60"
        >
          Review
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.comparison_review_request_event_id)}
          class="font-mono break-all"
        >
          {@workflow_context.comparison_review_request_event_id}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.comparison_review_open_placement_ids)}
          class="text-base-content/60"
        >
          Placements
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.comparison_review_open_placement_ids)}
          class="font-mono break-all"
        >
          {@workflow_context.comparison_review_open_placement_ids}
        </dd>
        <dt class="text-base-content/60">Items</dt>
        <dd class="font-mono">{@workflow_context.request_group_size}</dd>
        <dt class="text-base-content/60">Requested</dt>
        <dd class="font-mono">{@workflow_context.request_group_requested}</dd>
        <dt class="text-base-content/60">Approved</dt>
        <dd class="font-mono">{@workflow_context.request_group_approved}</dd>
        <dt class="text-base-content/60">Started</dt>
        <dd class="font-mono">{@workflow_context.request_group_started}</dd>
        <dt class="text-base-content/60">Completed</dt>
        <dd class="font-mono">{@workflow_context.request_group_completed}</dd>
        <dt class="text-base-content/60">Failed</dt>
        <dd class="font-mono">{@workflow_context.request_group_failed}</dd>
        <dt class="text-base-content/60">Resolved</dt>
        <dd class="font-mono">{@workflow_context.request_group_resolved_failed}</dd>
        <dt class="text-base-content/60">Retried</dt>
        <dd class="font-mono">{@workflow_context.request_group_retry_resolved}</dd>
        <dt class="text-base-content/60">Correction requested</dt>
        <dd class="font-mono">{@workflow_context.request_group_correction_requested}</dd>
        <dt class="text-base-content/60">Correction started</dt>
        <dd class="font-mono">{@workflow_context.request_group_correction_started}</dd>
        <dt class="text-base-content/60">Correction completed</dt>
        <dd class="font-mono">{@workflow_context.request_group_correction_completed}</dd>
        <dt class="text-base-content/60">Correction superseded</dt>
        <dd class="font-mono">{@workflow_context.request_group_correction_superseded}</dd>
        <dt class="text-base-content/60">Eligible approve</dt>
        <dd class="font-mono">{@workflow_context.request_group_approve_eligible}</dd>
        <dt class="text-base-content/60">Eligible start</dt>
        <dd class="font-mono">{@workflow_context.request_group_start_eligible}</dd>
        <dt class="text-base-content/60">Eligible complete</dt>
        <dd class="font-mono">{@workflow_context.request_group_complete_eligible}</dd>
        <dt class="text-base-content/60">Retryable</dt>
        <dd class="font-mono">{@workflow_context.request_group_retryable_failed}</dd>
        <dt class="text-base-content/60">Correction</dt>
        <dd class="font-mono">{@workflow_context.request_group_nonretryable_failed}</dd>
        <dt :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.request_group_failed_items)} class="text-base-content/60">
          Failed items
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.request_group_failed_items)}
          class="font-mono break-all"
        >
          {@workflow_context.request_group_failed_items}
        </dd>
      </dl>
      <section
        :if={@group_recovery.visible}
        id="dashboard-historical-workflow-group-recovery"
        class="mt-2 space-y-1 rounded border border-warning/40 bg-warning/10 p-2"
        data-historical-workflow-group-recovery-id={Map.get(@workflow_context, :request_group_id)}
        data-historical-workflow-group-recovery-failed={Map.get(@workflow_context, :request_group_failed)}
        data-historical-workflow-group-recovery-retryable={
          Map.get(@workflow_context, :request_group_retryable_failed)
        }
        data-historical-workflow-group-recovery-correction={
          Map.get(@workflow_context, :request_group_nonretryable_failed)
        }
        data-historical-workflow-group-recovery-resolved={
          Map.get(@workflow_context, :request_group_resolved_failed)
        }
        data-historical-workflow-group-recovery-retried={
          Map.get(@workflow_context, :request_group_retry_resolved)
        }
        data-historical-workflow-group-recovery-correction-requested={
          Map.get(@workflow_context, :request_group_correction_requested)
        }
        data-historical-workflow-group-recovery-retried-items={
          Map.get(@workflow_context, :request_group_retried_items)
        }
        data-historical-workflow-group-recovery-corrected-items={
          Map.get(@workflow_context, :request_group_corrected_items)
        }
        data-historical-workflow-group-recovery-correction-tasks={
          Map.get(@workflow_context, :request_group_correction_tasks)
        }
        data-historical-workflow-group-recovery-failed-item-events={
          Map.get(@workflow_context, :request_group_failed_item_events)
        }
        data-historical-workflow-group-recovery-failed-item-handoffs={
          Integer.to_string(length(@failed_item_handoffs))
        }
        data-historical-workflow-group-recovery-review-request={
          @workflow_context.comparison_review_request_event_id
        }
        data-historical-workflow-group-recovery-review-kind={
          @workflow_context.comparison_review_request_kind
        }
        data-historical-workflow-group-recovery-review-open-count={
          @workflow_context.comparison_review_open_count
        }
        data-historical-workflow-group-recovery-review-placements={
          @workflow_context.comparison_review_open_placement_ids
        }
        data-historical-workflow-group-recovery-review-workflow-kind={
          Map.get(@workflow_context, :comparison_review_workflow_kind)
        }
        data-historical-workflow-group-recovery-review-workflow-action={
          Map.get(@workflow_context, :comparison_review_workflow_action)
        }
        data-historical-workflow-group-recovery-review-workflow-selection-kind={
          Map.get(@workflow_context, :comparison_review_workflow_selection_kind)
        }
        data-historical-workflow-group-recovery-review-workflow-selection-count={
          Map.get(@workflow_context, :comparison_review_workflow_selection_count)
        }
        data-historical-workflow-group-recovery-review-primary-data-view={
          Map.get(@workflow_context, :comparison_review_primary_data_view)
        }
        data-historical-workflow-group-recovery-review-compare-data-view={
          Map.get(@workflow_context, :comparison_review_compare_data_view)
        }
        data-historical-workflow-group-recovery-next-action={
          @replacement_recovery.next_action
        }
        data-historical-workflow-group-recovery-unresolved={
          @group_recovery.unresolved
        }
        data-historical-workflow-group-recovery-correction-task-count={
          @replacement_recovery.correction_task_count
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Recovery Handoff</span>
          <span class="font-mono text-base-content/70">
            {Map.get(@workflow_context, :request_group_resolved_failed) || "0"} resolved
          </span>
        </div>
        <div
          :if={@comparison_review_links.review_href}
          id="dashboard-historical-workflow-group-recovery-review-origin"
          class="flex items-center justify-between gap-2 rounded border border-info/30 bg-base-100/60 px-2 py-1"
          data-historical-workflow-group-recovery-review-origin-request={
            @workflow_context.comparison_review_request_event_id
          }
          data-historical-workflow-group-recovery-review-origin-placement-count={
            Integer.to_string(length(@comparison_review_links.placement_links))
          }
          data-historical-workflow-group-recovery-review-workflow-kind={
            Map.get(@workflow_context, :comparison_review_workflow_kind)
          }
          data-historical-workflow-group-recovery-review-workflow-action={
            Map.get(@workflow_context, :comparison_review_workflow_action)
          }
          data-historical-workflow-group-recovery-review-workflow-selection-kind={
            Map.get(@workflow_context, :comparison_review_workflow_selection_kind)
          }
          data-historical-workflow-group-recovery-review-workflow-selection-count={
            Map.get(@workflow_context, :comparison_review_workflow_selection_count)
          }
          data-historical-workflow-group-recovery-review-primary-data-view={
            Map.get(@workflow_context, :comparison_review_primary_data_view)
          }
          data-historical-workflow-group-recovery-review-compare-data-view={
            Map.get(@workflow_context, :comparison_review_compare_data_view)
          }
        >
          <span class="hud-label">Review Origin</span>
          <.link
            patch={@comparison_review_links.review_href}
            class="inline-flex items-center gap-1 font-mono text-primary hover:text-primary-focus"
            data-historical-workflow-group-recovery-review-origin-link={
              @workflow_context.comparison_review_request_event_id
            }
            data-historical-workflow-group-recovery-review-origin-href={
              @comparison_review_links.review_href
            }
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" /> Open review
          </.link>
        </div>
        <section
          id="dashboard-historical-workflow-group-recovery-guidance"
          class="rounded border border-warning/30 bg-base-100/60 p-2"
          data-historical-workflow-group-recovery-guidance-next-action={
            @replacement_recovery.next_action
          }
          data-historical-workflow-group-recovery-guidance-unresolved={
            @group_recovery.unresolved
          }
          data-historical-workflow-group-recovery-guidance-retry-eligible={
            @replacement_recovery.retry_action.eligible
          }
          data-historical-workflow-group-recovery-guidance-retry-reason={
            @replacement_recovery.retry_action.reason
          }
          data-historical-workflow-group-recovery-guidance-retry-preview={
            @replacement_recovery.retry_action.preview
          }
          data-historical-workflow-group-recovery-guidance-retry-explanation={
            @replacement_recovery.retry_action.explanation
          }
          data-historical-workflow-group-recovery-guidance-retry-state={
            @replacement_recovery.retry_action.state
          }
          data-historical-workflow-group-recovery-guidance-retry-available-when={
            @replacement_recovery.retry_action.available_when
          }
          data-historical-workflow-group-recovery-guidance-correction-task-count={
            @replacement_recovery.correction_task_count
          }
        >
          <div class="flex items-center justify-between gap-2">
            <span class="hud-label">Recovery Guidance</span>
            <span class="font-mono text-base-content/70">
              {@replacement_recovery.next_action}
            </span>
          </div>
          <p class="mt-1 text-base-content/75">
            {@replacement_recovery.guidance}
          </p>
          <p
            :if={DataLinkInspectorPanelPresentation.present_text?(@replacement_recovery.retry_action.state)}
            class="mt-1 font-mono text-base-content/65"
          >
            {@replacement_recovery.retry_action.state}
          </p>
          <p
            :if={DataLinkInspectorPanelPresentation.present_text?(@replacement_recovery.retry_action.available_when)}
            class="mt-1 text-base-content/60"
          >
            {@replacement_recovery.retry_action.available_when}
          </p>
        </section>
        <section
          :if={@failed_item_handoffs != []}
          id="dashboard-historical-workflow-group-recovery-failed-item-handoffs"
          class="rounded border border-warning/30 bg-base-100/70 p-2"
          data-historical-workflow-group-recovery-failed-item-handoff-count={
            Integer.to_string(length(@failed_item_handoffs))
          }
        >
          <div class="flex items-center justify-between gap-2">
            <span class="hud-label">Failed Item Handoffs</span>
            <span class="font-mono text-base-content/70">
              {Integer.to_string(length(@failed_item_handoffs))}
            </span>
          </div>
          <div class="mt-2 flex flex-wrap gap-2">
            <.link
              :for={handoff <- @failed_item_handoffs}
              patch={handoff.href}
              class="btn btn-xs btn-warning btn-outline"
              data-historical-workflow-group-recovery-failed-item={handoff.event_id}
              data-historical-workflow-group-recovery-failed-item-label={handoff.label}
              data-historical-workflow-group-recovery-failed-item-run={handoff.run_id}
              data-historical-workflow-group-recovery-failed-item-recovery={
                handoff.recovery_action
              }
              data-historical-workflow-group-recovery-failed-item-retryable={handoff.retryable}
              data-historical-workflow-group-recovery-failed-item-href={handoff.href}
            >
              <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
              {handoff.label}
            </.link>
          </div>
        </section>
        <section
          id="dashboard-historical-workflow-group-recovery-execution-plan"
          class="rounded border border-warning/30 bg-base-100/70 p-2"
          data-historical-workflow-group-recovery-execution-plan-request-group={
            Map.get(@workflow_context, :request_group_id)
          }
          data-historical-workflow-group-recovery-execution-plan-next-action={
            @replacement_recovery.next_action
          }
          data-historical-workflow-group-recovery-execution-plan-retry-eligible={
            @replacement_recovery.retry_action.eligible
          }
          data-historical-workflow-group-recovery-execution-plan-retry-count={
            @replacement_recovery.retry_count
          }
          data-historical-workflow-group-recovery-execution-plan-correction-count={
            Map.get(@workflow_context, :request_group_nonretryable_failed)
          }
          data-historical-workflow-group-recovery-execution-plan-correction-task-count={
            @replacement_recovery.correction_task_count
          }
          data-historical-workflow-group-recovery-execution-plan-unresolved={
            @group_recovery.unresolved
          }
          data-historical-workflow-group-recovery-execution-plan-expected-effect={
            @replacement_recovery.expected_effect
          }
          data-historical-workflow-group-recovery-execution-plan-blockers={
            @replacement_recovery.blockers
          }
          data-historical-workflow-group-recovery-execution-plan-replacement-stage={
            @replacement_recovery.replacement_action.stage
          }
          data-historical-workflow-group-recovery-execution-plan-replacement-eligible={
            @replacement_recovery.replacement_action.eligible
          }
          data-historical-workflow-group-recovery-execution-plan-replacement-preview={
            @replacement_recovery.replacement_action.preview
          }
        >
          <div class="flex items-center justify-between gap-2">
            <span class="hud-label">Recovery Execution Plan</span>
            <span class="font-mono text-base-content/70">
              {@replacement_recovery.retry_count} retry
            </span>
          </div>
          <dl class="mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
            <dt class="text-base-content/60">Next action</dt>
            <dd class="font-mono break-all">
              {@replacement_recovery.next_action}
            </dd>
            <dt class="text-base-content/60">Retry batch</dt>
            <dd class="font-mono">
              {@replacement_recovery.retry_count}
            </dd>
            <dt class="text-base-content/60">Corrections</dt>
            <dd class="font-mono">
              {Map.get(@workflow_context, :request_group_nonretryable_failed) || "0"}
            </dd>
            <dt class="text-base-content/60">Expected</dt>
            <dd class="break-words">
              {@replacement_recovery.expected_effect}
            </dd>
            <dt
              :if={
                DataLinkInspectorPanelPresentation.present_text?(
                  @replacement_recovery.blockers
                )
              }
              class="text-base-content/60"
            >
              Blocked by
            </dt>
            <dd
              :if={
                DataLinkInspectorPanelPresentation.present_text?(
                  @replacement_recovery.blockers
                )
              }
              class="break-words text-base-content/75"
            >
              {@replacement_recovery.blockers}
            </dd>
          </dl>
          <section
            :if={@replacement_recovery.entries != []}
            id="dashboard-historical-workflow-group-recovery-remaining-work"
            class="mt-2 space-y-2 rounded border border-primary/30 bg-primary/5 p-2"
            data-historical-workflow-group-recovery-remaining-work-count={
              @replacement_recovery.total_count
            }
            data-historical-workflow-group-recovery-remaining-work-pending-count={
              @replacement_recovery.pending_count
            }
            data-historical-workflow-group-recovery-remaining-work-completed-count={
              @replacement_recovery.completed_count
            }
            data-historical-workflow-group-recovery-remaining-work-next-actions={
              @replacement_recovery.next_actions
            }
            data-historical-workflow-group-recovery-remaining-work-pending-runs={
              @replacement_recovery.pending_runs
            }
            data-historical-workflow-group-recovery-remaining-work-summary={
              @replacement_recovery.work_summary
            }
            data-historical-workflow-group-recovery-remaining-work-job-summary={
              @replacement_recovery.job_summary
            }
            data-historical-workflow-group-recovery-remaining-work-active-jobs={
              @replacement_recovery.active_job_count
            }
            data-historical-workflow-group-recovery-remaining-work-active-runs={
              @replacement_recovery.active_run_ids
            }
            data-historical-workflow-group-recovery-remaining-work-active-summary={
              @replacement_recovery.active_summary
            }
            data-historical-workflow-group-recovery-remaining-work-stale-jobs={
              @replacement_recovery.stale_job_count
            }
            data-historical-workflow-group-recovery-remaining-work-stale-runs={
              @replacement_recovery.stale_run_ids
            }
            data-historical-workflow-group-recovery-remaining-work-stale-summary={
              @replacement_recovery.stale_summary
            }
            data-historical-workflow-group-recovery-remaining-work-blocked-jobs={
              @replacement_recovery.blocked_job_count
            }
            data-historical-workflow-group-recovery-remaining-work-missing-jobs={
              @replacement_recovery.missing_job_count
            }
            data-historical-workflow-group-recovery-remaining-work-missing-runs={
              @replacement_recovery.missing_run_ids
            }
          >
            <div class="flex items-center justify-between gap-2">
              <span class="hud-label">Replacement Work</span>
              <span class="font-mono text-base-content/70">
                {@replacement_recovery.pending_count} pending
              </span>
            </div>
            <div class="space-y-1">
              <div
                :for={entry <- @replacement_recovery.entries}
                class="rounded border border-base-300/60 bg-base-100/70 px-2 py-1"
                data-historical-workflow-group-recovery-remaining-work-item={entry.raw}
                data-historical-workflow-group-recovery-remaining-work-source={entry.source}
                data-historical-workflow-group-recovery-remaining-work-replacement-run={
                  entry.replacement_run
                }
                data-historical-workflow-group-recovery-remaining-work-stage={entry.stage}
                data-historical-workflow-group-recovery-remaining-work-next-action={
                  entry.next_action
                }
                data-historical-workflow-group-recovery-remaining-work-status={entry.status}
                data-historical-workflow-group-recovery-remaining-work-job-status={
                  entry.job_status
                }
                data-historical-workflow-group-recovery-remaining-work-job-id={entry.job_id}
                data-historical-workflow-group-recovery-remaining-work-event-id={entry.event_id}
                data-historical-workflow-group-recovery-remaining-work-job-started={
                  entry.job_started_at
                }
                data-historical-workflow-group-recovery-remaining-work-job-completed={
                  entry.job_completed_at
                }
                data-historical-workflow-group-recovery-remaining-work-job-age-state={
                  entry.job_age_state
                }
                data-historical-workflow-group-recovery-remaining-work-job-action={
                  entry.job_action
                }
                data-historical-workflow-group-recovery-remaining-work-job-item={
                  entry.job_item
                }
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="min-w-0 truncate font-mono">{entry.replacement_run}</span>
                  <span class="badge badge-xs badge-outline">{entry.status}</span>
                </div>
                <div class="mt-1 flex flex-wrap gap-2 text-[0.68rem] text-base-content/65">
                  <span class="font-mono">{entry.stage}</span>
                  <span class="font-mono">{entry.next_action}</span>
                  <span class="min-w-0 break-all">{entry.source}</span>
                </div>
                <div
                  :if={present_text?(entry.job_status)}
                  class="mt-1 flex flex-wrap gap-2 text-[0.68rem] text-base-content/65"
                >
                  <span class="font-mono">{entry.job_status}</span>
                  <span class="font-mono">{entry.job_id}</span>
                  <span class="font-mono">{entry.job_action}</span>
                </div>
                <button
                  :if={entry.job_action == "inspect_stale_replacement_job"}
                  id={"dashboard-historical-workflow-stale-replacement-inspect-#{entry.replacement_run}"}
                  type="button"
                  class="btn btn-xs btn-warning btn-outline mt-1"
                  phx-click="inspect_stale_historical_workflow_replacement_job"
                  phx-value-job-id={entry.job_id}
                  phx-value-event-id={entry.event_id}
                  phx-value-replacement-run-id={entry.replacement_run}
                  data-workflow-action-id="inspect_stale_replacement_job"
                  data-workflow-action-scope="replacement_job"
                  data-workflow-action-replacement-run={entry.replacement_run}
                  data-workflow-action-job-id={entry.job_id}
                  data-workflow-action-event-id={entry.event_id}
                  data-workflow-action-job-started={entry.job_started_at}
                >
                  <.icon name="hero-magnifying-glass" class="size-3" /> Inspect stale job
                </button>
                <button
                  :if={entry.job_action == "inspect_stale_replacement_job"}
                  id={"dashboard-historical-workflow-stale-replacement-requeue-#{entry.replacement_run}"}
                  type="button"
                  class="btn btn-xs btn-warning mt-1"
                  phx-click="requeue_stale_historical_workflow_replacement_job"
                  phx-value-job-id={entry.job_id}
                  phx-value-event-id={entry.event_id}
                  phx-value-replacement-run-id={entry.replacement_run}
                  data-workflow-action-id="requeue_stale_replacement_job"
                  data-workflow-action-scope="replacement_job"
                  data-workflow-action-replacement-run={entry.replacement_run}
                  data-workflow-action-job-id={entry.job_id}
                  data-workflow-action-event-id={entry.event_id}
                  data-workflow-action-job-started={entry.job_started_at}
                >
                  <.icon name="hero-arrow-path" class="size-3" /> Requeue stale job
                </button>
                <button
                  :if={entry.job_action == "inspect_missing_replacement_job"}
                  id={"dashboard-historical-workflow-missing-replacement-inspect-#{entry.replacement_run}"}
                  type="button"
                  class="btn btn-xs btn-warning btn-outline mt-1"
                  phx-click="inspect_missing_historical_workflow_replacement_job"
                  phx-value-request-group-id={@workflow_context.request_group_id}
                  phx-value-replacement-run-id={entry.replacement_run}
                  data-workflow-action-id="inspect_missing_replacement_job"
                  data-workflow-action-scope="replacement_job"
                  data-workflow-action-request-group={@workflow_context.request_group_id}
                  data-workflow-action-replacement-run={entry.replacement_run}
                  data-workflow-action-source={entry.source}
                  data-workflow-action-stage={entry.stage}
                  data-workflow-action-next-action={entry.next_action}
                >
                  <.icon name="hero-magnifying-glass" class="size-3" /> Inspect missing job
                </button>
                <button
                  :if={
                    entry.job_action == "inspect_failed_replacement_job" and
                      @replacement_recovery.retry_action.present and present_text?(entry.job_id) and
                      present_text?(entry.event_id)
                  }
                  id={"dashboard-historical-workflow-failed-replacement-retry-#{entry.replacement_run}"}
                  type="button"
                  class="btn btn-xs btn-error btn-outline mt-1"
                  phx-click="retry_historical_workflow_job"
                  phx-value-job-id={entry.job_id}
                  phx-value-event-id={entry.event_id}
                  phx-value-replacement-run-id={entry.replacement_run}
                  data-workflow-action-id="retry_failed_replacement_job"
                  data-workflow-action-scope="replacement_job"
                  data-workflow-action-replacement-run={entry.replacement_run}
                  data-workflow-action-job-id={entry.job_id}
                  data-workflow-action-event-id={entry.event_id}
                  data-workflow-action-reason={@replacement_recovery.retry_action.reason}
                  data-workflow-action-preview={@replacement_recovery.retry_action.preview}
                >
                  <.icon name="hero-arrow-path" class="size-3" /> Retry failed job
                </button>
              </div>
            </div>
            <section
              :if={@replacement_recovery.active_job_count != "0"}
              id="dashboard-historical-workflow-group-recovery-active-replacement-jobs"
              class="rounded border border-info/40 bg-info/10 p-2"
              data-historical-workflow-group-recovery-active-replacement-job-count={
                @replacement_recovery.active_job_count
              }
              data-historical-workflow-group-recovery-active-replacement-runs={
                @replacement_recovery.active_run_ids
              }
              data-historical-workflow-group-recovery-active-replacement-summary={
                @replacement_recovery.active_summary
              }
            >
              <div class="flex items-center justify-between gap-2">
                <span class="hud-label">Active Replacement Jobs</span>
                <span class="font-mono text-base-content/70">
                  {@replacement_recovery.active_job_count}
                </span>
              </div>
              <p class="mt-1 font-mono text-[0.68rem] text-base-content/70 break-all">
                {@replacement_recovery.active_summary}
              </p>
            </section>
            <section
              :if={@replacement_recovery.stale_job_count != "0"}
              id="dashboard-historical-workflow-group-recovery-stale-replacement-jobs"
              class="rounded border border-warning/40 bg-warning/10 p-2"
              data-historical-workflow-group-recovery-stale-replacement-job-count={
                @replacement_recovery.stale_job_count
              }
              data-historical-workflow-group-recovery-stale-replacement-runs={
                @replacement_recovery.stale_run_ids
              }
              data-historical-workflow-group-recovery-stale-replacement-summary={
                @replacement_recovery.stale_summary
              }
            >
              <div class="flex items-center justify-between gap-2">
                <span class="hud-label">Stale Replacement Jobs</span>
                <span class="font-mono text-base-content/70">
                  {@replacement_recovery.stale_job_count}
                </span>
              </div>
              <p class="mt-1 font-mono text-[0.68rem] text-base-content/70 break-all">
                {@replacement_recovery.stale_summary}
              </p>
            </section>
            <section
              :if={@replacement_recovery.missing_job_count != "0"}
              id="dashboard-historical-workflow-group-recovery-missing-replacement-jobs"
              class="rounded border border-warning/40 bg-warning/10 p-2"
              data-historical-workflow-group-recovery-missing-replacement-job-count={
                @replacement_recovery.missing_job_count
              }
              data-historical-workflow-group-recovery-missing-replacement-runs={
                @replacement_recovery.missing_run_ids
              }
              data-historical-workflow-group-recovery-missing-replacement-summary={
                @replacement_recovery.missing_summary
              }
            >
              <div class="flex items-center justify-between gap-2">
                <span class="hud-label">Missing Replacement Jobs</span>
                <span class="font-mono text-base-content/70">
                  {@replacement_recovery.missing_job_count}
                </span>
              </div>
              <p class="mt-1 font-mono text-[0.68rem] text-base-content/70 break-all">
                {@replacement_recovery.missing_summary}
              </p>
            </section>
            <button
              :if={
                @replacement_recovery.retry_action.present and
                  @replacement_recovery.failed_job_count != "0"
              }
              id="dashboard-historical-workflow-group-retry-failed-replacements"
              type="button"
              class="btn btn-xs btn-error btn-outline w-full justify-between gap-2"
              phx-click="retry_historical_workflow_group_failed_jobs"
              phx-value-request-group-id={@workflow_context.request_group_id}
              phx-value-event-id={@workflow_context.event_id}
              phx-value-retry-run-ids={
                @replacement_recovery.failed_run_ids
              }
              data-workflow-action-id={@replacement_recovery.retry_action.id}
              data-workflow-action-scope="replacement_jobs"
              data-workflow-action-eligible={@replacement_recovery.retry_action.eligible}
              data-workflow-action-eligible-count={
                @replacement_recovery.failed_job_count
              }
              data-workflow-action-retry-run-ids={
                @replacement_recovery.failed_run_ids
              }
              data-workflow-action-reason={@replacement_recovery.retry_action.reason}
              data-workflow-action-preview={@replacement_recovery.retry_action.preview}
              data-confirm="Retry failed corrected replacement jobs in this request group?"
            >
              <span class="flex min-w-0 items-center gap-1">
                <.icon name="hero-arrow-path" class="size-3" /> Retry failed replacements
              </span>
              <span class="font-mono">
                {@replacement_recovery.failed_job_count}
              </span>
            </button>
          </section>
          <section
            id="dashboard-historical-workflow-group-recovery-closure-readiness"
            class="mt-2 space-y-2 rounded border border-info/30 bg-info/5 p-2"
            data-historical-workflow-group-recovery-closure-status={@closure_readiness.status}
            data-historical-workflow-group-recovery-closure-action={@closure_readiness.action}
            data-historical-workflow-group-recovery-closure-actions={@closure_readiness.actions}
            data-historical-workflow-group-recovery-closure-unresolved={
              @closure_readiness.unresolved
            }
            data-historical-workflow-group-recovery-closure-pending-replacements={
              @closure_readiness.pending_replacements
            }
            data-historical-workflow-group-recovery-closure-completed-replacements={
              @closure_readiness.completed_replacements
            }
            data-historical-workflow-group-recovery-closure-active-jobs={
              @closure_readiness.active_jobs
            }
            data-historical-workflow-group-recovery-closure-blocked-jobs={
              @closure_readiness.blocked_jobs
            }
            data-historical-workflow-group-recovery-closure-failed-jobs={
              @closure_readiness.failed_jobs
            }
            data-historical-workflow-group-recovery-closure-failed-runs={
              @closure_readiness.failed_runs
            }
            data-historical-workflow-group-recovery-closure-missing-jobs={
              @closure_readiness.missing_jobs
            }
            data-historical-workflow-group-recovery-closure-missing-runs={
              @closure_readiness.missing_runs
            }
            data-historical-workflow-group-recovery-closure-stale-jobs={
              @closure_readiness.stale_jobs
            }
            data-historical-workflow-group-recovery-closure-stale-runs={
              @closure_readiness.stale_runs
            }
            data-historical-workflow-group-recovery-closure-complete-eligible={
              @closure_readiness.complete_eligible
            }
            data-historical-workflow-group-recovery-closure-summary={@closure_readiness.summary}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="hud-label">Closure Readiness</span>
              <span class="font-mono text-base-content/70">
                {@closure_readiness.status}
              </span>
            </div>
            <dl class="grid grid-cols-[8rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
              <dt class="text-base-content/60">Action</dt>
              <dd class="font-mono break-all">{@closure_readiness.action}</dd>
              <dt class="text-base-content/60">Action queue</dt>
              <dd class="font-mono break-all">{@closure_readiness.actions}</dd>
              <dt class="text-base-content/60">Unresolved</dt>
              <dd class="font-mono">{@closure_readiness.unresolved}</dd>
              <dt class="text-base-content/60">Replacements</dt>
              <dd class="font-mono">
                {@closure_readiness.pending_replacements} pending / {@closure_readiness.completed_replacements} complete
              </dd>
              <dt class="text-base-content/60">Jobs</dt>
              <dd class="font-mono">
                {@closure_readiness.active_jobs} active / {@closure_readiness.blocked_jobs} blocked / {@closure_readiness.failed_jobs} failed / {@closure_readiness.missing_jobs} missing / {@closure_readiness.stale_jobs} stale
              </dd>
            </dl>
            <.form
              :if={
                @closure_readiness.status == "ready_to_complete" and
                  @group_recovery_forms.completion.present
              }
              for={%{}}
              as={:historical_workflow_group}
              id={@group_recovery_forms.completion.id}
              phx-submit={@group_recovery_forms.completion.submit_event}
              class="space-y-2 rounded border border-success/30 bg-success/5 p-2"
              data-historical-workflow-group-recovery-complete-request-group={
                @group_recovery_forms.completion.request_group_id
              }
              data-historical-workflow-group-recovery-complete-stage={
                @group_recovery_forms.completion.stage
              }
              data-historical-workflow-group-recovery-complete-eligible={
                @group_recovery_forms.completion.eligible
              }
              data-historical-workflow-group-recovery-complete-count={
                @group_recovery_forms.completion.count
              }
              data-historical-workflow-group-recovery-complete-reason={
                @group_recovery_forms.completion.reason
              }
              data-historical-workflow-group-recovery-complete-preview={
                @group_recovery_forms.completion.preview
              }
            >
              <input
                :for={field <- @group_recovery_forms.completion.hidden_fields}
                type="hidden"
                name={field.name}
                value={field.value}
              />
              <button
                id="dashboard-historical-workflow-group-recovery-complete"
                type="submit"
                name="historical_workflow_group[stage]"
                value={@group_recovery_forms.completion.stage}
                disabled={@group_recovery_forms.completion.disabled_bool}
                class={[
                  "btn btn-xs btn-success btn-outline w-full justify-between gap-2",
                  @group_recovery_forms.completion.disabled_bool && "btn-disabled"
                ]}
                data-workflow-action-id={@group_recovery_forms.completion.action_id}
                data-workflow-action-stage={@group_recovery_forms.completion.stage}
                data-workflow-action-eligible={@group_recovery_forms.completion.eligible}
                data-workflow-action-eligible-count={@group_recovery_forms.completion.count}
                data-workflow-action-reason={@group_recovery_forms.completion.reason}
                data-workflow-action-preview={@group_recovery_forms.completion.preview}
              >
                <span class="flex min-w-0 items-center gap-1">
                  <.icon name="hero-flag" class="h-3.5 w-3.5" /> Complete group
                </span>
                <span class="font-mono">{@group_recovery_forms.completion.count}</span>
              </button>
            </.form>
          </section>
          <button
            :if={@replacement_recovery.retry_action.present}
            id="dashboard-historical-workflow-group-retry-failed"
            type="button"
            class="btn btn-xs btn-error btn-outline mt-2 w-full justify-start"
            phx-click="retry_historical_workflow_group_failed_jobs"
            phx-value-request-group-id={@workflow_context.request_group_id}
            phx-value-event-id={@workflow_context.event_id}
            data-workflow-action-id={@replacement_recovery.retry_action.id}
            data-workflow-action-eligible={@replacement_recovery.retry_action.eligible}
            data-workflow-action-eligible-count={
              @replacement_recovery.retry_count
            }
            data-workflow-action-reason={@replacement_recovery.retry_action.reason}
            data-workflow-action-preview={@replacement_recovery.retry_action.preview}
            data-workflow-action-expected-effect={
              @replacement_recovery.expected_effect
            }
            data-confirm="Retry every retryable failed job in this request group?"
          >
            <.icon name="hero-arrow-path" class="size-3" /> Retry failed items
          </button>
          <.form
            :if={@group_recovery_forms.replacement_advancement.present}
            for={%{}}
            as={:historical_workflow_group}
            id={@group_recovery_forms.replacement_advancement.id}
            phx-submit={@group_recovery_forms.replacement_advancement.submit_event}
            class="mt-2 space-y-2 rounded border border-primary/30 bg-primary/5 p-2"
            data-historical-workflow-group-recovery-advance-request-group={
              @group_recovery_forms.replacement_advancement.request_group_id
            }
            data-historical-workflow-group-recovery-advance-stage={
              @group_recovery_forms.replacement_advancement.stage
            }
            data-historical-workflow-group-recovery-advance-eligible={
              @group_recovery_forms.replacement_advancement.eligible
            }
            data-historical-workflow-group-recovery-advance-count={
              @group_recovery_forms.replacement_advancement.count
            }
            data-historical-workflow-group-recovery-advance-reason={
              @group_recovery_forms.replacement_advancement.reason
            }
            data-historical-workflow-group-recovery-advance-preview={
              @group_recovery_forms.replacement_advancement.preview
            }
            data-historical-workflow-group-recovery-advance-correction-tasks={
              @group_recovery_forms.replacement_advancement.correction_tasks
            }
          >
            <input
              :for={field <- @group_recovery_forms.replacement_advancement.hidden_fields}
              type="hidden"
              name={field.name}
              value={field.value}
            />
            <div class="flex items-center justify-between gap-2">
              <span class="hud-label">Replacement Advancement</span>
              <span class="font-mono text-base-content/70">
                {@group_recovery_forms.replacement_advancement.count}
              </span>
            </div>
            <p class="text-base-content/75">
              {@group_recovery_forms.replacement_advancement.preview}
            </p>
            <button
              id="dashboard-historical-workflow-group-recovery-advance-corrected"
              type="submit"
              name="historical_workflow_group[stage]"
              value={@group_recovery_forms.replacement_advancement.stage}
              disabled={@group_recovery_forms.replacement_advancement.disabled_bool}
              class={[
                "btn btn-xs btn-primary btn-outline w-full justify-between gap-2",
                @group_recovery_forms.replacement_advancement.disabled_bool && "btn-disabled"
              ]}
              data-workflow-action-id={@group_recovery_forms.replacement_advancement.action_id}
              data-workflow-action-eligible={@group_recovery_forms.replacement_advancement.eligible}
              data-workflow-action-eligible-count={
                @group_recovery_forms.replacement_advancement.count
              }
              data-workflow-action-stage={@group_recovery_forms.replacement_advancement.stage}
              data-workflow-action-reason={@group_recovery_forms.replacement_advancement.reason}
              data-workflow-action-preview={@group_recovery_forms.replacement_advancement.preview}
              data-workflow-action-correction-tasks={
                @group_recovery_forms.replacement_advancement.correction_tasks
              }
            >
              <span class="flex min-w-0 items-center gap-1">
                <.icon name="hero-forward" class="h-3.5 w-3.5" /> Advance replacements
              </span>
              <span class="font-mono">{@group_recovery_forms.replacement_advancement.count}</span>
            </button>
          </.form>
        </section>
        <dl class="grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 gap-y-1">
          <dt class="text-base-content/60">Retryable</dt>
          <dd class="font-mono">{Map.get(@workflow_context, :request_group_retryable_failed)}</dd>
          <dt class="text-base-content/60">Correction</dt>
          <dd class="font-mono">
            {Map.get(@workflow_context, :request_group_nonretryable_failed)}
          </dd>
          <dt class="text-base-content/60">Retried</dt>
          <dd class="font-mono">{Map.get(@workflow_context, :request_group_retry_resolved)}</dd>
          <dt class="text-base-content/60">Corrected</dt>
          <dd class="font-mono">
            {Map.get(@workflow_context, :request_group_correction_requested)}
          </dd>
          <dt
            :if={DataLinkInspectorPanelPresentation.present_text?(Map.get(@workflow_context, :request_group_failed_items))}
            class="text-base-content/60"
          >
            Items
          </dt>
          <dd
            :if={DataLinkInspectorPanelPresentation.present_text?(Map.get(@workflow_context, :request_group_failed_items))}
            class="font-mono break-all"
          >
            {Map.get(@workflow_context, :request_group_failed_items)}
          </dd>
        </dl>
        <div
          :if={DataLinkInspectorPanelPresentation.present_text?(Map.get(@workflow_context, :request_group_retried_items))}
          class="space-y-1"
          data-historical-workflow-group-retried-items={
            Map.get(@workflow_context, :request_group_retried_items)
          }
        >
          <span class="hud-label">Retried Items</span>
          <div
            :for={item <- @group_recovery.retried_items}
            class="rounded border border-base-300/50 bg-base-100/60 px-2 py-1 font-mono text-base-content/75 break-all"
            data-historical-workflow-group-retried-item={item}
          >
            {item}
          </div>
        </div>
        <div
          :if={DataLinkInspectorPanelPresentation.present_text?(Map.get(@workflow_context, :request_group_corrected_items))}
          class="space-y-1"
          data-historical-workflow-group-corrected-items={
            Map.get(@workflow_context, :request_group_corrected_items)
          }
        >
          <span class="hud-label">Corrected Items</span>
          <div
            :for={item <- @group_recovery.corrected_items}
            class="rounded border border-base-300/50 bg-base-100/60 px-2 py-1 font-mono text-base-content/75 break-all"
            data-historical-workflow-group-corrected-item={item}
          >
            {item}
          </div>
        </div>
        <div
          :if={DataLinkInspectorPanelPresentation.present_text?(Map.get(@workflow_context, :request_group_correction_tasks))}
          class="space-y-1"
          data-historical-workflow-group-correction-tasks={
            Map.get(@workflow_context, :request_group_correction_tasks)
          }
        >
          <span class="hud-label">Correction Tasks</span>
          <div
            :for={item <- @group_recovery.correction_task_items}
            class="rounded border border-primary/30 bg-primary/5 px-2 py-1 font-mono text-base-content/80 break-all"
            data-historical-workflow-group-correction-task={item}
          >
            {item}
          </div>
        </div>
        <p class="text-base-content/70">
          Retryable failures can be requeued from this group. Non-retryable failures require a corrected workflow request from the failed item.
        </p>
      </section>
    </div>
    """
  end

  defp job_progress_count(workflow_context, status) do
    workflow_context
    |> Map.get(:request_group_job_progress)
    |> job_progress_counts()
    |> Map.get(status, 0)
    |> Integer.to_string()
  end

  defp job_progress_counts(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, fn status_count, counts ->
      case status_count |> String.trim() |> String.split(" ", trim: true) do
        [status, count] ->
          Map.put(counts, status, parsed_count(count))

        _other ->
          counts
      end
    end)
  end

  defp job_progress_counts(_value), do: %{}

  defp parsed_count(value) do
    case Integer.parse(to_string(value)) do
      {count, ""} -> count
      _other -> 0
    end
  end

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false
end
