defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionExplanationComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContext
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlsPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionFormComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupFormComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageFormComponents

  attr :inspector, :map, required: true
  attr :action_outcome, :map, default: nil
  attr :dashboard_current_path, :string, default: nil

  def historical_workflow_controls(assigns) do
    context = HistoricalWorkflowContext.build(assigns.inspector)
    controls = HistoricalWorkflowControlsPresentation.build(context, assigns.action_outcome)

    assigns =
      assigns
      |> assign(:workflow_context, context)
      |> assign(:workflow_controls, controls)
      |> assign(
        :action_outcome_presentation,
        DataLinkActionOutcomePresentation.build(assigns.action_outcome)
      )
      |> assign(
        :workflow_form,
        to_form(controls.form_params, as: :historical_workflow)
      )
      |> assign(
        :workflow_group_form,
        to_form(controls.form_params, as: :historical_workflow_group)
      )
      |> assign(
        :workflow_correction_form,
        to_form(
          controls.correction_form_params,
          as: :historical_workflow_correction
        )
      )

    ~H"""
    <section
      id="dashboard-historical-workflow-controls"
      class="space-y-2"
      data-historical-workflow={@workflow_context.workflow}
      data-historical-workflow-stage={@workflow_context.stage || ""}
      data-historical-workflow-run-id={@workflow_context.run_id}
    >
      <h3 class="hud-label">Workflow Actions</h3>
      <div
        :if={@action_outcome_presentation}
        id="dashboard-historical-workflow-action-outcome"
        class="hidden"
        data-workflow-action={@action_outcome_presentation.action}
        data-workflow-action-status={@action_outcome_presentation.status}
        data-workflow-action-kind={@action_outcome_presentation.kind}
        data-workflow-action-reason={@action_outcome_presentation.reason}
        data-workflow-action-stage={Map.get(@action_outcome_presentation.metadata, "stage")}
        data-workflow-action-request-group-id={
          Map.get(@action_outcome_presentation.metadata, "request_group_id")
        }
        data-workflow-action-job-id={Map.get(@action_outcome_presentation.metadata, "job_id")}
        data-workflow-action-count={Map.get(@action_outcome_presentation.metadata, "count")}
        data-workflow-action-retried={Map.get(@action_outcome_presentation.metadata, "retried")}
        data-workflow-action-retry-nonretryable={
          Map.get(@action_outcome_presentation.metadata, "retry_nonretryable")
        }
        data-workflow-action-retry-skipped={
          Map.get(@action_outcome_presentation.metadata, "retry_skipped")
        }
        data-workflow-action-retry-errors={
          Map.get(@action_outcome_presentation.metadata, "retry_errors")
        }
        data-workflow-action-retry-scope={
          Map.get(@action_outcome_presentation.metadata, "retry_scope")
        }
        data-workflow-action-retry-run-ids={
          Map.get(@action_outcome_presentation.metadata, "retry_run_ids")
        }
        data-workflow-action-retry-nonretryable-run-ids={
          Map.get(@action_outcome_presentation.metadata, "retry_nonretryable_run_ids")
        }
        data-workflow-action-retry-nonretryable-event-ids={
          Map.get(@action_outcome_presentation.metadata, "retry_nonretryable_event_ids")
        }
        data-workflow-action-retry-nonretryable-items={
          Map.get(@action_outcome_presentation.metadata, "retry_nonretryable_items")
        }
        data-workflow-action-retry-skipped-run-ids={
          Map.get(@action_outcome_presentation.metadata, "retry_skipped_run_ids")
        }
        data-workflow-action-retry-skipped-event-ids={
          Map.get(@action_outcome_presentation.metadata, "retry_skipped_event_ids")
        }
        data-workflow-action-retry-skipped-items={
          Map.get(@action_outcome_presentation.metadata, "retry_skipped_items")
        }
        data-workflow-action-retry-error-run-ids={
          Map.get(@action_outcome_presentation.metadata, "retry_error_run_ids")
        }
        data-workflow-action-retry-error-event-ids={
          Map.get(@action_outcome_presentation.metadata, "retry_error_event_ids")
        }
        data-workflow-action-retry-error-items={
          Map.get(@action_outcome_presentation.metadata, "retry_error_items")
        }
        data-workflow-action-queued-jobs={
          Map.get(@action_outcome_presentation.metadata, "queued_jobs")
        }
        data-workflow-action-failed-jobs={
          Map.get(@action_outcome_presentation.metadata, "failed_jobs")
        }
        data-workflow-action-target-event-id={
          Map.get(@action_outcome_presentation.metadata, "target_event_id")
        }
        data-workflow-action-target-run-id={
          Map.get(@action_outcome_presentation.metadata, "target_run_id")
        }
      >
        {@action_outcome_presentation.message}
      </div>
      <HistoricalWorkflowLatestActionComponents.latest_action
        latest_action_outcome={@workflow_controls.latest_action_outcome}
        dashboard_current_path={@dashboard_current_path}
      />
      <HistoricalWorkflowActionExplanationComponents.action_explanations
        blocked_action_explanations={@workflow_controls.blocked_action_explanations}
      />
      <HistoricalWorkflowGroupStatusComponents.group_status
        workflow_context={@workflow_context}
        workflow_controls={@workflow_controls}
        dashboard_current_path={@dashboard_current_path}
      />
      <HistoricalWorkflowJobStatusComponents.job_status
        workflow_context={@workflow_context}
        workflow_controls={@workflow_controls}
        dashboard_current_path={@dashboard_current_path}
      />
      <HistoricalWorkflowCorrectionFormComponents.corrected_request_form
        form={@workflow_correction_form}
        workflow_context={@workflow_context}
        workflow_controls={@workflow_controls}
      />
      <HistoricalWorkflowStageFormComponents.stage_transition_form
        form={@workflow_form}
        workflow_context={@workflow_context}
        workflow_controls={@workflow_controls}
      />
      <HistoricalWorkflowGroupFormComponents.group_transition_form
        form={@workflow_group_form}
        workflow_context={@workflow_context}
        workflow_controls={@workflow_controls}
      />
    </section>
    """
  end
end
