defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobRecoveryPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true
  attr :dashboard_current_path, :string, default: nil

  def job_status(assigns) do
    assigns =
      assign(
        assigns,
        :comparison_review_links,
        HistoricalWorkflowStatusNavigationPresentation.comparison_review_links(
          assigns.workflow_context,
          assigns.dashboard_current_path
        )
      )

    assigns =
      assign(
        assigns,
        :job_recovery,
        HistoricalWorkflowJobRecoveryPresentation.build(
          assigns.workflow_context,
          assigns.workflow_controls
        )
      )

    ~H"""
    <div
      :if={@workflow_controls.job_status}
      id="dashboard-historical-workflow-job-status"
      class={[
        "rounded border p-2 text-xs",
        @workflow_controls.job_status_class
      ]}
      data-historical-workflow-job-id={@workflow_context.job_id}
      data-historical-workflow-job-status={@workflow_context.job_status}
      data-historical-workflow-job-comparison-review-request={
        @workflow_context.comparison_review_request_event_id
      }
      data-historical-workflow-job-comparison-review-kind={
        @workflow_context.comparison_review_request_kind
      }
      data-historical-workflow-job-comparison-review-open-count={
        @workflow_context.comparison_review_open_count
      }
      data-historical-workflow-job-comparison-review-placements={
        @workflow_context.comparison_review_open_placement_ids
      }
      data-historical-workflow-job-next-action={
        @job_recovery.next_action
      }
    >
      <div class="flex items-center justify-between gap-2">
        <span class="hud-label">Workflow Job</span>
        <span class="font-mono uppercase tracking-normal">{@workflow_context.job_status}</span>
      </div>
      <section
        id="dashboard-historical-workflow-job-guidance"
        class="mt-2 rounded border border-base-300/60 bg-base-100/70 p-2"
        data-historical-workflow-job-guidance-next-action={
          @job_recovery.next_action
        }
        data-historical-workflow-job-guidance-retry-eligible={
          @job_recovery.retry.eligible
        }
        data-historical-workflow-job-guidance-retry-reason={
          @job_recovery.retry.reason
        }
        data-historical-workflow-job-guidance-retry-preview={
          @job_recovery.retry.preview
        }
        data-historical-workflow-job-guidance-retry-explanation={
          @job_recovery.retry.explanation
        }
        data-historical-workflow-job-guidance-retry-state={
          @job_recovery.retry.state
        }
        data-historical-workflow-job-guidance-retry-available-when={
          @job_recovery.retry.available_when
        }
        data-historical-workflow-job-guidance-correction-eligible={
          @job_recovery.correction.eligible
        }
        data-historical-workflow-job-guidance-correction-reason={
          @job_recovery.correction.reason
        }
        data-historical-workflow-job-guidance-correction-preview={
          @job_recovery.correction.preview
        }
        data-historical-workflow-job-guidance-correction-explanation={
          @job_recovery.correction.explanation
        }
        data-historical-workflow-job-guidance-correction-state={
          @job_recovery.correction.state
        }
        data-historical-workflow-job-guidance-correction-available-when={
          @job_recovery.correction.available_when
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Job Guidance</span>
          <span class="font-mono text-base-content/70">
            {@job_recovery.next_action}
          </span>
        </div>
        <p class="mt-1 text-base-content/75">
          {@job_recovery.guidance}
        </p>
        <p
          :if={DataLinkInspectorPanelPresentation.present_text?(@job_recovery.policy_state)}
          class="mt-1 font-mono text-base-content/65"
        >
          {@job_recovery.policy_state}
        </p>
        <p
          :if={DataLinkInspectorPanelPresentation.present_text?(@job_recovery.available_when)}
          class="mt-1 text-base-content/60"
        >
          {@job_recovery.available_when}
        </p>
      </section>
      <section
        :if={@comparison_review_links.review_href}
        id="dashboard-historical-workflow-job-review-origin"
        class="mt-2 space-y-2 rounded border border-info/40 bg-info/10 p-2"
        data-historical-workflow-job-review-origin-request={
          @workflow_context.comparison_review_request_event_id
        }
        data-historical-workflow-job-review-origin-kind={
          @workflow_context.comparison_review_request_kind
        }
        data-historical-workflow-job-review-origin-open-count={
          @workflow_context.comparison_review_open_count
        }
        data-historical-workflow-job-review-origin-placements={
          @workflow_context.comparison_review_open_placement_ids
        }
        data-historical-workflow-job-review-origin-workflow-kind={
          Map.get(@workflow_context, :comparison_review_workflow_kind)
        }
        data-historical-workflow-job-review-origin-workflow-action={
          Map.get(@workflow_context, :comparison_review_workflow_action)
        }
        data-historical-workflow-job-review-origin-workflow-selection-kind={
          Map.get(@workflow_context, :comparison_review_workflow_selection_kind)
        }
        data-historical-workflow-job-review-origin-workflow-selection-count={
          Map.get(@workflow_context, :comparison_review_workflow_selection_count)
        }
        data-historical-workflow-job-review-origin-primary-data-view={
          Map.get(@workflow_context, :comparison_review_primary_data_view)
        }
        data-historical-workflow-job-review-origin-compare-data-view={
          Map.get(@workflow_context, :comparison_review_compare_data_view)
        }
        data-historical-workflow-job-review-origin-placement-count={
          Integer.to_string(length(@comparison_review_links.placement_links))
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Review Origin</span>
          <.link
            patch={@comparison_review_links.review_href}
            class="inline-flex items-center gap-1 font-mono text-primary hover:text-primary-focus"
            data-historical-workflow-job-review-origin-link={
              @workflow_context.comparison_review_request_event_id
            }
            data-historical-workflow-job-review-origin-href={
              @comparison_review_links.review_href
            }
          >
            <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" /> Open review
          </.link>
        </div>
        <div
          :if={@comparison_review_links.placement_links != []}
          class="flex flex-wrap gap-1"
          data-historical-workflow-job-review-origin-placement-count={
            Integer.to_string(length(@comparison_review_links.placement_links))
          }
        >
          <.link
            :for={link <- @comparison_review_links.placement_links}
            patch={link.href}
            class="badge badge-xs badge-outline"
            data-historical-workflow-job-review-origin-placement={link.placement_id}
            data-historical-workflow-job-review-origin-placement-href={link.href}
          >
            {link.placement_id}
          </.link>
        </div>
      </section>
      <div class="mt-1 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1">
        <span class="text-base-content/60">Job</span>
        <span class="font-mono break-all">{@workflow_context.job_id}</span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.job_attempts)} class="text-base-content/60">
          Attempts
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.job_attempts)} class="font-mono">
          {@workflow_context.job_attempts}
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.job_failure)} class="text-base-content/60">
          Failure
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.job_failure)} class="font-mono break-all">
          {@workflow_context.job_failure}
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.failure_code)} class="text-base-content/60">
          Failure code
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.failure_code)} class="font-mono break-all">
          {@workflow_context.failure_code}
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.retryable)} class="text-base-content/60">
          Retryable
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.retryable)} class="font-mono">
          {@workflow_context.retryable}
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.recovery_action)} class="text-base-content/60">
          Recovery
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.recovery_action)} class="font-mono break-all">
          {@workflow_context.recovery_action}
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.retry_blockers)} class="text-base-content/60">
          Blockers
        </span>
        <span :if={DataLinkInspectorPanelPresentation.present_text?(@workflow_context.retry_blockers)} class="font-mono break-all">
          {@workflow_context.retry_blockers}
        </span>
      </div>
      <button
        :if={@job_recovery.retry_button.present}
        id="dashboard-historical-workflow-retry-job"
        type="button"
        class="btn btn-xs btn-error btn-outline mt-2"
        phx-click="retry_historical_workflow_job"
        phx-value-job-id={@workflow_context.job_id}
        phx-value-event-id={@workflow_context.event_id}
        data-workflow-action-id={@job_recovery.retry_button.id}
        data-workflow-action-eligible={@job_recovery.retry_button.eligible}
        data-workflow-action-reason={@job_recovery.retry_button.reason}
        data-workflow-action-preview={@job_recovery.retry_button.preview}
      >
        <.icon name="hero-arrow-path" class="size-3" /> Retry job
      </button>
    </div>
    """
  end
end
