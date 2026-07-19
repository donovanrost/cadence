defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowReplacementStatusComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :workflow_context, :map, required: true
  attr :replacement_recovery, :map, required: true
  attr :closure_readiness, :map, required: true
  attr :group_recovery_forms, :map, required: true

  def replacement_status(assigns) do
    ~H"""
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

    """
  end

  defp present_text?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_text?(_value), do: false
end
