defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionExplanationComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcomePresentation
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
        :workflow_action_outcome_attrs,
        HistoricalWorkflowActionOutcomePresentation.stable_attrs(
          assigns.action_outcome,
          "data-workflow-action"
        )
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
        {@workflow_action_outcome_attrs}
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
