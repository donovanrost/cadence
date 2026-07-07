defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  attr :latest_action_outcome, :map, default: nil
  attr :dashboard_current_path, :string, default: nil

  def latest_action(assigns) do
    latest_action_handoffs =
      HistoricalWorkflowStatusNavigationPresentation.latest_action_handoffs(
        assigns.latest_action_outcome,
        assigns.dashboard_current_path
      )

    assigns =
      assigns
      |> assign(:latest_action_handoffs, latest_action_handoffs)
      |> assign(
        :latest_action_attrs,
        HistoricalWorkflowActionOutcomePresentation.stable_attrs(
          assigns.latest_action_outcome,
          "data-workflow-latest-action",
          handoff_count: length(latest_action_handoffs),
          primary_result_event_id:
            HistoricalWorkflowStatusNavigationPresentation.primary_handoff_event_id(
              latest_action_handoffs
            )
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
      {@latest_action_attrs}
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
          :if={
            DataLinkInspectorPanelPresentation.present_text?(
              latest_action_value(@latest_action_outcome, :request_group_id)
            )
          }
          class="text-base-content/60"
        >
          Group
        </dt>
        <dd
          :if={
            DataLinkInspectorPanelPresentation.present_text?(
              latest_action_value(@latest_action_outcome, :request_group_id)
            )
          }
          class="font-mono break-all"
        >
          {latest_action_value(@latest_action_outcome, :request_group_id)}
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
            data-workflow-latest-action-handoff-label={handoff.label}
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

  defp latest_action_value(latest_action_outcome, key) when is_map(latest_action_outcome) do
    Map.get(latest_action_outcome, key)
  end

  defp latest_action_value(_latest_action_outcome, _key), do: nil
end
