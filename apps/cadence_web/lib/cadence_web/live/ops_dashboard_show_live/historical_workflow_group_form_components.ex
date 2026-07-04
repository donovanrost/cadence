defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStartPresentation

  attr :form, Phoenix.HTML.Form, required: true
  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true

  def group_transition_form(assigns) do
    assigns =
      assign(
        assigns,
        :group_start,
        HistoricalWorkflowGroupStartPresentation.build(
          assigns.workflow_context,
          assigns.workflow_controls
        )
      )

    ~H"""
    <.form
      :if={@workflow_controls.group_actions}
      for={@form}
      id="dashboard-historical-workflow-group-form"
      phx-submit="record_historical_workflow_group_stage"
      class="space-y-3 rounded border border-primary/30 bg-primary/5 p-2"
    >
      <input
        id="dashboard-historical-workflow-group-workflow"
        type="hidden"
        name={@form[:workflow].name}
        value={@workflow_context.workflow}
      />
      <input
        id="dashboard-historical-workflow-group-request-group-id"
        type="hidden"
        name={@form[:request_group_id].name}
        value={@workflow_context.request_group_id || ""}
      />
      <input
        id="dashboard-historical-workflow-group-realm"
        type="hidden"
        name={@form[:realm].name}
        value={@workflow_context.realm}
      />
      <input
        id="dashboard-historical-workflow-group-data-source-id"
        type="hidden"
        name={@form[:data_source_id].name}
        value={@workflow_context.data_source_id}
      />
      <input
        id="dashboard-historical-workflow-group-source-binding-id"
        type="hidden"
        name={@form[:source_binding_id].name}
        value={@workflow_context.source_binding_id}
      />
      <input
        id="dashboard-historical-workflow-group-dashboard-id"
        type="hidden"
        name={@form[:dashboard_id].name}
        value={@workflow_context.dashboard_id || ""}
      />
      <input
        id="dashboard-historical-workflow-group-dashboard-version"
        type="hidden"
        name={@form[:dashboard_version].name}
        value={@workflow_context.dashboard_version || ""}
      />
      <input
        id="dashboard-historical-workflow-group-dashboard-time-mode"
        type="hidden"
        name={@form[:dashboard_time_mode].name}
        value={@workflow_context.dashboard_time_mode || ""}
      />
      <input
        id="dashboard-historical-workflow-group-dashboard-replay-run-id"
        type="hidden"
        name={@form[:dashboard_replay_run_id].name}
        value={@workflow_context.dashboard_replay_run_id || ""}
      />
      <input
        id="dashboard-historical-workflow-group-dashboard-data-view"
        type="hidden"
        name={@form[:dashboard_data_view].name}
        value={@workflow_context.dashboard_data_view || ""}
      />
      <input
        id="dashboard-historical-workflow-group-dashboard-limit-mode"
        type="hidden"
        name={@form[:dashboard_limit_mode].name}
        value={@workflow_context.dashboard_limit_mode || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-request-event-id"
        type="hidden"
        name={@form[:comparison_review_request_event_id].name}
        value={@workflow_context.comparison_review_request_event_id || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-request-kind"
        type="hidden"
        name={@form[:comparison_review_request_kind].name}
        value={@workflow_context.comparison_review_request_kind || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-open-count"
        type="hidden"
        name={@form[:comparison_review_open_count].name}
        value={@workflow_context.comparison_review_open_count || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-open-placement-ids"
        type="hidden"
        name={@form[:comparison_review_open_placement_ids].name}
        value={@workflow_context.comparison_review_open_placement_ids || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-workflow-kind"
        type="hidden"
        name={@form[:comparison_review_workflow_kind].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_kind) || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-workflow-action"
        type="hidden"
        name={@form[:comparison_review_workflow_action].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_action) || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-workflow-selection-kind"
        type="hidden"
        name={@form[:comparison_review_workflow_selection_kind].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_selection_kind) || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-workflow-selection-count"
        type="hidden"
        name={@form[:comparison_review_workflow_selection_count].name}
        value={Map.get(@workflow_context, :comparison_review_workflow_selection_count) || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-primary-data-view"
        type="hidden"
        name={@form[:comparison_review_primary_data_view].name}
        value={Map.get(@workflow_context, :comparison_review_primary_data_view) || ""}
      />
      <input
        id="dashboard-historical-workflow-group-comparison-review-compare-data-view"
        type="hidden"
        name={@form[:comparison_review_compare_data_view].name}
        value={Map.get(@workflow_context, :comparison_review_compare_data_view) || ""}
      />
      <div class="flex items-center justify-between gap-2">
        <h4 class="hud-label">Group Actions</h4>
        <span class="badge badge-xs badge-primary">{@workflow_context.request_item_count} items</span>
      </div>
      <div
        id="dashboard-historical-workflow-group-eligible-items"
        class="space-y-1 rounded border border-base-300/60 bg-base-100/70 p-2"
        data-historical-workflow-group-eligible-request-group={@workflow_context.request_group_id || ""}
        data-historical-workflow-group-eligible-size={@workflow_context.request_item_count || ""}
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Eligible Items</span>
          <span class="font-mono text-base-content/60">
            {@workflow_context.request_item_count}
          </span>
        </div>
        <div class="space-y-1">
          <div
            :for={action <- @workflow_controls.group_stage_actions}
            class="rounded border border-base-300/50 bg-base-200/40 px-2 py-1"
            data-historical-workflow-group-eligible-action={action.stage}
            data-historical-workflow-group-eligible-count={action.eligible_count}
            data-historical-workflow-group-eligible-state={
              DataLinkInspectorPanelPresentation.bool_attr(action.eligible?)
            }
            data-historical-workflow-group-eligible-reason={action.reason}
            data-workflow-action-correction-tasks={Map.get(action, :correction_tasks)}
          >
            <div class="flex items-center justify-between gap-2">
              <span class="font-mono text-base-content">{action.label}</span>
              <span class="badge badge-xs badge-outline font-mono">
                {action.eligible_count}
              </span>
            </div>
            <p class="mt-1 text-base-content/75">{action.preview}</p>
            <p
              :if={
                DataLinkInspectorPanelPresentation.present_text?(
                  Map.get(action, :state_summary)
                )
              }
              class="mt-1 font-mono text-base-content/60"
            >
              {Map.get(action, :state_summary)}
            </p>
            <p
              :if={
                DataLinkInspectorPanelPresentation.present_text?(
                  Map.get(action, :available_when)
                )
              }
              class="mt-1 text-base-content/60"
            >
              {Map.get(action, :available_when)}
            </p>
          </div>
        </div>
      </div>
      <section
        :if={@group_start.present}
        id="dashboard-historical-workflow-group-start-orchestration"
        class="space-y-2 rounded border border-info/40 bg-info/10 p-2"
        data-historical-workflow-group-start-request-group={
          Map.get(@workflow_context, :request_group_id)
        }
        data-historical-workflow-group-start-next-action={@group_start.next_action}
        data-historical-workflow-group-start-eligible={@group_start.eligible_count}
        data-historical-workflow-group-start-eligible-state={@group_start.eligible}
        data-historical-workflow-group-start-reason={@group_start.reason}
        data-historical-workflow-group-start-preview={@group_start.preview}
        data-historical-workflow-group-start-state={@group_start.state}
        data-historical-workflow-group-start-available-when={@group_start.available_when}
        data-historical-workflow-group-start-expected-jobs={@group_start.expected_jobs}
        data-historical-workflow-group-start-review-request={
          Map.get(@workflow_context, :comparison_review_request_event_id)
        }
        data-historical-workflow-group-start-review-kind={
          Map.get(@workflow_context, :comparison_review_request_kind)
        }
        data-historical-workflow-group-start-review-open-count={
          Map.get(@workflow_context, :comparison_review_open_count)
        }
        data-historical-workflow-group-start-review-placements={
          Map.get(@workflow_context, :comparison_review_open_placement_ids)
        }
        data-historical-workflow-group-start-review-workflow-kind={
          Map.get(@workflow_context, :comparison_review_workflow_kind)
        }
        data-historical-workflow-group-start-review-workflow-action={
          Map.get(@workflow_context, :comparison_review_workflow_action)
        }
        data-historical-workflow-group-start-review-workflow-selection-kind={
          Map.get(@workflow_context, :comparison_review_workflow_selection_kind)
        }
        data-historical-workflow-group-start-review-workflow-selection-count={
          Map.get(@workflow_context, :comparison_review_workflow_selection_count)
        }
        data-historical-workflow-group-start-review-primary-data-view={
          Map.get(@workflow_context, :comparison_review_primary_data_view)
        }
        data-historical-workflow-group-start-review-compare-data-view={
          Map.get(@workflow_context, :comparison_review_compare_data_view)
        }
      >
        <div class="flex items-center justify-between gap-2">
          <span class="hud-label">Start Orchestration</span>
          <span class="badge badge-xs badge-info font-mono">
            {@group_start.expected_jobs} jobs
          </span>
        </div>
        <p class="text-base-content/75">
          {@group_start.guidance}
        </p>
        <dl class="grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
          <dt class="text-base-content/60">Eligible</dt>
          <dd class="font-mono">{@group_start.eligible_count}</dd>
          <dt
            :if={
              DataLinkInspectorPanelPresentation.present_text?(
                Map.get(@workflow_context, :comparison_review_request_event_id)
              )
            }
            class="text-base-content/60"
          >
            Review
          </dt>
          <dd
            :if={
              DataLinkInspectorPanelPresentation.present_text?(
                Map.get(@workflow_context, :comparison_review_request_event_id)
              )
            }
            class="font-mono break-all"
          >
            {Map.get(@workflow_context, :comparison_review_request_event_id)}
          </dd>
          <dt
            :if={
              DataLinkInspectorPanelPresentation.present_text?(
                @group_start.state
              )
            }
            class="text-base-content/60"
          >
            State
          </dt>
          <dd
            :if={
              DataLinkInspectorPanelPresentation.present_text?(
                @group_start.state
              )
            }
            class="font-mono break-all"
          >
            {@group_start.state}
          </dd>
        </dl>
        <p
          :if={
            DataLinkInspectorPanelPresentation.present_text?(
              @group_start.available_when
            )
          }
          class="text-base-content/60"
        >
          {@group_start.available_when}
        </p>
      </section>
      <.input
        field={@form[:reason]}
        type="text"
        label="Reason"
        placeholder={@workflow_context.reason || "dashboard workflow group event"}
        compact
      />
      <label
        id="dashboard-historical-workflow-group-confirm-row"
        class="flex items-start gap-2 rounded border border-primary/30 bg-base-100/70 p-2 text-xs"
      >
        <input
          id="dashboard-historical-workflow-group-confirm"
          type="checkbox"
          name={@form[:confirmed].name}
          value="confirmed"
          required
          class="checkbox checkbox-xs mt-0.5"
        />
        <span class="text-base-content/80">
          Confirm workflow transition for eligible items in this request group
        </span>
      </label>
      <div class="grid grid-cols-2 gap-2">
        <button
          :for={action <- @workflow_controls.group_stage_actions}
          id={"dashboard-historical-workflow-group-#{action.stage}"}
          type="submit"
          name={@form[:stage].name}
          value={action.stage}
          disabled={action.disabled?}
          class={[
            "btn btn-xs justify-between gap-2",
            action.disabled? && "btn-disabled",
            !action.disabled? && action.class
          ]}
          data-historical-workflow-group-action={action.stage}
          data-historical-workflow-group-action-eligible={action.eligible_count}
          data-workflow-action-id={action.id}
          data-workflow-action-eligible={DataLinkInspectorPanelPresentation.bool_attr(action.eligible?)}
          data-workflow-action-reason={action.reason}
          data-workflow-action-preview={action.preview}
          data-workflow-action-correction-tasks={Map.get(action, :correction_tasks)}
        >
          <span class="flex min-w-0 items-center gap-1">
            <.icon name={action.icon} class="h-3.5 w-3.5" /> {action.label}
          </span>
          <span class="font-mono">{action.eligible_count}</span>
        </button>
      </div>
    </.form>
    """
  end
end
