defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation

  attr :form, Phoenix.HTML.Form, required: true
  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true

  def stage_transition_form(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        presentation(
          assigns.form,
          assigns.workflow_context,
          assigns.workflow_controls
        )
      )

    ~H"""
    <.vue
      id="historical-workflow-stage-form-component"
      v-component="HistoricalWorkflowStageForm"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(form, workflow_context, workflow_controls) do
    stage_transition_form_dto(form, workflow_context, workflow_controls)
  end

  defp stage_transition_form_dto(form, workflow_context, workflow_controls) do
    %{
      root: %{
        attrs:
          raw_attrs(%{
            "id" => "dashboard-historical-workflow-form",
            "phx-submit" => "record_historical_workflow_stage",
            "class" => "space-y-3"
          })
      },
      hidden_fields: hidden_fields_dto(form, workflow_context),
      reason:
        compact_input_dto(
          form[:reason],
          "Reason",
          workflow_context.reason || "dashboard workflow event"
        ),
      source_fields: %{
        attrs: %{"class" => "grid grid-cols-1 gap-2"},
        fields: [
          compact_input_dto(form[:source_from], "Source From"),
          compact_input_dto(form[:source_to], "Source To")
        ]
      },
      confirmation: confirmation_dto(form),
      actions: actions_dto(form, workflow_controls.stage_actions)
    }
  end

  defp hidden_fields_dto(form, workflow_context) do
    [
      hidden_field_dto(
        form,
        :event_id,
        "dashboard-historical-workflow-event-id",
        workflow_context.event_id || ""
      ),
      hidden_field_dto(
        form,
        :correction_source_event_id,
        "dashboard-historical-workflow-correction-source-event-id",
        workflow_context.correction_source_event_id || ""
      ),
      hidden_field_dto(
        form,
        :workflow,
        "dashboard-historical-workflow-value",
        workflow_context.workflow
      ),
      hidden_field_dto(
        form,
        :run_id,
        "dashboard-historical-workflow-run-id",
        workflow_context.run_id
      ),
      hidden_field_dto(
        form,
        :realm,
        "dashboard-historical-workflow-realm",
        workflow_context.realm
      ),
      hidden_field_dto(
        form,
        :data_source_id,
        "dashboard-historical-workflow-data-source-id",
        workflow_context.data_source_id
      ),
      hidden_field_dto(
        form,
        :source_binding_id,
        "dashboard-historical-workflow-source-binding-id",
        workflow_context.source_binding_id
      ),
      hidden_field_dto(
        form,
        :observable_id,
        "dashboard-historical-workflow-observable-id",
        workflow_context.observable_id || ""
      ),
      hidden_field_dto(
        form,
        :point_id,
        "dashboard-historical-workflow-point-id",
        workflow_context.point_id || ""
      ),
      hidden_field_dto(
        form,
        :dashboard_id,
        "dashboard-historical-workflow-dashboard-id",
        workflow_context.dashboard_id || ""
      ),
      hidden_field_dto(
        form,
        :dashboard_version,
        "dashboard-historical-workflow-dashboard-version",
        workflow_context.dashboard_version || ""
      ),
      hidden_field_dto(
        form,
        :dashboard_time_mode,
        "dashboard-historical-workflow-dashboard-time-mode",
        workflow_context.dashboard_time_mode || ""
      ),
      hidden_field_dto(
        form,
        :dashboard_replay_run_id,
        "dashboard-historical-workflow-dashboard-replay-run-id",
        workflow_context.dashboard_replay_run_id || ""
      ),
      hidden_field_dto(
        form,
        :dashboard_data_view,
        "dashboard-historical-workflow-dashboard-data-view",
        workflow_context.dashboard_data_view || ""
      ),
      hidden_field_dto(
        form,
        :dashboard_limit_mode,
        "dashboard-historical-workflow-dashboard-limit-mode",
        workflow_context.dashboard_limit_mode || ""
      ),
      hidden_field_dto(
        form,
        :request_group_id,
        "dashboard-historical-workflow-request-group-id",
        workflow_context.request_group_id || ""
      ),
      hidden_field_dto(
        form,
        :request_mode,
        "dashboard-historical-workflow-request-mode",
        workflow_context.request_mode || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_request_event_id,
        "dashboard-historical-workflow-comparison-review-request-event-id",
        Map.get(workflow_context, :comparison_review_request_event_id) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_request_kind,
        "dashboard-historical-workflow-comparison-review-request-kind",
        Map.get(workflow_context, :comparison_review_request_kind) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_open_count,
        "dashboard-historical-workflow-comparison-review-open-count",
        Map.get(workflow_context, :comparison_review_open_count) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_open_placement_ids,
        "dashboard-historical-workflow-comparison-review-open-placement-ids",
        Map.get(workflow_context, :comparison_review_open_placement_ids) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_workflow_kind,
        "dashboard-historical-workflow-comparison-review-workflow-kind",
        Map.get(workflow_context, :comparison_review_workflow_kind) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_workflow_action,
        "dashboard-historical-workflow-comparison-review-workflow-action",
        Map.get(workflow_context, :comparison_review_workflow_action) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_workflow_selection_kind,
        "dashboard-historical-workflow-comparison-review-workflow-selection-kind",
        Map.get(workflow_context, :comparison_review_workflow_selection_kind) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_workflow_selection_count,
        "dashboard-historical-workflow-comparison-review-workflow-selection-count",
        Map.get(workflow_context, :comparison_review_workflow_selection_count) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_primary_data_view,
        "dashboard-historical-workflow-comparison-review-primary-data-view",
        Map.get(workflow_context, :comparison_review_primary_data_view) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_compare_data_view,
        "dashboard-historical-workflow-comparison-review-compare-data-view",
        Map.get(workflow_context, :comparison_review_compare_data_view) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_scope_kind,
        "dashboard-historical-workflow-comparison-review-scope-kind",
        Map.get(workflow_context, :comparison_review_scope_kind) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_scope_ids,
        "dashboard-historical-workflow-comparison-review-scope-ids",
        Map.get(workflow_context, :comparison_review_scope_ids) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_contact_ids,
        "dashboard-historical-workflow-comparison-review-contact-ids",
        Map.get(workflow_context, :comparison_review_contact_ids) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_resource_ids,
        "dashboard-historical-workflow-comparison-review-resource-ids",
        Map.get(workflow_context, :comparison_review_resource_ids) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_transport_ids,
        "dashboard-historical-workflow-comparison-review-transport-ids",
        Map.get(workflow_context, :comparison_review_transport_ids) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_source_endpoint_ids,
        "dashboard-historical-workflow-comparison-review-source-endpoint-ids",
        Map.get(workflow_context, :comparison_review_source_endpoint_ids) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_ground_station_ids,
        "dashboard-historical-workflow-comparison-review-ground-station-ids",
        Map.get(workflow_context, :comparison_review_ground_station_ids) || ""
      ),
      hidden_field_dto(
        form,
        :comparison_review_scope_link_ids,
        "dashboard-historical-workflow-comparison-review-scope-link-ids",
        Map.get(workflow_context, :comparison_review_scope_link_ids) || ""
      )
    ]
  end

  defp hidden_field_dto(form, field_name, id, value) do
    field = form[field_name]

    %{
      attrs:
        raw_attrs(%{
          "id" => id,
          "type" => "hidden",
          "name" => field.name,
          "value" => value
        })
    }
  end

  defp compact_input_dto(field, label, placeholder \\ nil) do
    errors =
      if Phoenix.Component.used_input?(field) do
        Enum.map(field.errors, fn {message, _options} -> dom_text(message) end)
      else
        []
      end

    %{
      wrapper_attrs: %{"class" => "fieldset"},
      label: %{"attrs" => %{"class" => "hud-label block mb-1.5"}, "text" => label},
      input_attrs:
        raw_attrs(%{
          "id" => field.id,
          "name" => field.name,
          "type" => "text",
          "value" => field.value,
          "placeholder" => placeholder,
          "class" => class_names(["w-full input", errors != [] && "input-error"])
        }),
      errors: errors
    }
  end

  defp confirmation_dto(form) do
    %{
      attrs: %{
        "id" => "dashboard-historical-workflow-confirm-row",
        "class" =>
          "flex items-start gap-2 rounded border border-base-300/70 bg-base-100/60 p-2 text-xs"
      },
      input_attrs:
        raw_attrs(%{
          "id" => "dashboard-historical-workflow-confirm",
          "type" => "checkbox",
          "name" => form[:confirmed].name,
          "value" => "confirmed",
          "required" => true,
          "class" => "checkbox checkbox-xs mt-0.5"
        }),
      label: %{
        "attrs" => %{"class" => "text-base-content/80"},
        "text" => "Confirm workflow transition"
      }
    }
  end

  defp actions_dto(form, stage_actions) do
    %{
      attrs: %{"class" => "grid grid-cols-2 gap-2"},
      items: Enum.map(stage_actions, &action_dto(form[:stage], &1))
    }
  end

  defp action_dto(stage_field, action) do
    %{
      attrs:
        raw_attrs(%{
          "id" => "dashboard-historical-workflow-#{action.stage}",
          "type" => "submit",
          "name" => stage_field.name,
          "value" => action.stage,
          "disabled" => action.disabled?,
          "class" =>
            class_names([
              "btn btn-xs justify-start",
              action.disabled? && "btn-disabled",
              !action.disabled? && action.class
            ]),
          "data-historical-workflow-action" => action.stage,
          "data-workflow-action-id" => action.id,
          "data-workflow-action-eligible" =>
            DataLinkInspectorPanelPresentation.bool_attr(action.eligible?),
          "data-workflow-action-reason" => action.reason,
          "data-workflow-action-preview" => action.preview
        }),
      icon: %{
        "attrs" => %{"class" => class_names([action.icon, "h-3.5 w-3.5"])}
      },
      label: action.label
    }
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
