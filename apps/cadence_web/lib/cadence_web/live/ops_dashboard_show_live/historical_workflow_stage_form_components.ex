defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation

  attr :form, Phoenix.HTML.Form, required: true
  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true

  def stage_transition_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="dashboard-historical-workflow-form"
      phx-submit="record_historical_workflow_stage"
      class="space-y-3"
    >
      <input
        id="dashboard-historical-workflow-event-id"
        type="hidden"
        name={@form[:event_id].name}
        value={@workflow_context.event_id || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-source-event-id"
        type="hidden"
        name={@form[:correction_source_event_id].name}
        value={@workflow_context.correction_source_event_id || ""}
      />
      <input
        id="dashboard-historical-workflow-value"
        type="hidden"
        name={@form[:workflow].name}
        value={@workflow_context.workflow}
      />
      <input
        id="dashboard-historical-workflow-run-id"
        type="hidden"
        name={@form[:run_id].name}
        value={@workflow_context.run_id}
      />
      <input
        id="dashboard-historical-workflow-realm"
        type="hidden"
        name={@form[:realm].name}
        value={@workflow_context.realm}
      />
      <input
        id="dashboard-historical-workflow-data-source-id"
        type="hidden"
        name={@form[:data_source_id].name}
        value={@workflow_context.data_source_id}
      />
      <input
        id="dashboard-historical-workflow-source-binding-id"
        type="hidden"
        name={@form[:source_binding_id].name}
        value={@workflow_context.source_binding_id}
      />
      <input
        id="dashboard-historical-workflow-observable-id"
        type="hidden"
        name={@form[:observable_id].name}
        value={@workflow_context.observable_id || ""}
      />
      <input
        id="dashboard-historical-workflow-point-id"
        type="hidden"
        name={@form[:point_id].name}
        value={@workflow_context.point_id || ""}
      />
      <input
        id="dashboard-historical-workflow-dashboard-id"
        type="hidden"
        name={@form[:dashboard_id].name}
        value={@workflow_context.dashboard_id || ""}
      />
      <input
        id="dashboard-historical-workflow-dashboard-version"
        type="hidden"
        name={@form[:dashboard_version].name}
        value={@workflow_context.dashboard_version || ""}
      />
      <input
        id="dashboard-historical-workflow-dashboard-time-mode"
        type="hidden"
        name={@form[:dashboard_time_mode].name}
        value={@workflow_context.dashboard_time_mode || ""}
      />
      <input
        id="dashboard-historical-workflow-dashboard-replay-run-id"
        type="hidden"
        name={@form[:dashboard_replay_run_id].name}
        value={@workflow_context.dashboard_replay_run_id || ""}
      />
      <input
        id="dashboard-historical-workflow-dashboard-data-view"
        type="hidden"
        name={@form[:dashboard_data_view].name}
        value={@workflow_context.dashboard_data_view || ""}
      />
      <input
        id="dashboard-historical-workflow-dashboard-limit-mode"
        type="hidden"
        name={@form[:dashboard_limit_mode].name}
        value={@workflow_context.dashboard_limit_mode || ""}
      />
      <input
        id="dashboard-historical-workflow-request-group-id"
        type="hidden"
        name={@form[:request_group_id].name}
        value={@workflow_context.request_group_id || ""}
      />
      <input
        id="dashboard-historical-workflow-request-mode"
        type="hidden"
        name={@form[:request_mode].name}
        value={@workflow_context.request_mode || ""}
      />
      <.input
        field={@form[:reason]}
        type="text"
        label="Reason"
        placeholder={@workflow_context.reason || "dashboard workflow event"}
        compact
      />
      <div class="grid grid-cols-1 gap-2">
        <.input
          field={@form[:source_from]}
          type="text"
          label="Source From"
          compact
        />
        <.input
          field={@form[:source_to]}
          type="text"
          label="Source To"
          compact
        />
      </div>
      <label
        id="dashboard-historical-workflow-confirm-row"
        class="flex items-start gap-2 rounded border border-base-300/70 bg-base-100/60 p-2 text-xs"
      >
        <input
          id="dashboard-historical-workflow-confirm"
          type="checkbox"
          name={@form[:confirmed].name}
          value="confirmed"
          required
          class="checkbox checkbox-xs mt-0.5"
        />
        <span class="text-base-content/80">
          Confirm workflow transition
        </span>
      </label>
      <div class="grid grid-cols-2 gap-2">
        <button
          :for={action <- @workflow_controls.stage_actions}
          id={"dashboard-historical-workflow-#{action.stage}"}
          type="submit"
          name={@form[:stage].name}
          value={action.stage}
          disabled={action.disabled?}
          class={[
            "btn btn-xs justify-start",
            action.disabled? && "btn-disabled",
            !action.disabled? && action.class
          ]}
          data-historical-workflow-action={action.stage}
          data-workflow-action-id={action.id}
          data-workflow-action-eligible={DataLinkInspectorPanelPresentation.bool_attr(action.eligible?)}
          data-workflow-action-reason={action.reason}
          data-workflow-action-preview={action.preview}
        >
          <.icon name={action.icon} class="h-3.5 w-3.5" /> {action.label}
        </button>
      </div>
    </.form>
    """
  end
end
