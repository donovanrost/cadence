defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobRecoveryPresentation

  attr :form, Phoenix.HTML.Form, required: true
  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true

  def corrected_request_form(assigns) do
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
    <.form
      :if={@job_recovery.correction_form.present}
      for={@form}
      id="dashboard-historical-workflow-correction-form"
      phx-submit="record_corrected_historical_workflow_request"
      class="space-y-3 rounded border border-warning/40 bg-warning/10 p-2"
      data-workflow-action-id={@job_recovery.correction_form.id}
      data-workflow-action-eligible={@job_recovery.correction_form.eligible}
      data-workflow-action-reason={@job_recovery.correction_form.reason}
      data-workflow-action-preview={@job_recovery.correction_form.preview}
      data-historical-workflow-correction-request-mode={Map.get(@workflow_context, :request_mode) || ""}
      data-historical-workflow-correction-request-group={Map.get(@workflow_context, :request_group_id) || ""}
      data-historical-workflow-correction-request-item={Map.get(@workflow_context, :request_item) || ""}
      data-historical-workflow-correction-request-item-count={
        Integer.to_string(Map.get(@workflow_context, :request_item_count, 0) || 0)
      }
    >
      <input
        id="dashboard-historical-workflow-correction-workflow"
        type="hidden"
        name={@form[:workflow].name}
        value={@workflow_context.workflow}
      />
      <input
        id="dashboard-historical-workflow-correction-original-run-id"
        type="hidden"
        name={@form[:original_run_id].name}
        value={@workflow_context.run_id}
      />
      <input
        id="dashboard-historical-workflow-correction-original-event-id"
        type="hidden"
        name={@form[:original_event_id].name}
        value={@workflow_context.event_id}
      />
      <input
        id="dashboard-historical-workflow-correction-original-job-id"
        type="hidden"
        name={@form[:original_job_id].name}
        value={@workflow_context.job_id}
      />
      <input
        id="dashboard-historical-workflow-correction-dashboard-id"
        type="hidden"
        name={@form[:dashboard_id].name}
        value={@workflow_context.dashboard_id || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-dashboard-version"
        type="hidden"
        name={@form[:dashboard_version].name}
        value={@workflow_context.dashboard_version || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-dashboard-time-mode"
        type="hidden"
        name={@form[:dashboard_time_mode].name}
        value={@workflow_context.dashboard_time_mode || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-dashboard-replay-run-id"
        type="hidden"
        name={@form[:dashboard_replay_run_id].name}
        value={@workflow_context.dashboard_replay_run_id || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-dashboard-data-view"
        type="hidden"
        name={@form[:dashboard_data_view].name}
        value={@workflow_context.dashboard_data_view || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-dashboard-limit-mode"
        type="hidden"
        name={@form[:dashboard_limit_mode].name}
        value={@workflow_context.dashboard_limit_mode || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-request-mode"
        type="hidden"
        name={@form[:request_mode].name}
        value={Map.get(@workflow_context, :request_mode) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-request-group-id"
        type="hidden"
        name={@form[:request_group_id].name}
        value={Map.get(@workflow_context, :request_group_id) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-request-item-index"
        type="hidden"
        name={@form[:request_item_index].name}
        value={request_item_index(@workflow_context)}
      />
      <input
        id="dashboard-historical-workflow-correction-request-item-count"
        type="hidden"
        name={@form[:request_item_count].name}
        value={request_item_count(@workflow_context)}
      />
      <input
        id="dashboard-historical-workflow-correction-request-item-run-id"
        type="hidden"
        name={@form[:request_item_run_id].name}
        value={@form[:run_id].value || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-request-event-id"
        type="hidden"
        name={@form[:comparison_review_request_event_id].name}
        value={Map.get(@workflow_context, :comparison_review_request_event_id) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-request-kind"
        type="hidden"
        name={@form[:comparison_review_request_kind].name}
        value={Map.get(@workflow_context, :comparison_review_request_kind) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-open-count"
        type="hidden"
        name={@form[:comparison_review_open_count].name}
        value={Map.get(@workflow_context, :comparison_review_open_count) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-open-placement-ids"
        type="hidden"
        name={@form[:comparison_review_open_placement_ids].name}
        value={Map.get(@workflow_context, :comparison_review_open_placement_ids) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-workflow-kind"
        type="hidden"
        name={@form[:comparison_review_workflow_kind].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_kind) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-workflow-action"
        type="hidden"
        name={@form[:comparison_review_workflow_action].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_action) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-workflow-selection-kind"
        type="hidden"
        name={@form[:comparison_review_workflow_selection_kind].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_selection_kind) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-workflow-selection-count"
        type="hidden"
        name={@form[:comparison_review_workflow_selection_count].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_selection_count) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-primary-data-view"
        type="hidden"
        name={@form[:comparison_review_primary_data_view].name}
        value={Map.get(@workflow_context, :comparison_review_primary_data_view) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-compare-data-view"
        type="hidden"
        name={@form[:comparison_review_compare_data_view].name}
        value={Map.get(@workflow_context, :comparison_review_compare_data_view) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-scope-kind"
        type="hidden"
        name={@form[:comparison_review_scope_kind].name}
        value={Map.get(@workflow_context, :comparison_review_scope_kind) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-scope-ids"
        type="hidden"
        name={@form[:comparison_review_scope_ids].name}
        value={Map.get(@workflow_context, :comparison_review_scope_ids) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-contact-ids"
        type="hidden"
        name={@form[:comparison_review_contact_ids].name}
        value={Map.get(@workflow_context, :comparison_review_contact_ids) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-resource-ids"
        type="hidden"
        name={@form[:comparison_review_resource_ids].name}
        value={Map.get(@workflow_context, :comparison_review_resource_ids) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-transport-ids"
        type="hidden"
        name={@form[:comparison_review_transport_ids].name}
        value={Map.get(@workflow_context, :comparison_review_transport_ids) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-source-endpoint-ids"
        type="hidden"
        name={@form[:comparison_review_source_endpoint_ids].name}
        value={Map.get(@workflow_context, :comparison_review_source_endpoint_ids) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-ground-station-ids"
        type="hidden"
        name={@form[:comparison_review_ground_station_ids].name}
        value={Map.get(@workflow_context, :comparison_review_ground_station_ids) || ""}
      />
      <input
        id="dashboard-historical-workflow-correction-comparison-review-scope-link-ids"
        type="hidden"
        name={@form[:comparison_review_scope_link_ids].name}
        value={Map.get(@workflow_context, :comparison_review_scope_link_ids) || ""}
      />
      <div class="flex items-center justify-between gap-2">
        <h4 class="hud-label">Correct Request</h4>
        <span class="badge badge-xs badge-warning">New run</span>
      </div>
      <dl
        :if={DataLinkInspectorPanelPresentation.present_text?(Map.get(@workflow_context, :request_group_id))}
        id="dashboard-historical-workflow-correction-group-context"
        class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 rounded border border-warning/30 bg-base-100/70 p-2 text-xs"
        data-historical-workflow-correction-group-context-request-mode={
          Map.get(@workflow_context, :request_mode) || ""
        }
        data-historical-workflow-correction-group-context-request-group={
          Map.get(@workflow_context, :request_group_id) || ""
        }
        data-historical-workflow-correction-group-context-request-item={
          Map.get(@workflow_context, :request_item) || ""
        }
        data-historical-workflow-correction-group-context-replacement-run={
          @form[:run_id].value || ""
        }
      >
        <dt class="text-base-content/60">Group</dt>
        <dd class="font-mono break-all">{Map.get(@workflow_context, :request_group_id)}</dd>
        <dt class="text-base-content/60">Item</dt>
        <dd class="font-mono">{Map.get(@workflow_context, :request_item)}</dd>
        <dt class="text-base-content/60">Replacement</dt>
        <dd class="font-mono break-all">{@form[:run_id].value}</dd>
      </dl>
      <.input field={@form[:run_id]} type="text" label="New Run" compact />
      <div class="grid grid-cols-1 gap-2">
        <.input field={@form[:realm]} type="text" label="Realm" compact />
        <.input
          field={@form[:data_source_id]}
          type="text"
          label="Data Source"
          compact
        />
        <.input
          field={@form[:source_binding_id]}
          type="text"
          label="Source Binding"
          compact
        />
        <.input
          field={@form[:observable_id]}
          type="text"
          label="Observable"
          compact
        />
        <.input field={@form[:point_id]} type="text" label="Point" compact />
        <.input
          field={@form[:source_from]}
          type="text"
          label="Source From"
          compact
        />
        <.input field={@form[:source_to]} type="text" label="Source To" compact />
        <.input field={@form[:reason]} type="text" label="Reason" compact />
      </div>
      <label
        id="dashboard-historical-workflow-correction-confirm-row"
        class="flex items-start gap-2 rounded border border-warning/40 bg-base-100/70 p-2 text-xs"
      >
        <input
          id="dashboard-historical-workflow-correction-confirm"
          type="checkbox"
          name={@form[:confirmed].name}
          value="confirmed"
          required
          class="checkbox checkbox-xs mt-0.5"
        />
        <span class="text-base-content/80">
          Confirm corrected workflow request
        </span>
      </label>
      <button
        id="dashboard-historical-workflow-correction-submit"
        type="submit"
        class="btn btn-xs btn-warning btn-outline w-full justify-start"
      >
        <.icon name="hero-document-plus" class="h-3.5 w-3.5" /> Request corrected workflow
      </button>
    </.form>
    """
  end

  defp request_item_index(workflow_context) do
    workflow_context
    |> Map.get(:request_item)
    |> split_request_item()
    |> elem(0)
  end

  defp request_item_count(workflow_context) do
    workflow_context
    |> Map.get(:request_item)
    |> split_request_item()
    |> elem(1)
  end

  defp split_request_item(value) when is_binary(value) do
    case String.split(value, "/", parts: 2) do
      [index, count] -> {String.trim(index), String.trim(count)}
      _parts -> {"", ""}
    end
  end

  defp split_request_item(_value), do: {"", ""}
end
