defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobRecoveryPresentation

  @source_fields [
    {:realm, "Realm"},
    {:data_source_id, "Data Source"},
    {:source_binding_id, "Source Binding"},
    {:observable_id, "Observable"},
    {:point_id, "Point"},
    {:source_from, "Source From"},
    {:source_to, "Source To"},
    {:reason, "Reason"}
  ]

  attr :form, Phoenix.HTML.Form, required: true
  attr :workflow_context, :map, required: true
  attr :workflow_controls, :map, required: true

  def corrected_request_form(assigns) do
    presentation = presentation(assigns.form, assigns.workflow_context, assigns.workflow_controls)

    if presentation do
      assigns = assign(assigns, :presentation, presentation)

      ~H"""
      <.vue
        id="historical-workflow-correction-form-component"
        v-component="HistoricalWorkflowCorrectionForm"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
      """
    else
      ~H""
    end
  end

  def presentation(form, workflow_context, workflow_controls) do
    job_recovery =
      HistoricalWorkflowJobRecoveryPresentation.build(
        workflow_context,
        workflow_controls
      )

    if job_recovery.correction_form.present do
      corrected_request_form_dto(form, workflow_context, job_recovery)
    end
  end

  defp corrected_request_form_dto(form, workflow_context, job_recovery) do
    correction_form = job_recovery.correction_form
    replacement_run_id = form_value(form, :run_id)

    %{
      root: %{
        id: "dashboard-historical-workflow-correction-form",
        class: "space-y-3 rounded border border-warning/40 bg-warning/10 p-2",
        attrs:
          raw_attrs(%{
            "phx-submit" => "record_corrected_historical_workflow_request",
            "data-workflow-action-id" => correction_form.id,
            "data-workflow-action-eligible" => correction_form.eligible,
            "data-workflow-action-reason" => correction_form.reason,
            "data-workflow-action-preview" => correction_form.preview,
            "data-historical-workflow-correction-request-mode" =>
              Map.get(workflow_context, :request_mode) || "",
            "data-historical-workflow-correction-request-group" =>
              Map.get(workflow_context, :request_group_id) || "",
            "data-historical-workflow-correction-request-item" =>
              Map.get(workflow_context, :request_item) || "",
            "data-historical-workflow-correction-request-item-count" =>
              Integer.to_string(Map.get(workflow_context, :request_item_count, 0) || 0)
          })
      },
      hidden_fields: hidden_fields_dto(form, workflow_context, replacement_run_id),
      header: %{
        class: "flex items-center justify-between gap-2",
        heading: %{class: "hud-label", text: "Correct Request"},
        badge: %{class: "badge badge-xs badge-warning", text: "New run"}
      },
      group_context: group_context_dto(workflow_context, replacement_run_id),
      new_run: compact_text_field_dto(form, :run_id, "New Run"),
      source_fields:
        Enum.map(@source_fields, fn {key, label} ->
          compact_text_field_dto(form, key, label)
        end),
      source_fields_class: "grid grid-cols-1 gap-2",
      confirmation: %{
        row: %{
          id: "dashboard-historical-workflow-correction-confirm-row",
          class:
            "flex items-start gap-2 rounded border border-warning/40 bg-base-100/70 p-2 text-xs"
        },
        input: %{
          id: "dashboard-historical-workflow-correction-confirm",
          type: "checkbox",
          name: form_name(form, :confirmed),
          value: "confirmed",
          required: true,
          class: "checkbox checkbox-xs mt-0.5"
        },
        label: %{
          class: "text-base-content/80",
          text: "Confirm corrected workflow request"
        }
      },
      submit: %{
        id: "dashboard-historical-workflow-correction-submit",
        type: "submit",
        class: "btn btn-xs btn-warning btn-outline w-full justify-start",
        icon: %{name: "hero-document-plus", class: "h-3.5 w-3.5"},
        text: "Request corrected workflow"
      }
    }
  end

  defp hidden_fields_dto(form, workflow_context, replacement_run_id) do
    [
      hidden_field_dto(
        form,
        :workflow,
        "dashboard-historical-workflow-correction-workflow",
        nullable_attribute_text(workflow_context.workflow)
      ),
      hidden_field_dto(
        form,
        :original_run_id,
        "dashboard-historical-workflow-correction-original-run-id",
        nullable_attribute_text(workflow_context.run_id)
      ),
      hidden_field_dto(
        form,
        :original_event_id,
        "dashboard-historical-workflow-correction-original-event-id",
        nullable_attribute_text(workflow_context.event_id)
      ),
      hidden_field_dto(
        form,
        :original_job_id,
        "dashboard-historical-workflow-correction-original-job-id",
        nullable_attribute_text(workflow_context.job_id)
      ),
      hidden_field_dto(
        form,
        :dashboard_id,
        "dashboard-historical-workflow-correction-dashboard-id",
        attribute_text(workflow_context.dashboard_id || "")
      ),
      hidden_field_dto(
        form,
        :dashboard_version,
        "dashboard-historical-workflow-correction-dashboard-version",
        attribute_text(workflow_context.dashboard_version || "")
      ),
      hidden_field_dto(
        form,
        :dashboard_time_mode,
        "dashboard-historical-workflow-correction-dashboard-time-mode",
        attribute_text(workflow_context.dashboard_time_mode || "")
      ),
      hidden_field_dto(
        form,
        :dashboard_replay_run_id,
        "dashboard-historical-workflow-correction-dashboard-replay-run-id",
        attribute_text(workflow_context.dashboard_replay_run_id || "")
      ),
      hidden_field_dto(
        form,
        :dashboard_data_view,
        "dashboard-historical-workflow-correction-dashboard-data-view",
        attribute_text(workflow_context.dashboard_data_view || "")
      ),
      hidden_field_dto(
        form,
        :dashboard_limit_mode,
        "dashboard-historical-workflow-correction-dashboard-limit-mode",
        attribute_text(workflow_context.dashboard_limit_mode || "")
      ),
      hidden_field_dto(
        form,
        :request_mode,
        "dashboard-historical-workflow-correction-request-mode",
        context_attribute_text(workflow_context, :request_mode)
      ),
      hidden_field_dto(
        form,
        :request_group_id,
        "dashboard-historical-workflow-correction-request-group-id",
        context_attribute_text(workflow_context, :request_group_id)
      ),
      hidden_field_dto(
        form,
        :request_item_index,
        "dashboard-historical-workflow-correction-request-item-index",
        request_item_index(workflow_context)
      ),
      hidden_field_dto(
        form,
        :request_item_count,
        "dashboard-historical-workflow-correction-request-item-count",
        request_item_count(workflow_context)
      ),
      hidden_field_dto(
        form,
        :request_item_run_id,
        "dashboard-historical-workflow-correction-request-item-run-id",
        attribute_text(replacement_run_id || "")
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_request_event_id,
        "dashboard-historical-workflow-correction-comparison-review-request-event-id"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_request_kind,
        "dashboard-historical-workflow-correction-comparison-review-request-kind"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_open_count,
        "dashboard-historical-workflow-correction-comparison-review-open-count"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_open_placement_ids,
        "dashboard-historical-workflow-correction-comparison-review-open-placement-ids"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_workflow_kind,
        "dashboard-historical-workflow-correction-comparison-review-workflow-kind"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_workflow_action,
        "dashboard-historical-workflow-correction-comparison-review-workflow-action"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_workflow_selection_kind,
        "dashboard-historical-workflow-correction-comparison-review-workflow-selection-kind"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_workflow_selection_count,
        "dashboard-historical-workflow-correction-comparison-review-workflow-selection-count"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_primary_data_view,
        "dashboard-historical-workflow-correction-comparison-review-primary-data-view"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_compare_data_view,
        "dashboard-historical-workflow-correction-comparison-review-compare-data-view"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_scope_kind,
        "dashboard-historical-workflow-correction-comparison-review-scope-kind"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_scope_ids,
        "dashboard-historical-workflow-correction-comparison-review-scope-ids"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_contact_ids,
        "dashboard-historical-workflow-correction-comparison-review-contact-ids"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_resource_ids,
        "dashboard-historical-workflow-correction-comparison-review-resource-ids"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_transport_ids,
        "dashboard-historical-workflow-correction-comparison-review-transport-ids"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_source_endpoint_ids,
        "dashboard-historical-workflow-correction-comparison-review-source-endpoint-ids"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_ground_station_ids,
        "dashboard-historical-workflow-correction-comparison-review-ground-station-ids"
      ),
      comparison_hidden_field_dto(
        form,
        workflow_context,
        :comparison_review_scope_link_ids,
        "dashboard-historical-workflow-correction-comparison-review-scope-link-ids"
      )
    ]
  end

  defp comparison_hidden_field_dto(form, workflow_context, key, id) do
    hidden_field_dto(form, key, id, context_attribute_text(workflow_context, key))
  end

  defp hidden_field_dto(form, key, id, value) do
    %{id: id, type: "hidden", name: form_name(form, key), value: value}
  end

  defp group_context_dto(workflow_context, replacement_run_id) do
    request_group_id = Map.get(workflow_context, :request_group_id)

    %{
      visible: DataLinkInspectorPanelPresentation.present_text?(request_group_id),
      id: "dashboard-historical-workflow-correction-group-context",
      class:
        "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 rounded border border-warning/30 bg-base-100/70 p-2 text-xs",
      attrs: %{
        "data-historical-workflow-correction-group-context-request-mode" =>
          context_dom_text(workflow_context, :request_mode),
        "data-historical-workflow-correction-group-context-request-group" =>
          dom_text(request_group_id || ""),
        "data-historical-workflow-correction-group-context-request-item" =>
          context_dom_text(workflow_context, :request_item),
        "data-historical-workflow-correction-group-context-replacement-run" =>
          dom_text(replacement_run_id || "")
      },
      rows: [
        group_context_row("group", "Group", request_group_id, "font-mono break-all"),
        group_context_row(
          "item",
          "Item",
          Map.get(workflow_context, :request_item),
          "font-mono"
        ),
        group_context_row(
          "replacement",
          "Replacement",
          replacement_run_id,
          "font-mono break-all"
        )
      ]
    }
  end

  defp group_context_row(key, label, value, value_class) do
    %{
      key: key,
      label: %{class: "text-base-content/60", text: label},
      value: %{class: value_class, text: dom_text(value)}
    }
  end

  defp compact_text_field_dto(form, key, label) do
    field = form[key]
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    %{
      id: field.id,
      name: field.name,
      type: "text",
      value: nullable_attribute_text(field.value),
      required: false,
      wrapper_class: "fieldset",
      label: %{class: "hud-label block mb-1.5", text: label},
      input_class: class_names(["w-full input", errors != [] && "input-error"]),
      errors: Enum.map(errors, fn {message, _options} -> dom_text(message) end),
      error_class: "mt-1.5 text-sm text-error"
    }
  end

  defp form_name(form, key) do
    field = form[key]
    field.name
  end

  defp form_value(form, key) do
    field = form[key]
    field.value
  end

  defp context_dom_text(workflow_context, key) do
    dom_text(Map.get(workflow_context, key) || "")
  end

  defp context_attribute_text(workflow_context, key) do
    attribute_text(Map.get(workflow_context, key) || "")
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

  defp class_names(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map(&dom_text/1)
    |> Enum.join(" ")
  end

  defp nullable_attribute_text(nil), do: nil
  defp nullable_attribute_text(false), do: nil
  defp nullable_attribute_text(value), do: attribute_text(value)

  defp attribute_text(true), do: ""
  defp attribute_text(value), do: dom_text(value)

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value) when is_number(value), do: to_string(value)
  defp dom_text(value), do: to_string(value)
end
