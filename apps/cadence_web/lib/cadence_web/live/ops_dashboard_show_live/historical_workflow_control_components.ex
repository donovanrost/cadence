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
    workflow_form = to_form(controls.form_params, as: :historical_workflow)
    workflow_group_form = to_form(controls.form_params, as: :historical_workflow_group)

    workflow_correction_form =
      to_form(
        controls.correction_form_params,
        as: :historical_workflow_correction
      )

    assigns =
      assign(
        assigns,
        :presentation,
        historical_workflow_controls_presentation(
          context,
          controls,
          assigns.action_outcome,
          assigns.dashboard_current_path,
          workflow_form,
          workflow_group_form,
          workflow_correction_form
        )
      )

    ~H"""
    <.vue
      id="dashboard-historical-workflow-controls-component"
      v-component="HistoricalWorkflowControls"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp historical_workflow_controls_presentation(
         context,
         controls,
         action_outcome,
         dashboard_current_path,
         workflow_form,
         workflow_group_form,
         workflow_correction_form
       ) do
    %{
      root: %{
        id: "dashboard-historical-workflow-controls",
        class: "space-y-2",
        attrs:
          raw_attrs(%{
            "data-historical-workflow" => context.workflow,
            "data-historical-workflow-stage" => context.stage || "",
            "data-historical-workflow-run-id" => context.run_id
          })
      },
      heading: %{class: "hud-label", text: "Workflow Actions"},
      action_outcome: action_outcome_presentation(action_outcome),
      latest_action:
        HistoricalWorkflowLatestActionComponents.presentation(
          controls.latest_action_outcome,
          dashboard_current_path
        ),
      action_explanations:
        HistoricalWorkflowActionExplanationComponents.presentation(
          controls.blocked_action_explanations
        ),
      group_status:
        HistoricalWorkflowGroupStatusComponents.presentation(
          context,
          controls,
          dashboard_current_path
        ),
      job_status:
        HistoricalWorkflowJobStatusComponents.presentation(
          context,
          controls,
          dashboard_current_path
        ),
      correction_form:
        HistoricalWorkflowCorrectionFormComponents.presentation(
          workflow_correction_form,
          context,
          controls
        ),
      stage_form:
        HistoricalWorkflowStageFormComponents.presentation(workflow_form, context, controls),
      group_form:
        HistoricalWorkflowGroupFormComponents.presentation(
          workflow_group_form,
          context,
          controls
        )
    }
  end

  defp action_outcome_presentation(action_outcome) do
    case DataLinkActionOutcomePresentation.build(action_outcome) do
      nil ->
        nil

      presentation ->
        %{
          root: %{
            id: "dashboard-historical-workflow-action-outcome",
            class: "hidden",
            attrs:
              HistoricalWorkflowActionOutcomePresentation.stable_attrs(
                action_outcome,
                "data-workflow-action"
              )
          },
          message: presentation.message
        }
    end
  end

  defp raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end
end
