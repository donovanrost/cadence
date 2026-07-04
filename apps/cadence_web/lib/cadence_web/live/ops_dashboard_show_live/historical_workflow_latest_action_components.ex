defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  attr :latest_action_outcome, :map, default: nil
  attr :dashboard_current_path, :string, default: nil

  def latest_action(assigns) do
    assigns =
      assign(
        assigns,
        :latest_action_handoffs,
        HistoricalWorkflowStatusNavigationPresentation.latest_action_handoffs(
          assigns.latest_action_outcome,
          assigns.dashboard_current_path
        )
      )

    ~H"""
    <div
      :if={@latest_action_outcome}
      id="dashboard-historical-workflow-latest-action"
      class={[
        "rounded border p-2 text-xs",
        @latest_action_outcome.class
      ]}
      data-workflow-latest-action={@latest_action_outcome.action}
      data-workflow-latest-action-status={@latest_action_outcome.status}
      data-workflow-latest-action-reason={@latest_action_outcome.reason}
      data-workflow-latest-action-stage={@latest_action_outcome.stage}
      data-workflow-latest-action-job-id={@latest_action_outcome.job_id}
      data-workflow-latest-action-count={@latest_action_outcome.count}
      data-workflow-latest-action-retried={@latest_action_outcome.retried}
      data-workflow-latest-action-retry-nonretryable={
        @latest_action_outcome.retry_nonretryable
      }
      data-workflow-latest-action-retry-skipped={@latest_action_outcome.retry_skipped}
      data-workflow-latest-action-retry-errors={@latest_action_outcome.retry_errors}
      data-workflow-latest-action-retry-scope={@latest_action_outcome.retry_scope}
       data-workflow-latest-action-retry-run-ids={@latest_action_outcome.retry_run_ids}
       data-workflow-latest-action-retry-nonretryable-run-ids={
         retry_disposition(@latest_action_outcome, :nonretryable_run_ids)
       }
       data-workflow-latest-action-retry-nonretryable-event-ids={
         retry_disposition(@latest_action_outcome, :nonretryable_event_ids)
       }
       data-workflow-latest-action-retry-nonretryable-items={
         retry_disposition(@latest_action_outcome, :nonretryable_items)
       }
       data-workflow-latest-action-retry-skipped-run-ids={
         retry_disposition(@latest_action_outcome, :skipped_run_ids)
       }
       data-workflow-latest-action-retry-skipped-event-ids={
         retry_disposition(@latest_action_outcome, :skipped_event_ids)
       }
       data-workflow-latest-action-retry-skipped-items={
         retry_disposition(@latest_action_outcome, :skipped_items)
       }
       data-workflow-latest-action-retry-error-run-ids={
         @latest_action_outcome.retry_error_run_ids
       }
      data-workflow-latest-action-retry-error-event-ids={
        @latest_action_outcome.retry_error_event_ids
      }
      data-workflow-latest-action-retry-error-items={
        @latest_action_outcome.retry_error_items
      }
      data-workflow-latest-action-queued-jobs={@latest_action_outcome.queued_jobs}
      data-workflow-latest-action-failed-jobs={@latest_action_outcome.failed_jobs}
      data-workflow-latest-action-result-event-ids={
        @latest_action_outcome.result_event_ids
      }
      data-workflow-latest-action-target-event-id={
        @latest_action_outcome.target_event_id
      }
      data-workflow-latest-action-target-run-id={
        @latest_action_outcome.target_run_id
      }
      data-workflow-latest-action-handoff-count={length(@latest_action_handoffs)}
      data-workflow-latest-action-primary-result-event-id={
        HistoricalWorkflowStatusNavigationPresentation.primary_handoff_event_id(
          @latest_action_handoffs
        )
      }
    >
      <div class="flex items-center justify-between gap-2">
        <span class="hud-label">Last Action</span>
        <span class={["badge badge-xs", @latest_action_outcome.badge_class]}>
          {@latest_action_outcome.status_label}
        </span>
      </div>
      <p class="mt-1 text-base-content/80">
        {@latest_action_outcome.message}
      </p>
      <dl class="mt-2 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1">
        <dt class="text-base-content/60">Action</dt>
        <dd class="font-mono break-all">
          {@latest_action_outcome.action_label}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.reason)}
          class="text-base-content/60"
        >
          Reason
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.reason)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.reason}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.stage)}
          class="text-base-content/60"
        >
          Stage
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.stage)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.stage}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.job_id)}
          class="text-base-content/60"
        >
          Job
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.job_id)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.job_id}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.target_event_id)}
          class="text-base-content/60"
        >
          Event
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.target_event_id)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.target_event_id}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.target_run_id)}
          class="text-base-content/60"
        >
          Run
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.target_run_id)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.target_run_id}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.result_event_ids)}
          class="text-base-content/60"
        >
          Results
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.result_event_ids)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.result_event_ids}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.count)}
          class="text-base-content/60"
        >
          Count
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.count)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.count}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retried)}
          class="text-base-content/60"
        >
          Retried
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retried)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retried}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_nonretryable)}
          class="text-base-content/60"
        >
          Non-retry
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_nonretryable)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retry_nonretryable}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_skipped)}
          class="text-base-content/60"
        >
          Skipped
        </dt>
         <dd
           :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_skipped)}
           class="font-mono break-all"
         >
           {@latest_action_outcome.retry_skipped}
         </dd>
         <dt
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :nonretryable_run_ids)
             )
           }
           class="text-base-content/60"
         >
           Non-retry runs
         </dt>
         <dd
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :nonretryable_run_ids)
             )
           }
           class="font-mono break-all"
         >
           {retry_disposition(@latest_action_outcome, :nonretryable_run_ids)}
         </dd>
         <dt
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :nonretryable_event_ids)
             )
           }
           class="text-base-content/60"
         >
           Non-retry events
         </dt>
         <dd
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :nonretryable_event_ids)
             )
           }
           class="font-mono break-all"
         >
           {retry_disposition(@latest_action_outcome, :nonretryable_event_ids)}
         </dd>
         <dt
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :nonretryable_items)
             )
           }
           class="text-base-content/60"
         >
           Non-retry items
         </dt>
         <dd
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :nonretryable_items)
             )
           }
           class="font-mono break-all"
         >
           {retry_disposition(@latest_action_outcome, :nonretryable_items)}
         </dd>
         <dt
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :skipped_run_ids)
             )
           }
           class="text-base-content/60"
         >
           Skipped runs
         </dt>
         <dd
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :skipped_run_ids)
             )
           }
           class="font-mono break-all"
         >
           {retry_disposition(@latest_action_outcome, :skipped_run_ids)}
         </dd>
         <dt
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :skipped_event_ids)
             )
           }
           class="text-base-content/60"
         >
           Skipped events
         </dt>
         <dd
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :skipped_event_ids)
             )
           }
           class="font-mono break-all"
         >
           {retry_disposition(@latest_action_outcome, :skipped_event_ids)}
         </dd>
         <dt
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :skipped_items)
             )
           }
           class="text-base-content/60"
         >
           Skipped items
         </dt>
         <dd
           :if={
             DataLinkInspectorPanelPresentation.present_text?(
               retry_disposition(@latest_action_outcome, :skipped_items)
             )
           }
           class="font-mono break-all"
         >
           {retry_disposition(@latest_action_outcome, :skipped_items)}
         </dd>
         <dt
           :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_errors)}
           class="text-base-content/60"
        >
          Errors
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_errors)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retry_errors}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_error_run_ids)}
          class="text-base-content/60"
        >
          Error runs
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_error_run_ids)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retry_error_run_ids}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_error_event_ids)}
          class="text-base-content/60"
        >
          Error events
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_error_event_ids)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retry_error_event_ids}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_error_items)}
          class="text-base-content/60"
        >
          Error items
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_error_items)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retry_error_items}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_scope)}
          class="text-base-content/60"
        >
          Scope
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_scope)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retry_scope}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_run_ids)}
          class="text-base-content/60"
        >
          Retry runs
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.retry_run_ids)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.retry_run_ids}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.queued_jobs)}
          class="text-base-content/60"
        >
          Queued
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.queued_jobs)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.queued_jobs}
        </dd>
        <dt
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.failed_jobs)}
          class="text-base-content/60"
        >
          Failed
        </dt>
        <dd
          :if={DataLinkInspectorPanelPresentation.present_text?(@latest_action_outcome.failed_jobs)}
          class="font-mono break-all"
        >
          {@latest_action_outcome.failed_jobs}
        </dd>
      </dl>
      <section
        :if={@latest_action_handoffs != []}
        id="dashboard-historical-workflow-latest-action-handoffs"
        class="mt-2 space-y-2 rounded border border-base-300/60 bg-base-100/70 p-2"
        data-workflow-latest-action-handoff-count={length(@latest_action_handoffs)}
        data-workflow-latest-action-handoff-primary-event={
          HistoricalWorkflowStatusNavigationPresentation.primary_handoff_event_id(
            @latest_action_handoffs
          )
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Result Handoff</span>
          <span class="font-mono text-base-content/70">
            {length(@latest_action_handoffs)}
          </span>
        </div>
        <div class="flex flex-wrap gap-1">
          <.link
            :for={handoff <- @latest_action_handoffs}
            patch={handoff.href}
            class="badge badge-xs badge-outline"
            data-workflow-latest-action-handoff={handoff.event_id}
            data-workflow-latest-action-handoff-role={handoff.role}
            data-workflow-latest-action-handoff-href={handoff.href}
          >
            {handoff.label}
          </.link>
        </div>
      </section>
    </div>
    """
  end

  defp retry_disposition(%{retry_disposition: disposition}, key) when is_map(disposition) do
    Map.get(disposition, key)
  end

  defp retry_disposition(_latest_action_outcome, _key), do: nil
end
