defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DashboardActionPresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContext
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlComponents
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowExplanation
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyContext
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyPresentation
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionContext
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionPresentation

  alias Cadence.Dashboards.DashboardAction

  attr :inspector, :map, required: true
  attr :mission_id, :string, required: true
  attr :dashboard_document, :any, required: true
  attr :dashboard_current_path, :string, required: true
  attr :data_link_action_outcome, :map, default: nil

  def data_link_panel(assigns) do
    presentation =
      DataLinkInspectorPanelPresentation.build(
        assigns.inspector,
        assigns.mission_id,
        assigns.dashboard_document,
        assigns.data_link_action_outcome
      )

    assigns =
      assigns
      |> assign(:panel, presentation.panel)
      |> assign(:panel_attrs, presentation.panel_attrs)
      |> assign(:data_link_actions, presentation.data_link_actions)
      |> assign(:data_link_action_outcome_presentation, presentation.action_outcome)
      |> assign(
        :data_link_action_outcome_attrs,
        DataLinkActionOutcomePresentation.stable_attrs(
          presentation.action_outcome,
          "data-data-link-action-outcome",
          action_suffix: "action"
        )
      )

    ~H"""
    <section
      id="dashboard-data-link-inspector"
      data-data-link-target={@panel_attrs.target}
      data-data-link-target-id={@panel_attrs.target_id}
      data-data-link-status={@panel_attrs.status}
      data-data-link-selected-link={@panel_attrs.selected_link}
      data-data-link-selected-realm={@panel_attrs.selected_realm}
      data-data-link-selected-data-view={@panel_attrs.selected_data_view}
      data-data-link-selected-data-source-id={@panel_attrs.selected_data_source_id}
      data-data-link-selected-source-binding-id={@panel_attrs.selected_source_binding_id}
      data-data-link-selected-time-mode={@panel_attrs.selected_time_mode}
      data-data-link-selected-time-axis={@panel_attrs.selected_time_axis}
      data-data-link-selected-replay-run-id={@panel_attrs.selected_replay_run_id}
      class="space-y-4"
    >
      <div class="space-y-1">
        <div class="flex items-center gap-2">
          <span class="badge badge-xs badge-outline">{@inspector.target_text}</span>
          <span class="badge badge-xs">{@inspector.status_text}</span>
        </div>
        <p :if={@inspector.message} class="text-sm text-base-content/70">
          {@inspector.message}
        </p>
      </div>

      <button
        id="dashboard-data-link-copy-link"
        type="button"
        phx-hook="ClipboardButton"
        data-clipboard-text={@dashboard_current_path}
        class="btn btn-sm btn-outline w-full justify-start"
      >
        <.icon name="hero-link" class="h-4 w-4" /> Copy link
      </button>

      <.dashboard_actions actions={@data_link_actions} />

      <div
        :if={@data_link_action_outcome_presentation}
        id="dashboard-data-link-action-outcome"
        class="hidden"
        {@data_link_action_outcome_attrs}
      >
        {@data_link_action_outcome_presentation.message}
      </div>

      <section :if={@panel.selection_summary_rows != []} class="space-y-2" data-data-link-selection>
        <h3 class="hud-label">Selection</h3>
        <dl class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
          <%= for row <- @panel.selection_summary_rows do %>
            <dt class="text-base-content/60">{row.label}</dt>
            <dd
              class="font-mono text-base-content break-all"
              data-data-link-selection-field={row.label}
            >
              {row.value}
            </dd>
          <% end %>
        </dl>
      </section>

      <.workflow_explanation
        :if={@panel.workflow_explanation?}
        inspector={@inspector}
      />

      <.revision_decision_controls
        :if={@panel.revision_decision_controls?}
        inspector={@inspector}
        action_outcome={@data_link_action_outcome}
      />

      <.late_data_policy_controls
        :if={@panel.late_data_policy_controls?}
        inspector={@inspector}
        action_outcome={@data_link_action_outcome}
      />

      <HistoricalWorkflowControlComponents.historical_workflow_controls
        :if={@panel.historical_workflow_controls?}
        inspector={@inspector}
        action_outcome={@data_link_action_outcome}
        dashboard_current_path={@dashboard_current_path}
      />

      <.navigation_breadcrumb
        :if={@panel.navigation}
        inspector={@inspector}
        trail={@panel.navigation_trail}
      />

      <section :if={@inspector.rows != []} class="space-y-2">
        <h3 class="hud-label">Record</h3>
        <dl class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
          <%= for row <- @inspector.rows do %>
            <dt class="text-base-content/60">{row.label}</dt>
            <dd class="font-mono text-base-content break-all" data-data-link-field={row.label}>
              {row.value}
            </dd>
          <% end %>
        </dl>
      </section>

      <.related_data_links
        :if={@panel.related_groups != []}
        inspector={@inspector}
        groups={@panel.related_groups}
      />

      <section :if={@inspector.context_rows != []} class="space-y-2">
        <h3 class="hud-label">Runtime Context</h3>
        <dl class="grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
          <%= for row <- @inspector.context_rows do %>
            <dt class="text-base-content/60">{row.label}</dt>
            <dd class="font-mono text-base-content break-all" data-data-link-context={row.label}>
              {row.value}
            </dd>
          <% end %>
        </dl>
      </section>
    </section>
    """
  end

  attr :inspector, :map, required: true

  defp workflow_explanation(assigns) do
    context = HistoricalWorkflowContext.build(assigns.inspector)
    explanation = HistoricalWorkflowExplanation.build(context)

    assigns =
      assigns
      |> assign(:workflow_context, context)
      |> assign(:workflow_explanation, explanation)

    ~H"""
    <section
      id="dashboard-workflow-explanation"
      class={[
        "space-y-2 rounded border p-2",
        @workflow_explanation.container_class
      ]}
      data-workflow-explanation-event-id={@workflow_context.event_id}
      data-workflow-explanation-event-type={@workflow_context.event_type}
      data-workflow-explanation-run-id={@workflow_context.run_id}
      data-workflow-explanation-state={@workflow_explanation.summary.state}
      data-workflow-explanation-severity={@workflow_explanation.summary.severity}
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="hud-label">Workflow Explanation</h3>
        <span class={["badge badge-xs", @workflow_explanation.badge_class]}>
          {@workflow_explanation.summary.badge}
        </span>
      </div>
      <p
        id="dashboard-workflow-explanation-summary"
        class="text-xs leading-5 text-base-content/80"
      >
        {@workflow_explanation.summary.summary}
      </p>
      <dl class="grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs">
        <%= for row <- @workflow_explanation.rows do %>
          <dt class="text-base-content/60">{row.label}</dt>
          <dd
            class="font-mono text-base-content break-all"
            data-workflow-explanation-field={row.label}
          >
            {row.value}
          </dd>
        <% end %>
      </dl>
    </section>
    """
  end

  attr :inspector, :map, required: true
  attr :action_outcome, :map, default: nil

  defp late_data_policy_controls(assigns) do
    context = LateDataPolicyContext.build(assigns.inspector)
    policy = LateDataPolicyPresentation.build(context)

    assigns =
      assigns
      |> assign(:late_data_context, context)
      |> assign(:late_data_policy, policy)
      |> assign(
        :action_outcome_presentation,
        DataLinkActionOutcomePresentation.for_action(assigns.action_outcome, :late_data_policy)
      )
      |> assign(
        :late_data_form,
        to_form(policy.form_params, as: :late_data_policy)
      )

    ~H"""
    <section
      id="dashboard-late-data-policy-controls"
      class="space-y-2 rounded border border-info/40 bg-info/10 p-2"
      data-late-data-policy-source-event={@late_data_context.source_event_id}
      data-late-data-policy-run-id={@late_data_context.run_id}
      data-late-data-policy-execution-mode={@late_data_policy.execution_mode}
      data-late-data-policy-accept-effect={@late_data_policy.accept_effect}
      data-late-data-policy-reject-effect={@late_data_policy.reject_effect}
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="hud-label">Late Data Policy</h3>
        <div class="flex flex-wrap justify-end gap-1">
          <span class="badge badge-xs badge-info">Lifecycle event</span>
          <span class={["badge badge-xs", @late_data_policy.execution_badge_class]}>
            {@late_data_policy.execution_label}
          </span>
        </div>
      </div>
      <div
        :if={@action_outcome_presentation}
        id="dashboard-late-data-policy-action-outcome"
        class="hidden"
        data-late-data-policy-action={@action_outcome_presentation.action}
        data-late-data-policy-action-status={@action_outcome_presentation.status}
        data-late-data-policy-action-kind={@action_outcome_presentation.kind}
        data-late-data-policy-action-reason={@action_outcome_presentation.reason}
        data-late-data-policy-action-decision={
          Map.get(@action_outcome_presentation.metadata, "decision")
        }
        data-late-data-policy-action-execution-mode={
          Map.get(@action_outcome_presentation.metadata, "execution_mode")
        }
        data-late-data-policy-action-dashboard-time-mode={
          Map.get(@action_outcome_presentation.metadata, "dashboard_time_mode")
        }
        data-late-data-policy-action-dashboard-replay-run-id={
          Map.get(@action_outcome_presentation.metadata, "dashboard_replay_run_id")
        }
        data-late-data-policy-action-dashboard-data-view={
          Map.get(@action_outcome_presentation.metadata, "dashboard_data_view")
        }
        data-late-data-policy-action-dashboard-limit-mode={
          Map.get(@action_outcome_presentation.metadata, "dashboard_limit_mode")
        }
        data-late-data-policy-action-result-event-id={
          Map.get(@action_outcome_presentation.metadata, "result_event_id")
        }
        data-late-data-policy-action-target-event-id={
          Map.get(@action_outcome_presentation.metadata, "target_event_id")
        }
        data-late-data-policy-action-target-run-id={
          Map.get(@action_outcome_presentation.metadata, "target_run_id")
        }
      >
        {@action_outcome_presentation.message}
      </div>
      <.form
        for={@late_data_form}
        id="dashboard-late-data-policy-form"
        phx-submit="record_late_data_policy_decision"
        class="space-y-3"
      >
        <input
          id="dashboard-late-data-policy-execution-mode"
          type="hidden"
          name={@late_data_form[:execution_mode].name}
          value={@late_data_policy.execution_mode}
        />
        <input
          id="dashboard-late-data-policy-source-event-id"
          type="hidden"
          name={@late_data_form[:source_event_id].name}
          value={@late_data_context.source_event_id}
        />
        <input
          id="dashboard-late-data-policy-source-event-type"
          type="hidden"
          name={@late_data_form[:source_event_type].name}
          value={@late_data_context.source_event_type}
        />
        <input
          id="dashboard-late-data-policy-run-id"
          type="hidden"
          name={@late_data_form[:run_id].name}
          value={@late_data_context.run_id}
        />
        <input
          id="dashboard-late-data-policy-dashboard-time-mode"
          type="hidden"
          name={@late_data_form[:dashboard_time_mode].name}
          value={@late_data_context.dashboard_time_mode}
        />
        <input
          id="dashboard-late-data-policy-dashboard-replay-run-id"
          type="hidden"
          name={@late_data_form[:dashboard_replay_run_id].name}
          value={@late_data_context.dashboard_replay_run_id}
        />
        <input
          id="dashboard-late-data-policy-dashboard-data-view"
          type="hidden"
          name={@late_data_form[:dashboard_data_view].name}
          value={@late_data_context.dashboard_data_view}
        />
        <input
          id="dashboard-late-data-policy-dashboard-limit-mode"
          type="hidden"
          name={@late_data_form[:dashboard_limit_mode].name}
          value={@late_data_context.dashboard_limit_mode}
        />
        <input
          id="dashboard-late-data-policy-realm"
          type="hidden"
          name={@late_data_form[:realm].name}
          value={@late_data_context.realm}
        />
        <input
          id="dashboard-late-data-policy-data-source-id"
          type="hidden"
          name={@late_data_form[:data_source_id].name}
          value={@late_data_context.data_source_id}
        />
        <input
          id="dashboard-late-data-policy-source-binding-id"
          type="hidden"
          name={@late_data_form[:source_binding_id].name}
          value={@late_data_context.source_binding_id}
        />
        <input
          id="dashboard-late-data-policy-observable-id"
          type="hidden"
          name={@late_data_form[:observable_id].name}
          value={@late_data_context.observable_id}
        />
        <input
          id="dashboard-late-data-policy-point-id"
          type="hidden"
          name={@late_data_form[:point_id].name}
          value={@late_data_context.point_id}
        />
        <input
          id="dashboard-late-data-policy-source-from"
          type="hidden"
          name={@late_data_form[:source_from].name}
          value={@late_data_context.source_from}
        />
        <input
          id="dashboard-late-data-policy-source-to"
          type="hidden"
          name={@late_data_form[:source_to].name}
          value={@late_data_context.source_to}
        />
        <input
          id="dashboard-late-data-policy-receipt-from"
          type="hidden"
          name={@late_data_form[:receipt_from].name}
          value={@late_data_context.receipt_from}
        />
        <input
          id="dashboard-late-data-policy-receipt-to"
          type="hidden"
          name={@late_data_form[:receipt_to].name}
          value={@late_data_context.receipt_to}
        />
        <input
          id="dashboard-late-data-policy-sample-count"
          type="hidden"
          name={@late_data_form[:sample_count].name}
          value={@late_data_context.sample_count}
        />
        <div
          id="dashboard-late-data-policy-effect-preview"
          class="grid grid-cols-1 gap-1 text-[0.68rem] sm:grid-cols-2"
        >
          <div
            class="rounded border border-success/30 bg-success/10 p-2"
            data-late-data-policy-effect="accept"
          >
            <div class="font-semibold uppercase tracking-wide text-success">Accept</div>
            <div class="text-base-content/75" data-late-data-policy-effect-summary="accept">
              {@late_data_policy.accept_effect}
            </div>
          </div>
          <div
            class="rounded border border-warning/30 bg-warning/10 p-2"
            data-late-data-policy-effect="reject"
          >
            <div class="font-semibold uppercase tracking-wide text-warning">Reject</div>
            <div class="text-base-content/75" data-late-data-policy-effect-summary="reject">
              {@late_data_policy.reject_effect}
            </div>
          </div>
        </div>
        <div class="grid grid-cols-1 gap-2">
          <.input
            field={@late_data_form[:decision]}
            type="select"
            label="Decision"
            options={@late_data_policy.decision_options}
            compact
          />
          <.input
            field={@late_data_form[:authority]}
            type="select"
            label="Authority"
            options={@late_data_policy.authority_options}
            compact
          />
          <.input field={@late_data_form[:reason]} type="text" label="Reason" compact />
        </div>
        <label
          id="dashboard-late-data-policy-confirm-row"
          class="flex items-start gap-2 rounded border border-info/40 bg-base-100/70 p-2 text-xs"
        >
          <input
            id="dashboard-late-data-policy-confirm"
            type="checkbox"
            name={@late_data_form[:confirmed].name}
            value="confirmed"
            required
            class="checkbox checkbox-xs mt-0.5"
          />
          <span class="text-base-content/80">
            Confirm late-data policy decision
          </span>
        </label>
        <button
          id="dashboard-late-data-policy-submit"
          type="submit"
          class="btn btn-xs btn-info btn-outline w-full justify-start"
        >
          <.icon name="hero-check-circle" class="h-3.5 w-3.5" /> Apply late-data policy
        </button>
      </.form>
    </section>
    """
  end

  attr :inspector, :map, required: true
  attr :action_outcome, :map, default: nil

  defp revision_decision_controls(assigns) do
    context = RevisionDecisionContext.build(assigns.inspector)
    presentation = RevisionDecisionPresentation.build(context)

    assigns =
      assigns
      |> assign(:decision_context, context)
      |> assign(:decision_presentation, presentation)
      |> assign(
        :action_outcome_presentation,
        DataLinkActionOutcomePresentation.for_action(assigns.action_outcome, :revision_decision)
      )
      |> assign(
        :decision_form,
        to_form(presentation.form_params, as: :revision_decision)
      )

    ~H"""
    <section
      id="dashboard-revision-decision-controls"
      class="space-y-2 rounded border border-warning/40 bg-warning/10 p-2"
      data-revision-decision-observation-identity={@decision_context.observation_identity_id}
      data-revision-decision-source-event={@decision_context.source_decision_event_id}
      data-revision-decision-default-effect={@decision_presentation.default_effect}
    >
      <div
        :if={@action_outcome_presentation}
        id="dashboard-revision-decision-action-outcome"
        class="hidden"
        data-revision-decision-action-status={@action_outcome_presentation.status}
        data-revision-decision-action-kind={@action_outcome_presentation.kind}
        data-revision-decision-action-reason={@action_outcome_presentation.reason}
        data-revision-decision-action-decision={
          Map.get(@action_outcome_presentation.metadata, "decision")
        }
        data-revision-decision-action-dashboard-time-mode={
          Map.get(@action_outcome_presentation.metadata, "dashboard_time_mode")
        }
        data-revision-decision-action-dashboard-replay-run-id={
          Map.get(@action_outcome_presentation.metadata, "dashboard_replay_run_id")
        }
        data-revision-decision-action-dashboard-data-view={
          Map.get(@action_outcome_presentation.metadata, "dashboard_data_view")
        }
        data-revision-decision-action-dashboard-limit-mode={
          Map.get(@action_outcome_presentation.metadata, "dashboard_limit_mode")
        }
        data-revision-decision-action-result-event-id={
          Map.get(@action_outcome_presentation.metadata, "result_event_id")
        }
        data-revision-decision-action-target-event-id={
          Map.get(@action_outcome_presentation.metadata, "target_event_id")
        }
        data-revision-decision-action-target-observation-identity-id={
          Map.get(@action_outcome_presentation.metadata, "target_observation_identity_id")
        }
      >
        {@action_outcome_presentation.message}
      </div>
      <div class="flex items-center justify-between gap-2">
        <h3 class="hud-label">Revision Decision</h3>
        <span class="badge badge-xs badge-warning">Correction authority</span>
      </div>
      <.form
        for={@decision_form}
        id="dashboard-revision-decision-form"
        phx-submit="apply_revision_decision"
        class="space-y-3"
      >
        <input
          id="dashboard-revision-decision-observation-identity-id"
          type="hidden"
          name={@decision_form[:observation_identity_id].name}
          value={@decision_context.observation_identity_id}
        />
        <input
          id="dashboard-revision-decision-source-event-id"
          type="hidden"
          name={@decision_form[:source_decision_event_id].name}
          value={@decision_context.source_decision_event_id}
        />
        <input
          id="dashboard-revision-decision-source-decision"
          type="hidden"
          name={@decision_form[:source_decision].name}
          value={@decision_context.source_decision}
        />
        <input
          id="dashboard-revision-decision-dashboard-limit-mode"
          type="hidden"
          name={@decision_form[:dashboard_limit_mode].name}
          value={@decision_context.dashboard_limit_mode}
        />
        <input
          id="dashboard-revision-decision-dashboard-time-mode"
          type="hidden"
          name={@decision_form[:dashboard_time_mode].name}
          value={@decision_context.dashboard_time_mode}
        />
        <input
          id="dashboard-revision-decision-dashboard-replay-run-id"
          type="hidden"
          name={@decision_form[:dashboard_replay_run_id].name}
          value={@decision_context.dashboard_replay_run_id}
        />
        <input
          id="dashboard-revision-decision-dashboard-data-view"
          type="hidden"
          name={@decision_form[:dashboard_data_view].name}
          value={@decision_context.dashboard_data_view}
        />
        <input
          id="dashboard-revision-decision-source-target"
          type="hidden"
          name={@decision_form[:source_target].name}
          value={@decision_context.source_target}
        />
        <input
          id="dashboard-revision-decision-source-target-id"
          type="hidden"
          name={@decision_form[:source_target_id].name}
          value={@decision_context.source_target_id}
        />
        <input
          id="dashboard-revision-decision-source-link-label"
          type="hidden"
          name={@decision_form[:source_link_label].name}
          value={@decision_context.source_link_label}
        />
        <input
          id="dashboard-revision-decision-comparison-state"
          type="hidden"
          name={@decision_form[:comparison_state].name}
          value={@decision_context.comparison_state}
        />
        <input
          id="dashboard-revision-decision-comparison-delta"
          type="hidden"
          name={@decision_form[:comparison_delta].name}
          value={@decision_context.comparison_delta}
        />
        <input
          id="dashboard-revision-decision-primary-sample"
          type="hidden"
          name={@decision_form[:primary_sample_id].name}
          value={@decision_context.primary_sample_id}
        />
        <input
          id="dashboard-revision-decision-compare-sample"
          type="hidden"
          name={@decision_form[:compare_sample_id].name}
          value={@decision_context.compare_sample_id}
        />
        <input
          id="dashboard-revision-decision-primary-data-view"
          type="hidden"
          name={@decision_form[:primary_data_view].name}
          value={@decision_context.primary_data_view}
        />
        <input
          id="dashboard-revision-decision-compare-data-view"
          type="hidden"
          name={@decision_form[:compare_data_view].name}
          value={@decision_context.compare_data_view}
        />
        <input
          id="dashboard-revision-decision-widget-id"
          type="hidden"
          name={@decision_form[:widget_id].name}
          value={@decision_context.widget_id}
        />
        <input
          id="dashboard-revision-decision-widget-title"
          type="hidden"
          name={@decision_form[:widget_title].name}
          value={@decision_context.widget_title}
        />
        <div
          id="dashboard-revision-decision-effect-preview"
          class="grid grid-cols-1 gap-1 text-[0.68rem] sm:grid-cols-2"
        >
          <div
            :for={decision <- @decision_presentation.effects}
            class={["rounded border p-2", decision.class]}
            data-revision-decision-effect={decision.value}
          >
            <div class="font-semibold uppercase tracking-wide">{decision.label}</div>
            <div
              class="text-base-content/75"
              data-revision-decision-effect-summary={decision.value}
            >
              {decision.effect}
            </div>
          </div>
        </div>
        <div class="grid grid-cols-1 gap-2">
          <.input
            field={@decision_form[:decision]}
            type="select"
            label="Decision"
            options={@decision_presentation.options}
            compact
          />
          <.input field={@decision_form[:realm]} type="text" label="Realm" compact />
          <.input
            field={@decision_form[:data_source_id]}
            type="text"
            label="Data Source"
            compact
          />
          <.input
            field={@decision_form[:source_binding_id]}
            type="text"
            label="Source Binding"
            compact
          />
          <.input
            field={@decision_form[:canonical_observation_id]}
            type="text"
            label="Canonical Observation"
            compact
          />
          <.input
            field={@decision_form[:canonical_sample_id]}
            type="text"
            label="Canonical Sample"
            compact
          />
          <.input
            field={@decision_form[:canonical_revision]}
            type="number"
            label="Canonical Revision"
            compact
          />
          <.input
            field={@decision_form[:decision_reason]}
            type="text"
            label="Reason"
            compact
          />
          <.input
            field={@decision_form[:correction_workflow_id]}
            type="text"
            label="Workflow"
            compact
          />
          <.input field={@decision_form[:authority]} type="text" label="Authority" compact />
        </div>
        <label
          id="dashboard-revision-decision-confirm-row"
          class="flex items-start gap-2 rounded border border-warning/40 bg-base-100/70 p-2 text-xs"
        >
          <input
            id="dashboard-revision-decision-confirm"
            type="checkbox"
            name={@decision_form[:confirmed].name}
            value="confirmed"
            required
            class="checkbox checkbox-xs mt-0.5"
          />
          <span class="text-base-content/80">
            Confirm telemetry revision decision
          </span>
        </label>
        <button
          id="dashboard-revision-decision-submit"
          type="submit"
          class="btn btn-xs btn-warning btn-outline w-full justify-start"
        >
          <.icon name="hero-check-circle" class="h-3.5 w-3.5" /> Apply revision decision
        </button>
      </.form>
    </section>
    """
  end

  attr :groups, :list, required: true
  attr :inspector, :map, required: true

  defp related_data_links(assigns) do
    ~H"""
    <section class="space-y-2" data-data-link-related-links>
      <h3 class="hud-label">Related</h3>
      <div class="space-y-3">
        <div
          :for={group <- @groups}
          class="space-y-1"
          data-data-link-related-group={group.key}
        >
          <div class="flex items-center justify-between gap-2">
            <h4 class="text-[0.65rem] font-semibold uppercase tracking-normal text-base-content/50">
              {group.label}
            </h4>
            <span class="font-mono text-[0.65rem] text-base-content/40">
              {length(group.links)}
            </span>
          </div>
          <button
            :for={link <- group.links}
            type="button"
            phx-click="open_data_link"
            {DataLinkAttrs.open(link, DataLinkPresentation.navigation_event_attrs(@inspector, link))}
            class="grid w-full grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100"
            data-data-link-related-target={link.target_text}
            data-data-link-related-id={link.target_id || ""}
            data-data-link-related-ref={link.link_id || ""}
            data-data-link-related-kind={DataLinkInspectorPanelPresentation.relationship_kind_text(link.relationship_kind)}
          >
            <span class="text-base-content/60">{link.target_text}</span>
            <span class="font-mono text-base-content break-all">{link.target_id}</span>
            <span class="text-base-content/60">Label</span>
            <span class="text-base-content break-all">{link.label}</span>
          </button>
        </div>
      </div>
    </section>
    """
  end

  attr :inspector, :map, required: true
  attr :trail, :list, required: true

  defp navigation_breadcrumb(assigns) do
    ~H"""
    <section class="space-y-2" data-data-link-navigation>
      <h3 class="hud-label">Navigation</h3>
      <button
        :for={{entry, index} <- Enum.with_index(@trail)}
        :if={entry.back_link}
        type="button"
        phx-click="open_data_link"
        {DataLinkAttrs.open(entry.back_link, DataLinkPresentation.navigation_event_attrs(@inspector, entry.back_link))}
        class="grid w-full grid-cols-[5rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100"
        data-data-link-nav-entry-index={index}
        data-data-link-nav-entry-target={entry.target || ""}
        data-data-link-nav-entry-id={entry.target_id || ""}
        data-data-link-nav-entry-kind={Map.get(entry, :relationship_kind) || ""}
        data-data-link-nav-from-target={entry.target || ""}
        data-data-link-nav-from-id={entry.target_id || ""}
        data-data-link-nav-from-kind={Map.get(entry, :relationship_kind) || ""}
      >
        <span class="text-base-content/60">From</span>
        <span class="font-mono text-base-content break-all">{entry.target_id}</span>
        <span class="text-base-content/60">Via</span>
        <span class="text-base-content break-all">
          {Map.get(entry, :relationship_label) || Map.get(entry, :relationship_kind) ||
            entry.label || entry.target}
        </span>
      </button>
    </section>
    """
  end

  attr :actions, :list, required: true

  defp dashboard_actions(assigns) do
    ~H"""
    <.link
      :for={%DashboardAction{} = action <- DashboardActionPresentation.visible(@actions)}
      id={action.action_id}
      navigate={action.route}
      class="btn btn-sm btn-outline w-full justify-start"
      data-dashboard-action={action.action_id}
      data-dashboard-action-kind={Atom.to_string(action.kind)}
      data-dashboard-action-target={Atom.to_string(action.target)}
      data-dashboard-action-source={Atom.to_string(action.source)}
      data-dashboard-action-presentation={Atom.to_string(action.presentation)}
    >
      <.icon name={DashboardActionPresentation.icon(action)} class="h-4 w-4" /> {action.label}
    </.link>
    """
  end
end
