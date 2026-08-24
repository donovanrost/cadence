defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStartPresentation

  @hidden_fields [
    :workflow,
    :request_group_id,
    :realm,
    :data_source_id,
    :source_binding_id,
    :dashboard_id,
    :dashboard_version,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_data_view,
    :dashboard_limit_mode,
    :comparison_review_request_event_id,
    :comparison_review_request_kind,
    :comparison_review_open_count,
    :comparison_review_open_placement_ids,
    :comparison_review_workflow_kind,
    :comparison_review_workflow_action,
    :comparison_review_workflow_selection_kind,
    :comparison_review_workflow_selection_count,
    :comparison_review_primary_data_view,
    :comparison_review_compare_data_view,
    :comparison_review_scope_kind,
    :comparison_review_scope_ids,
    :comparison_review_contact_ids,
    :comparison_review_resource_ids,
    :comparison_review_transport_ids,
    :comparison_review_source_endpoint_ids,
    :comparison_review_ground_station_ids,
    :comparison_review_scope_link_ids
  ]

  @required_context_fields [
    :workflow,
    :request_group_id,
    :realm,
    :data_source_id,
    :source_binding_id,
    :dashboard_id,
    :dashboard_version,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_data_view,
    :dashboard_limit_mode,
    :comparison_review_request_event_id,
    :comparison_review_request_kind,
    :comparison_review_open_count,
    :comparison_review_open_placement_ids
  ]

  @direct_context_values [:workflow, :realm, :data_source_id, :source_binding_id]

  @review_fields [
    {:request, :comparison_review_request_event_id},
    {:kind, :comparison_review_request_kind},
    {:open_count, :comparison_review_open_count},
    {:placements, :comparison_review_open_placement_ids},
    {:workflow_kind, :comparison_review_workflow_kind},
    {:workflow_action, :comparison_review_workflow_action},
    {:workflow_selection_kind, :comparison_review_workflow_selection_kind},
    {:workflow_selection_count, :comparison_review_workflow_selection_count},
    {:primary_data_view, :comparison_review_primary_data_view},
    {:compare_data_view, :comparison_review_compare_data_view},
    {:scope_kind, :comparison_review_scope_kind},
    {:scope_ids, :comparison_review_scope_ids},
    {:contact_ids, :comparison_review_contact_ids},
    {:resource_ids, :comparison_review_resource_ids},
    {:transport_ids, :comparison_review_transport_ids},
    {:source_endpoint_ids, :comparison_review_source_endpoint_ids},
    {:ground_station_ids, :comparison_review_ground_station_ids},
    {:scope_link_ids, :comparison_review_scope_link_ids}
  ]

  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:workflow_context, :map, required: true)
  attr(:workflow_controls, :map, required: true)

  def group_transition_form(assigns) do
    group_start =
      HistoricalWorkflowGroupStartPresentation.build(
        assigns.workflow_context,
        assigns.workflow_controls
      )

    presentation =
      if assigns.workflow_controls.group_actions do
        group_transition_form_dto(
          assigns.form,
          assigns.workflow_context,
          assigns.workflow_controls,
          group_start
        )
      end

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      :if={@workflow_controls.group_actions}
      id="historical-workflow-group-form-component"
      v-component="HistoricalWorkflowGroupForm"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp group_transition_form_dto(form, workflow_context, workflow_controls, group_start) do
    actions = Map.fetch!(workflow_controls, :group_stage_actions)
    request_item_count = Map.fetch!(workflow_context, :request_item_count)

    %{
      root: %{
        id: "dashboard-historical-workflow-group-form",
        class: "space-y-3 rounded border border-primary/30 bg-primary/5 p-2",
        attrs: %{"phx-submit" => "record_historical_workflow_group_stage"}
      },
      hidden_fields: Enum.map(@hidden_fields, &hidden_field_dto(form, workflow_context, &1)),
      header: %{
        class: "flex items-center justify-between gap-2",
        title: %{class: "hud-label", text: "Group Actions"},
        count: %{
          class: "badge badge-xs badge-primary",
          text: "#{request_item_count} items"
        }
      },
      eligible_items: eligible_items_dto(workflow_context, actions),
      start_orchestration: start_orchestration_dto(workflow_context, group_start),
      reason: reason_field_dto(form, workflow_context),
      confirmation: confirmation_dto(form),
      actions: %{
        class: "grid grid-cols-2 gap-2",
        items: Enum.map(actions, &action_button_dto(form, &1))
      }
    }
  end

  defp hidden_field_dto(form, workflow_context, field) do
    form_field = form[field]

    %{
      key: Atom.to_string(field),
      attrs:
        raw_attrs(%{
          "id" => hidden_field_id(field),
          "type" => "hidden",
          "name" => form_field.name,
          "value" => context_field_value(workflow_context, field)
        })
    }
  end

  defp hidden_field_id(field) do
    suffix = field |> Atom.to_string() |> String.replace("_", "-")
    "dashboard-historical-workflow-group-#{suffix}"
  end

  defp context_field_value(workflow_context, field) do
    value =
      if field in @required_context_fields,
        do: Map.fetch!(workflow_context, field),
        else: Map.get(workflow_context, field)

    if field in @direct_context_values, do: value, else: value || ""
  end

  defp eligible_items_dto(workflow_context, actions) do
    request_group_id = Map.fetch!(workflow_context, :request_group_id)
    request_item_count = Map.fetch!(workflow_context, :request_item_count)

    %{
      id: "dashboard-historical-workflow-group-eligible-items",
      class: "space-y-1 rounded border border-base-300/60 bg-base-100/70 p-2",
      attrs:
        raw_attrs(%{
          "data-historical-workflow-group-eligible-request-group" => request_group_id || "",
          "data-historical-workflow-group-eligible-size" => request_item_count || ""
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        title: %{class: "hud-label", text: "Eligible Items"},
        count: %{class: "font-mono text-base-content/60", text: dom_text(request_item_count)}
      },
      list_class: "space-y-1",
      actions: Enum.map(actions, &eligible_action_dto/1)
    }
  end

  defp eligible_action_dto(action) do
    state_summary = Map.get(action, :state_summary)
    available_when = Map.get(action, :available_when)

    %{
      key: dom_text(Map.get(action, :stage)),
      attrs:
        raw_attrs(%{
          "class" => "rounded border border-base-300/50 bg-base-200/40 px-2 py-1",
          "data-historical-workflow-group-eligible-action" => Map.get(action, :stage),
          "data-historical-workflow-group-eligible-count" => Map.get(action, :eligible_count),
          "data-historical-workflow-group-eligible-state" =>
            DataLinkInspectorPanelPresentation.bool_attr(Map.get(action, :eligible?)),
          "data-historical-workflow-group-eligible-reason" => Map.get(action, :reason),
          "data-workflow-action-correction-tasks" => Map.get(action, :correction_tasks)
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "font-mono text-base-content", text: dom_text(Map.get(action, :label))},
        count: %{
          class: "badge badge-xs badge-outline font-mono",
          text: dom_text(Map.get(action, :eligible_count))
        }
      },
      preview: %{class: "mt-1 text-base-content/75", text: dom_text(Map.get(action, :preview))},
      state_summary: optional_text_dto(state_summary, "mt-1 font-mono text-base-content/60"),
      available_when: optional_text_dto(available_when, "mt-1 text-base-content/60")
    }
  end

  defp start_orchestration_dto(_workflow_context, %{present: false}), do: nil

  defp start_orchestration_dto(workflow_context, group_start) do
    review_request = Map.get(workflow_context, :comparison_review_request_event_id)

    %{
      id: "dashboard-historical-workflow-group-start-orchestration",
      class: "space-y-2 rounded border border-info/40 bg-info/10 p-2",
      attrs:
        @review_fields
        |> Enum.reduce(
          %{
            "data-historical-workflow-group-start-request-group" =>
              Map.get(workflow_context, :request_group_id),
            "data-historical-workflow-group-start-next-action" => group_start.next_action,
            "data-historical-workflow-group-start-eligible" => group_start.eligible_count,
            "data-historical-workflow-group-start-eligible-state" => group_start.eligible,
            "data-historical-workflow-group-start-reason" => group_start.reason,
            "data-historical-workflow-group-start-preview" => group_start.preview,
            "data-historical-workflow-group-start-state" => group_start.state,
            "data-historical-workflow-group-start-available-when" => group_start.available_when,
            "data-historical-workflow-group-start-expected-jobs" => group_start.expected_jobs
          },
          fn {suffix, field}, attrs ->
            suffix = suffix |> Atom.to_string() |> String.replace("_", "-")

            Map.put(
              attrs,
              "data-historical-workflow-group-start-review-#{suffix}",
              Map.get(workflow_context, field)
            )
          end
        )
        |> raw_attrs(),
      header: %{
        class: "flex items-center justify-between gap-2",
        title: %{class: "hud-label", text: "Start Orchestration"},
        count: %{
          class: "badge badge-xs badge-info font-mono",
          text: "#{group_start.expected_jobs} jobs"
        }
      },
      guidance: %{class: "text-base-content/75", text: group_start.guidance},
      details: %{
        class: "grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
        eligible: detail_row_dto("Eligible", group_start.eligible_count, false),
        review:
          if(DataLinkInspectorPanelPresentation.present_text?(review_request),
            do: detail_row_dto("Review", review_request, true)
          ),
        state:
          if(DataLinkInspectorPanelPresentation.present_text?(group_start.state),
            do: detail_row_dto("State", group_start.state, true)
          )
      },
      available_when: optional_text_dto(group_start.available_when, "text-base-content/60")
    }
  end

  defp detail_row_dto(label, value, break_all?) do
    %{
      label: %{class: "text-base-content/60", text: label},
      value: %{
        class: class_names(["font-mono", break_all? && "break-all"]),
        text: dom_text(value)
      }
    }
  end

  defp reason_field_dto(form, workflow_context) do
    form_field = form[:reason]
    errors = if Phoenix.Component.used_input?(form_field), do: form_field.errors, else: []

    %{
      wrapper_class: "fieldset",
      label: %{class: "hud-label block mb-1.5", text: "Reason"},
      control: %{
        class: class_names(["w-full input", errors != [] && "input-error"]),
        attrs:
          raw_attrs(%{
            "id" => form_field.id,
            "name" => form_field.name,
            "type" => "text",
            "value" => form_field.value,
            "placeholder" =>
              Map.fetch!(workflow_context, :reason) || "dashboard workflow group event",
            "required" => false
          })
      },
      errors:
        Enum.map(errors, fn {message, _opts} ->
          %{class: "mt-1.5 text-sm text-error", text: dom_text(message)}
        end)
    }
  end

  defp confirmation_dto(form) do
    %{
      id: "dashboard-historical-workflow-group-confirm-row",
      class: "flex items-start gap-2 rounded border border-primary/30 bg-base-100/70 p-2 text-xs",
      field: %{
        class: "checkbox checkbox-xs mt-0.5",
        attrs:
          raw_attrs(%{
            "id" => "dashboard-historical-workflow-group-confirm",
            "type" => "checkbox",
            "name" => form[:confirmed].name,
            "value" => "confirmed",
            "required" => true
          })
      },
      label: %{
        class: "text-base-content/80",
        text: "Confirm workflow transition for eligible items in this request group"
      }
    }
  end

  defp action_button_dto(form, action) do
    disabled? = Map.get(action, :disabled?)

    %{
      key: dom_text(Map.get(action, :stage)),
      attrs:
        raw_attrs(%{
          "id" => "dashboard-historical-workflow-group-#{Map.get(action, :stage)}",
          "type" => "submit",
          "name" => form[:stage].name,
          "value" => Map.get(action, :stage),
          "disabled" => disabled?,
          "class" =>
            class_names([
              "btn btn-xs justify-between gap-2",
              disabled? && "btn-disabled",
              !disabled? && Map.get(action, :class)
            ]),
          "data-historical-workflow-group-action" => Map.get(action, :stage),
          "data-historical-workflow-group-action-eligible" => Map.get(action, :eligible_count),
          "data-workflow-action-id" => Map.get(action, :id),
          "data-workflow-action-eligible" =>
            DataLinkInspectorPanelPresentation.bool_attr(Map.get(action, :eligible?)),
          "data-workflow-action-reason" => Map.get(action, :reason),
          "data-workflow-action-preview" => Map.get(action, :preview),
          "data-workflow-action-correction-tasks" => Map.get(action, :correction_tasks)
        }),
      label: %{
        class: "flex min-w-0 items-center gap-1",
        icon: %{name: dom_text(Map.get(action, :icon)), class: "h-3.5 w-3.5"},
        text: dom_text(Map.get(action, :label))
      },
      count: %{class: "font-mono", text: dom_text(Map.get(action, :eligible_count))}
    }
  end

  defp optional_text_dto(value, class) do
    if DataLinkInspectorPanelPresentation.present_text?(value) do
      %{class: class, text: value}
    end
  end

  defp class_names(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map(&dom_text/1)
    |> Enum.join(" ")
  end

  defp raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, dom_text(value))
    end)
  end

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value) when is_number(value), do: to_string(value)
  defp dom_text(value), do: to_string(value)
end
