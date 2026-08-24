defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation do
  @moduledoc false

  alias Cadence.Dashboards.DashboardAction
  alias CadenceWeb.OpsDashboardShowLive.DashboardActionPresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs
  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowContext
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowExplanation
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyContext
  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicyPresentation
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionContext
  alias CadenceWeb.OpsDashboardShowLive.RevisionDecisionPresentation

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  @empty_panel_attrs %{
    target: "",
    target_id: "",
    status: "",
    selected_link: "",
    selected_realm: "",
    selected_data_view: "",
    selected_data_source_id: "",
    selected_source_binding_id: "",
    selected_time_mode: "",
    selected_time_axis: "",
    selected_replay_run_id: ""
  }

  @late_data_hidden_fields [
    {:execution_mode, "dashboard-late-data-policy-execution-mode"},
    {:source_event_id, "dashboard-late-data-policy-source-event-id"},
    {:source_event_type, "dashboard-late-data-policy-source-event-type"},
    {:run_id, "dashboard-late-data-policy-run-id"},
    {:dashboard_time_mode, "dashboard-late-data-policy-dashboard-time-mode"},
    {:dashboard_replay_run_id, "dashboard-late-data-policy-dashboard-replay-run-id"},
    {:dashboard_data_view, "dashboard-late-data-policy-dashboard-data-view"},
    {:dashboard_limit_mode, "dashboard-late-data-policy-dashboard-limit-mode"},
    {:realm, "dashboard-late-data-policy-realm"},
    {:data_source_id, "dashboard-late-data-policy-data-source-id"},
    {:source_binding_id, "dashboard-late-data-policy-source-binding-id"},
    {:observable_id, "dashboard-late-data-policy-observable-id"},
    {:point_id, "dashboard-late-data-policy-point-id"},
    {:source_from, "dashboard-late-data-policy-source-from"},
    {:source_to, "dashboard-late-data-policy-source-to"},
    {:receipt_from, "dashboard-late-data-policy-receipt-from"},
    {:receipt_to, "dashboard-late-data-policy-receipt-to"},
    {:sample_count, "dashboard-late-data-policy-sample-count"}
  ]

  @revision_hidden_fields [
    {:observation_identity_id, "dashboard-revision-decision-observation-identity-id"},
    {:source_decision_event_id, "dashboard-revision-decision-source-event-id"},
    {:source_decision, "dashboard-revision-decision-source-decision"},
    {:dashboard_limit_mode, "dashboard-revision-decision-dashboard-limit-mode"},
    {:dashboard_time_mode, "dashboard-revision-decision-dashboard-time-mode"},
    {:dashboard_replay_run_id, "dashboard-revision-decision-dashboard-replay-run-id"},
    {:dashboard_data_view, "dashboard-revision-decision-dashboard-data-view"},
    {:source_target, "dashboard-revision-decision-source-target"},
    {:source_target_id, "dashboard-revision-decision-source-target-id"},
    {:source_link_label, "dashboard-revision-decision-source-link-label"},
    {:comparison_state, "dashboard-revision-decision-comparison-state"},
    {:comparison_delta, "dashboard-revision-decision-comparison-delta"},
    {:primary_sample_id, "dashboard-revision-decision-primary-sample"},
    {:compare_sample_id, "dashboard-revision-decision-compare-sample"},
    {:primary_data_view, "dashboard-revision-decision-primary-data-view"},
    {:compare_data_view, "dashboard-revision-decision-compare-data-view"},
    {:widget_id, "dashboard-revision-decision-widget-id"},
    {:widget_title, "dashboard-revision-decision-widget-title"}
  ]

  @revision_input_fields [
    {:decision, "select", "Decision"},
    {:realm, "text", "Realm"},
    {:data_source_id, "text", "Data Source"},
    {:source_binding_id, "text", "Source Binding"},
    {:canonical_observation_id, "text", "Canonical Observation"},
    {:canonical_sample_id, "text", "Canonical Sample"},
    {:canonical_revision, "number", "Canonical Revision"},
    {:decision_reason, "text", "Reason"},
    {:correction_workflow_id, "text", "Workflow"},
    {:authority, "text", "Authority"}
  ]

  def build(inspector, mission_id, dashboard_document, action_outcome \\ nil) do
    panel = DataLinkPresentation.panel(inspector)

    %{
      panel: panel,
      panel_attrs: panel_attrs(inspector, panel),
      data_link_actions:
        DashboardActionPresentation.for_inspector(
          inspector,
          mission_id,
          :data_link_panel,
          dashboard_document
        ),
      action_outcome: DataLinkActionOutcomePresentation.build(action_outcome)
    }
  end

  def for_vue(
        inspector,
        mission_id,
        dashboard_document,
        dashboard_current_path,
        action_outcome \\ nil
      ) do
    base = build(inspector, mission_id, dashboard_document, action_outcome)
    panel = base.panel

    %{
      root: %{attrs: root_attrs(base.panel_attrs)},
      header: header_dto(inspector),
      clipboard: clipboard_dto(dashboard_current_path),
      actions: actions_dto(base.data_link_actions),
      action_outcome: action_outcome_dto(base.action_outcome),
      selection: rows_section_dto(panel.selection_summary_rows, "Selection", :selection),
      workflow_explanation: workflow_explanation_dto(inspector, panel),
      revision_decision: revision_decision_dto(inspector, panel, action_outcome),
      late_data_policy: late_data_policy_dto(inspector, panel, action_outcome),
      historical_workflow_navigation:
        historical_workflow_navigation_dto(inspector, mission_id, panel),
      navigation: navigation_dto(inspector, panel),
      record: rows_section_dto(inspector_value(inspector, :rows, []), "Record", :record),
      related: related_dto(inspector, panel),
      runtime_context:
        rows_section_dto(
          inspector_value(inspector, :context_rows, []),
          "Runtime Context",
          :runtime_context
        )
    }
  end

  def panel_attrs(inspector, panel) when is_map(inspector) and is_map(panel) do
    selection_summary = map_value(panel, :selection_summary) || %{}

    %{
      target: attr_text(inspector_value(inspector, :target)),
      target_id: attr_text(inspector_value(inspector, :target_id)),
      status: attr_text(inspector_value(inspector, :status_text)),
      selected_link: attr_text(map_value(selection_summary, :link_id)),
      selected_realm: attr_text(map_value(selection_summary, :realm)),
      selected_data_view: attr_text(map_value(selection_summary, :data_view)),
      selected_data_source_id: attr_text(map_value(selection_summary, :data_source_id)),
      selected_source_binding_id: attr_text(map_value(selection_summary, :source_binding_id)),
      selected_time_mode: attr_text(map_value(selection_summary, :time_mode)),
      selected_time_axis: attr_text(map_value(selection_summary, :time_axis)),
      selected_replay_run_id: attr_text(map_value(selection_summary, :replay_run_id))
    }
  end

  def panel_attrs(_inspector, _panel), do: @empty_panel_attrs

  def relationship_kind_text(nil), do: nil
  def relationship_kind_text(kind) when is_atom(kind), do: Atom.to_string(kind)
  def relationship_kind_text(kind) when is_binary(kind), do: kind
  def relationship_kind_text(_kind), do: nil

  def bool_attr(true), do: "true"
  def bool_attr(_value), do: "false"

  def present_text?(value), do: is_binary(value) and value != ""

  defp root_attrs(panel_attrs) do
    %{
      :id => "dashboard-data-link-inspector",
      :class => "space-y-4",
      "data-data-link-target" => panel_attrs.target,
      "data-data-link-target-id" => panel_attrs.target_id,
      "data-data-link-status" => panel_attrs.status,
      "data-data-link-selected-link" => panel_attrs.selected_link,
      "data-data-link-selected-realm" => panel_attrs.selected_realm,
      "data-data-link-selected-data-view" => panel_attrs.selected_data_view,
      "data-data-link-selected-data-source-id" => panel_attrs.selected_data_source_id,
      "data-data-link-selected-source-binding-id" => panel_attrs.selected_source_binding_id,
      "data-data-link-selected-time-mode" => panel_attrs.selected_time_mode,
      "data-data-link-selected-time-axis" => panel_attrs.selected_time_axis,
      "data-data-link-selected-replay-run-id" => panel_attrs.selected_replay_run_id
    }
  end

  defp header_dto(inspector) do
    %{
      class: "space-y-1",
      badges_class: "flex items-center gap-2",
      target: %{
        class: "badge badge-xs badge-outline",
        text: attr_text(inspector_value(inspector, :target_text))
      },
      status: %{
        class: "badge badge-xs",
        text: attr_text(inspector_value(inspector, :status_text))
      },
      message: text_dto(inspector_value(inspector, :message), "text-sm text-base-content/70")
    }
  end

  defp clipboard_dto(dashboard_current_path) do
    %{
      button_id: "dashboard-data-link-copy-link",
      clipboard_text: dashboard_current_path,
      button_class: "btn btn-sm btn-outline w-full justify-start",
      icon: "hero-link",
      icon_class: "h-4 w-4",
      label: "Copy link"
    }
  end

  defp actions_dto(actions) do
    actions
    |> DashboardActionPresentation.visible()
    |> Enum.map(fn %DashboardAction{} = action ->
      %{
        attrs: %{
          :id => action.action_id,
          :href => action.route,
          :class => "btn btn-sm btn-outline w-full justify-start",
          "data-phx-link" => "redirect",
          "data-phx-link-state" => "push",
          "data-dashboard-action" => action.action_id,
          "data-dashboard-action-kind" => Atom.to_string(action.kind),
          "data-dashboard-action-target" => Atom.to_string(action.target),
          "data-dashboard-action-source" => Atom.to_string(action.source),
          "data-dashboard-action-presentation" => Atom.to_string(action.presentation)
        },
        icon_class: "#{DashboardActionPresentation.icon(action)} h-4 w-4",
        label: action.label
      }
    end)
  end

  defp action_outcome_dto(nil), do: nil

  defp action_outcome_dto(outcome) do
    %{
      attrs:
        outcome
        |> DataLinkActionOutcomePresentation.stable_attrs(
          "data-data-link-action-outcome",
          action_suffix: "action"
        )
        |> Map.merge(%{id: "dashboard-data-link-action-outcome", class: "hidden"}),
      message: outcome.message
    }
  end

  defp rows_section_dto([], _heading, _kind), do: nil
  defp rows_section_dto(nil, _heading, _kind), do: nil

  defp rows_section_dto(rows, heading, kind) when is_list(rows) do
    %{
      attrs: rows_section_attrs(kind),
      heading: %{class: "hud-label", text: heading},
      list_class: "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
      rows:
        Enum.map(rows, fn row ->
          label = attr_text(map_value(row, :label))

          %{
            key: label,
            label: %{class: "text-base-content/60", text: label},
            value: %{
              class: "font-mono text-base-content break-all",
              text: attr_text(map_value(row, :value)),
              attrs: row_value_attrs(kind, label)
            }
          }
        end)
    }
  end

  defp rows_section_attrs(:selection),
    do: %{:class => "space-y-2", "data-data-link-selection" => ""}

  defp rows_section_attrs(_kind), do: %{class: "space-y-2"}

  defp row_value_attrs(:selection, label), do: %{"data-data-link-selection-field" => label}
  defp row_value_attrs(:record, label), do: %{"data-data-link-field" => label}
  defp row_value_attrs(:runtime_context, label), do: %{"data-data-link-context" => label}

  defp workflow_explanation_dto(_inspector, %{workflow_explanation?: false}), do: nil

  defp workflow_explanation_dto(inspector, _panel) do
    context = HistoricalWorkflowContext.build(inspector)
    explanation = HistoricalWorkflowExplanation.build(context)

    %{
      attrs: %{
        :id => "dashboard-workflow-explanation",
        :class => "space-y-2 rounded border p-2 #{explanation.container_class}",
        "data-workflow-explanation-event-id" => context.event_id,
        "data-workflow-explanation-event-type" => context.event_type,
        "data-workflow-explanation-run-id" => context.run_id,
        "data-workflow-explanation-state" => attr_text(explanation.summary.state),
        "data-workflow-explanation-severity" => attr_text(explanation.summary.severity)
      },
      header: %{
        class: "flex items-center justify-between gap-2",
        heading: %{class: "hud-label", text: "Workflow Explanation"},
        badge: %{
          class: "badge badge-xs #{explanation.badge_class}",
          text: explanation.summary.badge
        }
      },
      summary: %{
        attrs: %{
          id: "dashboard-workflow-explanation-summary",
          class: "text-xs leading-5 text-base-content/80"
        },
        text: explanation.summary.summary
      },
      list_class: "grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
      rows:
        Enum.map(explanation.rows, fn row ->
          %{
            key: row.label,
            label: %{class: "text-base-content/60", text: row.label},
            value: %{
              class: "font-mono text-base-content break-all",
              text: attr_text(row.value),
              attrs: %{"data-workflow-explanation-field" => row.label}
            }
          }
        end)
    }
  end

  defp late_data_policy_dto(_inspector, %{late_data_policy_controls?: false}, _outcome),
    do: nil

  defp late_data_policy_dto(inspector, _panel, outcome) do
    context = LateDataPolicyContext.build(inspector)
    policy = LateDataPolicyPresentation.build(context)
    form = Phoenix.Component.to_form(policy.form_params, as: :late_data_policy)

    %{
      attrs: %{
        :id => "dashboard-late-data-policy-controls",
        :class => "space-y-2 rounded border border-info/40 bg-info/10 p-2",
        "data-late-data-policy-source-event" => context.source_event_id,
        "data-late-data-policy-run-id" => context.run_id,
        "data-late-data-policy-execution-mode" => policy.execution_mode,
        "data-late-data-policy-accept-effect" => policy.accept_effect,
        "data-late-data-policy-reject-effect" => policy.reject_effect
      },
      header: %{
        class: "flex items-center justify-between gap-2",
        heading: %{class: "hud-label", text: "Late Data Policy"},
        badges_class: "flex flex-wrap justify-end gap-1",
        lifecycle_badge: %{class: "badge badge-xs badge-info", text: "Lifecycle event"},
        execution_badge: %{
          class: "badge badge-xs #{policy.execution_badge_class}",
          text: policy.execution_label
        }
      },
      action_outcome:
        late_data_action_outcome_dto(
          DataLinkActionOutcomePresentation.for_action(outcome, :late_data_policy)
        ),
      form: late_data_form_dto(form, policy),
      effects: late_data_effects_dto(policy)
    }
  end

  defp late_data_form_dto(form, policy) do
    %{
      attrs: %{
        :id => "dashboard-late-data-policy-form",
        "phx-submit" => "record_late_data_policy_decision",
        :class => "space-y-3"
      },
      hidden_fields: hidden_fields_dto(form, policy.form_params, @late_data_hidden_fields),
      fields: [
        select_field_dto(form[:decision], "Decision", policy.decision_options),
        select_field_dto(form[:authority], "Authority", policy.authority_options),
        input_field_dto(form[:reason], "text", "Reason")
      ],
      confirmation:
        confirmation_dto(
          form[:confirmed],
          "dashboard-late-data-policy-confirm-row",
          "dashboard-late-data-policy-confirm",
          "border-info/40",
          "Confirm late-data policy decision"
        ),
      submit: %{
        attrs: %{
          id: "dashboard-late-data-policy-submit",
          type: "submit",
          class: "btn btn-xs btn-info btn-outline w-full justify-start"
        },
        icon_class: "hero-check-circle h-3.5 w-3.5",
        text: "Apply late-data policy"
      }
    }
  end

  defp late_data_effects_dto(policy) do
    [
      effect_dto(
        "accept",
        "Accept",
        policy.accept_effect,
        "rounded border border-success/30 bg-success/10 p-2",
        "font-semibold uppercase tracking-wide text-success",
        "data-late-data-policy-effect",
        "data-late-data-policy-effect-summary"
      ),
      effect_dto(
        "reject",
        "Reject",
        policy.reject_effect,
        "rounded border border-warning/30 bg-warning/10 p-2",
        "font-semibold uppercase tracking-wide text-warning",
        "data-late-data-policy-effect",
        "data-late-data-policy-effect-summary"
      )
    ]
  end

  defp late_data_action_outcome_dto(nil), do: nil

  defp late_data_action_outcome_dto(outcome) do
    %{
      attrs: %{
        :id => "dashboard-late-data-policy-action-outcome",
        :class => "hidden",
        "data-late-data-policy-action" => outcome.action,
        "data-late-data-policy-action-status" => outcome.status,
        "data-late-data-policy-action-kind" => outcome.kind,
        "data-late-data-policy-action-reason" => outcome.reason,
        "data-late-data-policy-action-decision" => outcome.metadata["decision"],
        "data-late-data-policy-action-execution-mode" => outcome.metadata["execution_mode"],
        "data-late-data-policy-action-dashboard-time-mode" =>
          outcome.metadata["dashboard_time_mode"],
        "data-late-data-policy-action-dashboard-replay-run-id" =>
          outcome.metadata["dashboard_replay_run_id"],
        "data-late-data-policy-action-dashboard-data-view" =>
          outcome.metadata["dashboard_data_view"],
        "data-late-data-policy-action-dashboard-limit-mode" =>
          outcome.metadata["dashboard_limit_mode"],
        "data-late-data-policy-action-result-event-id" => outcome.metadata["result_event_id"],
        "data-late-data-policy-action-target-event-id" => outcome.metadata["target_event_id"],
        "data-late-data-policy-action-target-run-id" => outcome.metadata["target_run_id"]
      },
      message: outcome.message
    }
  end

  defp revision_decision_dto(_inspector, %{revision_decision_controls?: false}, _outcome),
    do: nil

  defp revision_decision_dto(inspector, _panel, outcome) do
    context = RevisionDecisionContext.build(inspector)
    decision = RevisionDecisionPresentation.build(context)
    form = Phoenix.Component.to_form(decision.form_params, as: :revision_decision)

    %{
      attrs: %{
        :id => "dashboard-revision-decision-controls",
        :class => "space-y-2 rounded border border-warning/40 bg-warning/10 p-2",
        "data-revision-decision-observation-identity" => context.observation_identity_id,
        "data-revision-decision-source-event" => context.source_decision_event_id,
        "data-revision-decision-default-effect" => decision.default_effect
      },
      action_outcome:
        revision_action_outcome_dto(
          DataLinkActionOutcomePresentation.for_action(outcome, :revision_decision)
        ),
      header: %{
        class: "flex items-center justify-between gap-2",
        heading: %{class: "hud-label", text: "Revision Decision"},
        badge: %{class: "badge badge-xs badge-warning", text: "Correction authority"}
      },
      form: revision_form_dto(form, decision),
      effects: revision_effects_dto(decision.effects)
    }
  end

  defp revision_form_dto(form, decision) do
    %{
      attrs: %{
        :id => "dashboard-revision-decision-form",
        "phx-submit" => "apply_revision_decision",
        :class => "space-y-3"
      },
      hidden_fields: hidden_fields_dto(form, decision.form_params, @revision_hidden_fields),
      fields:
        Enum.map(@revision_input_fields, fn
          {:decision, "select", label} ->
            select_field_dto(form[:decision], label, decision.options)

          {key, type, label} ->
            input_field_dto(form[key], type, label)
        end),
      confirmation:
        confirmation_dto(
          form[:confirmed],
          "dashboard-revision-decision-confirm-row",
          "dashboard-revision-decision-confirm",
          "border-warning/40",
          "Confirm telemetry revision decision"
        ),
      submit: %{
        attrs: %{
          id: "dashboard-revision-decision-submit",
          type: "submit",
          class: "btn btn-xs btn-warning btn-outline w-full justify-start"
        },
        icon_class: "hero-check-circle h-3.5 w-3.5",
        text: "Apply revision decision"
      }
    }
  end

  defp revision_effects_dto(effects) do
    Enum.map(effects, fn effect ->
      effect_dto(
        effect.value,
        effect.label,
        effect.effect,
        "rounded border p-2 #{effect.class}",
        "font-semibold uppercase tracking-wide",
        "data-revision-decision-effect",
        "data-revision-decision-effect-summary"
      )
    end)
  end

  defp revision_action_outcome_dto(nil), do: nil

  defp revision_action_outcome_dto(outcome) do
    %{
      attrs: %{
        :id => "dashboard-revision-decision-action-outcome",
        :class => "hidden",
        "data-revision-decision-action-status" => outcome.status,
        "data-revision-decision-action-kind" => outcome.kind,
        "data-revision-decision-action-reason" => outcome.reason,
        "data-revision-decision-action-decision" => outcome.metadata["decision"],
        "data-revision-decision-action-dashboard-time-mode" =>
          outcome.metadata["dashboard_time_mode"],
        "data-revision-decision-action-dashboard-replay-run-id" =>
          outcome.metadata["dashboard_replay_run_id"],
        "data-revision-decision-action-dashboard-data-view" =>
          outcome.metadata["dashboard_data_view"],
        "data-revision-decision-action-dashboard-limit-mode" =>
          outcome.metadata["dashboard_limit_mode"],
        "data-revision-decision-action-result-event-id" => outcome.metadata["result_event_id"],
        "data-revision-decision-action-target-event-id" => outcome.metadata["target_event_id"],
        "data-revision-decision-action-target-observation-identity-id" =>
          outcome.metadata["target_observation_identity_id"]
      },
      message: outcome.message
    }
  end

  defp hidden_fields_dto(form, params, fields) do
    Enum.map(fields, fn {key, id} ->
      %{
        id: id,
        type: "hidden",
        name: form[key].name,
        value: Map.get(params, Atom.to_string(key), "")
      }
    end)
  end

  defp select_field_dto(field, label, options) do
    %{
      wrapper_class: "fieldset",
      label: %{class: "hud-label block mb-1.5", text: label},
      attrs: %{
        id: field.id,
        name: field.name,
        required: false,
        multiple: false,
        class: "w-full select"
      },
      options:
        Enum.map(options, fn {option_label, option_value} ->
          %{
            label: option_label,
            value: to_string(option_value),
            selected: to_string(field.value) == to_string(option_value),
            disabled: false,
            title: nil
          }
        end)
    }
  end

  defp input_field_dto(field, type, label) do
    %{
      wrapper_class: "fieldset",
      label: %{class: "hud-label block mb-1.5", text: label},
      attrs: %{
        id: field.id,
        name: field.name,
        type: type,
        value: field.value,
        required: false,
        class: "w-full input"
      }
    }
  end

  defp confirmation_dto(field, row_id, input_id, border_class, label) do
    %{
      row: %{
        attrs: %{
          id: row_id,
          class:
            "flex items-start gap-2 rounded border #{border_class} bg-base-100/70 p-2 text-xs"
        }
      },
      input: %{
        attrs: %{
          id: input_id,
          type: "checkbox",
          name: field.name,
          value: "confirmed",
          required: true,
          class: "checkbox checkbox-xs mt-0.5"
        }
      },
      label: %{class: "text-base-content/80", text: label}
    }
  end

  defp effect_dto(value, label, summary, class, label_class, effect_attr, summary_attr) do
    %{
      attrs: %{effect_attr => value, class: class},
      label: %{class: label_class, text: label},
      summary: %{attrs: %{summary_attr => value, class: "text-base-content/75"}, text: summary}
    }
  end

  defp historical_workflow_navigation_dto(
         _inspector,
         _mission_id,
         %{historical_workflow_controls?: false}
       ),
       do: nil

  defp historical_workflow_navigation_dto(inspector, mission_id, _panel) do
    %{
      attrs: %{
        :id => "dashboard-workflow-open-data-operations",
        :href => data_operations_path(inspector, mission_id),
        :class => "btn btn-sm btn-outline w-full justify-start",
        "data-phx-link" => "redirect",
        "data-phx-link-state" => "push"
      },
      icon_class: "hero-arrow-path-rounded-square h-4 w-4",
      text: "Continue in Data Operations"
    }
  end

  defp data_operations_path(inspector, mission_id) do
    context = HistoricalWorkflowContext.build(inspector)

    query =
      %{
        "group" => context.request_group_id || context.run_id,
        "workflow" => context.workflow,
        "run_id" => context.run_id,
        "realm" => context.realm,
        "data_source_id" => context.data_source_id,
        "source_binding_id" => context.source_binding_id,
        "observable_id" => context.observable_id,
        "point_id" => context.point_id,
        "point_ids" => context.point_id,
        "source_from" => context.source_from,
        "source_to" => context.source_to,
        "dashboard_id" => context.dashboard_id,
        "dashboard_version" => context.dashboard_version,
        "dashboard_time_mode" => context.dashboard_time_mode,
        "dashboard_replay_run_id" => context.dashboard_replay_run_id,
        "dashboard_data_view" => context.dashboard_data_view,
        "dashboard_limit_mode" => context.dashboard_limit_mode,
        "reason" => context.reason
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/missions/#{mission_id}/ops/data-operations?#{query}"
  end

  defp navigation_dto(_inspector, %{navigation: nil}), do: nil

  defp navigation_dto(inspector, panel) do
    entries =
      panel.navigation_trail
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, index} ->
        case map_value(entry, :back_link) do
          back_link when is_map(back_link) ->
            event_attrs =
              DataLinkAttrs.open(
                back_link,
                DataLinkPresentation.navigation_event_attrs(inspector, back_link)
              )

            [navigation_entry_dto(entry, index, event_attrs)]

          _missing ->
            []
        end
      end)

    %{
      attrs: %{:class => "space-y-2", "data-data-link-navigation" => ""},
      heading: %{class: "hud-label", text: "Navigation"},
      entries: entries
    }
  end

  defp navigation_entry_dto(entry, index, event_attrs) do
    %{
      attrs:
        Map.merge(event_attrs, %{
          :type => "button",
          "phx-click" => "open_data_link",
          :class =>
            "grid w-full grid-cols-[5rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100",
          "data-data-link-nav-entry-index" => index,
          "data-data-link-nav-entry-target" => attr_text(map_value(entry, :target)),
          "data-data-link-nav-entry-id" => attr_text(map_value(entry, :target_id)),
          "data-data-link-nav-entry-kind" => attr_text(map_value(entry, :relationship_kind)),
          "data-data-link-nav-from-target" => attr_text(map_value(entry, :target)),
          "data-data-link-nav-from-id" => attr_text(map_value(entry, :target_id)),
          "data-data-link-nav-from-kind" => attr_text(map_value(entry, :relationship_kind))
        }),
      from: attr_text(map_value(entry, :target_id)),
      via:
        attr_text(
          map_value(entry, :relationship_label) || map_value(entry, :relationship_kind) ||
            map_value(entry, :label) || map_value(entry, :target)
        )
    }
  end

  defp related_dto(_inspector, %{related_groups: []}), do: nil

  defp related_dto(inspector, panel) do
    %{
      attrs: %{:class => "space-y-2", "data-data-link-related-links" => ""},
      heading: %{class: "hud-label", text: "Related"},
      groups_class: "space-y-3",
      groups: Enum.map(panel.related_groups, &related_group_dto(&1, inspector))
    }
  end

  defp related_group_dto(group, inspector) do
    %{
      attrs: %{:class => "space-y-1", "data-data-link-related-group" => group.key},
      header_class: "flex items-center justify-between gap-2",
      heading: %{
        class: "text-[0.65rem] font-semibold uppercase tracking-normal text-base-content/50",
        text: group.label
      },
      count: %{
        class: "font-mono text-[0.65rem] text-base-content/40",
        text: Integer.to_string(length(group.links))
      },
      links: Enum.map(group.links, &related_link_dto(&1, inspector))
    }
  end

  defp related_link_dto(link, inspector) do
    event_attrs =
      DataLinkAttrs.open(link, DataLinkPresentation.navigation_event_attrs(inspector, link))

    %{
      attrs:
        Map.merge(event_attrs, %{
          :type => "button",
          "phx-click" => "open_data_link",
          :class =>
            "grid w-full grid-cols-[7rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left text-xs hover:border-primary/60 hover:bg-base-100",
          "data-data-link-related-target" => attr_text(map_value(link, :target_text)),
          "data-data-link-related-id" => attr_text(map_value(link, :target_id)),
          "data-data-link-related-ref" => attr_text(map_value(link, :link_id)),
          "data-data-link-related-kind" =>
            relationship_kind_text(map_value(link, :relationship_kind))
        }),
      target: attr_text(map_value(link, :target_text)),
      target_id: attr_text(map_value(link, :target_id)),
      label: attr_text(map_value(link, :label))
    }
  end

  defp text_dto(value, class) when is_binary(value) and value != "",
    do: %{class: class, text: value}

  defp text_dto(_value, _class), do: nil

  defp inspector_value(inspector, key, default \\ nil) do
    map_value(inspector, key, default)
  end

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_value(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp map_value(_map, _key, default), do: default

  defp attr_text(nil), do: ""
  defp attr_text(value) when is_atom(value), do: Atom.to_string(value)
  defp attr_text(value) when is_integer(value), do: Integer.to_string(value)
  defp attr_text(value) when is_binary(value), do: value
  defp attr_text(value), do: to_string(value)
end
