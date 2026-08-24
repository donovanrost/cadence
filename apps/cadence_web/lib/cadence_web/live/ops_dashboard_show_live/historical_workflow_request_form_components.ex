defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowRequestFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  @hidden_fields [
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

  attr(:form, Phoenix.HTML.Form, required: true)

  def request_form(assigns) do
    assigns = assign(assigns, :presentation, request_form_dto(assigns.form))

    ~H"""
    <.vue
      id="historical-workflow-request-form-component"
      v-component="HistoricalWorkflowRequestForm"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc "Builds the JSON-safe presentation contract for the historical workflow request form."
  def request_form_dto(form) do
    %{
      root: %{
        id: "dashboard-historical-workflow-request-form",
        class: "space-y-3",
        attrs: %{"phx-submit" => "record_historical_workflow_request"}
      },
      hidden_fields: Enum.map(@hidden_fields, &hidden_field_dto(form, &1)),
      preview: request_preview_dto(form),
      request_context: %{
        class: "space-y-2 rounded border border-base-300 bg-base-100/70 p-2 text-xs",
        title: %{class: "hud-label", text: "Request Context"},
        fields: [
          field_dto(form, :workflow, "select", "Workflow",
            options: [{"Backfill", "backfill"}, {"Import", "import"}]
          ),
          field_dto(form, :run_id, "text", "Run")
        ],
        group: %{
          class: "grid grid-cols-1 gap-2",
          fields: [
            field_dto(form, :realm, "text", "Realm"),
            field_dto(form, :data_source_id, "text", "Data Source"),
            field_dto(form, :source_binding_id, "text", "Source Binding")
          ]
        }
      },
      source_window: %{
        class: "space-y-2 rounded border border-base-300 bg-base-100/70 p-2 text-xs",
        title: %{class: "hud-label", text: "Source Window"},
        fields: [
          field_dto(form, :observable_id, "text", "Observable"),
          field_dto(form, :point_id, "text", "Point"),
          field_dto(form, :point_ids, "text", "Points",
            placeholder: "Comma, space, or newline separated point IDs"
          ),
          field_dto(form, :source_from, "text", "Source From"),
          field_dto(form, :source_to, "text", "Source To"),
          field_dto(form, :reason, "text", "Reason")
        ]
      },
      confirmation: %{
        id: "dashboard-historical-workflow-request-confirm-row",
        class:
          "flex items-start gap-2 rounded border border-warning/40 bg-warning/10 p-2 text-xs",
        field: %{
          class: "checkbox checkbox-xs mt-0.5",
          attrs:
            raw_attrs(%{
              "id" => "dashboard-historical-workflow-request-confirm",
              "type" => "checkbox",
              "name" => form[:confirmed].name,
              "value" => "confirmed",
              "required" => true
            })
        },
        label: %{
          class: "text-base-content/80",
          text: "Confirm historical data workflow request"
        }
      },
      submit: %{
        id: "dashboard-historical-workflow-request-submit",
        type: "submit",
        class: "btn btn-xs btn-primary w-full justify-start",
        icon: %{name: "hero-document-plus", class: "h-3.5 w-3.5"},
        text: "Record request"
      }
    }
  end

  defp hidden_field_dto(form, field) do
    form_field = form[field]

    %{
      key: Atom.to_string(field),
      attrs:
        raw_attrs(%{
          "type" => "hidden",
          "name" => form_field.name,
          "value" => form_field.value
        })
    }
  end

  defp request_preview_dto(form) do
    %{
      id: "dashboard-historical-workflow-request-preview",
      class: "space-y-2 rounded border border-info/30 bg-info/10 p-2 text-xs",
      title: %{class: "hud-label", text: "Request Preview"},
      list: %{
        class: "grid grid-cols-[minmax(5.5rem,auto)_1fr] gap-x-3 gap-y-1",
        rows:
          Enum.map(request_preview_rows(form), fn row ->
            %{
              key: row.field,
              class: "contents",
              attrs: %{"data-preview-field" => row.field},
              label: %{class: "text-base-content/60", text: row.label},
              value: %{
                class: "min-w-0 truncate text-base-content",
                attrs: raw_attrs(%{"title" => row.value}),
                text: row.value
              }
            }
          end)
      }
    }
  end

  defp field_dto(form, field, type, label, options \\ []) do
    form_field = form[field]
    errors = if Phoenix.Component.used_input?(form_field), do: form_field.errors, else: []

    %{
      key: Atom.to_string(field),
      type: type,
      wrapper_class: "fieldset",
      label: %{class: "hud-label block mb-1.5", text: label},
      control: control_dto(form_field, type, errors, options),
      errors:
        Enum.map(errors, fn {message, _opts} ->
          %{class: "mt-1.5 text-sm text-error", text: dom_text(message)}
        end)
    }
  end

  defp control_dto(form_field, "select", errors, options) do
    %{
      class: class_names(["w-full select", errors != [] && "select-error"]),
      attrs:
        raw_attrs(%{
          "id" => form_field.id,
          "name" => form_field.name,
          "required" => false,
          "multiple" => false
        }),
      options:
        options
        |> Keyword.get(:options, [])
        |> Enum.map(fn {label, value} ->
          %{
            key: dom_text(value),
            text: dom_text(label),
            attrs:
              raw_attrs(%{
                "value" => value,
                "selected" => option_selected?(form_field.value, value),
                "disabled" => false,
                "title" => nil
              })
          }
        end)
    }
  end

  defp control_dto(form_field, type, errors, options) do
    %{
      class: class_names(["w-full input", errors != [] && "input-error"]),
      attrs:
        raw_attrs(%{
          "id" => form_field.id,
          "name" => form_field.name,
          "type" => type,
          "value" => form_field.value,
          "placeholder" => Keyword.get(options, :placeholder),
          "required" => false
        }),
      options: []
    }
  end

  defp option_selected?(values, option_value) when is_list(values) do
    Enum.any?(values, &(to_string(&1) == to_string(option_value)))
  end

  defp option_selected?(value, option_value),
    do: to_string(value) == to_string(option_value)

  defp request_preview_rows(form) do
    workflow = form_value(form, :workflow)

    [
      %{field: "workflow", label: "Workflow", value: workflow_label(workflow)},
      %{field: "effect", label: "Effect", value: workflow_effect(workflow)},
      %{field: "points", label: "Points", value: points_preview(form)},
      %{field: "source", label: "Source", value: source_preview(form)},
      %{field: "window", label: "Window", value: window_preview(form)},
      %{field: "dashboard", label: "Dashboard", value: dashboard_preview(form)},
      %{field: "runtime", label: "Runtime", value: runtime_preview(form)},
      %{field: "comparison", label: "Comparison", value: comparison_preview(form)},
      %{
        field: "comparison_scope",
        label: "Comparison Scope",
        value: comparison_scope_preview(form)
      }
    ]
  end

  defp workflow_label("import"), do: "Import"
  defp workflow_label("backfill"), do: "Backfill"
  defp workflow_label(value), do: text_or_dash(value)

  defp workflow_effect("import"),
    do: "Create import request event; samples are written after start."

  defp workflow_effect(_workflow),
    do: "Create backfill request event; samples are written after start."

  defp points_preview(form) do
    form
    |> form_value(:point_ids)
    |> split_point_ids()
    |> case do
      [] ->
        form
        |> form_value(:point_id)
        |> text_or_dash()

      [point_id] ->
        point_id

      point_ids ->
        "#{length(point_ids)} points: #{Enum.join(point_ids, ", ")}"
    end
  end

  defp source_preview(form) do
    [
      form_value(form, :realm),
      form_value(form, :data_source_id),
      form_value(form, :source_binding_id)
    ]
    |> text_join()
  end

  defp window_preview(form) do
    [form_value(form, :source_from), form_value(form, :source_to)]
    |> text_join(" -> ")
  end

  defp dashboard_preview(form) do
    case {form_value(form, :dashboard_id), form_value(form, :dashboard_version)} do
      {nil, nil} -> "-"
      {dashboard_id, nil} -> dashboard_id
      {nil, version} -> "v#{version}"
      {dashboard_id, version} -> "#{dashboard_id} v#{version}"
    end
  end

  defp runtime_preview(form) do
    [
      form_value(form, :dashboard_time_mode),
      form_value(form, :dashboard_replay_run_id),
      form_value(form, :dashboard_data_view),
      form_value(form, :dashboard_limit_mode)
    ]
    |> text_join()
  end

  defp comparison_preview(form) do
    [
      form_value(form, :comparison_review_workflow_kind),
      form_value(form, :comparison_review_workflow_action),
      form_value(form, :comparison_review_workflow_selection_count),
      form_value(form, :comparison_review_primary_data_view),
      form_value(form, :comparison_review_compare_data_view)
    ]
    |> text_join()
  end

  defp comparison_scope_preview(form) do
    [
      form_value(form, :comparison_review_scope_kind),
      form_value(form, :comparison_review_scope_ids),
      form_value(form, :comparison_review_contact_ids),
      form_value(form, :comparison_review_transport_ids),
      form_value(form, :comparison_review_source_endpoint_ids),
      form_value(form, :comparison_review_ground_station_ids),
      form_value(form, :comparison_review_scope_link_ids)
    ]
    |> text_join()
  end

  defp split_point_ids(nil), do: []

  defp split_point_ids(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "\r", "\t", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp split_point_ids(_value), do: []

  defp text_join(values, separator \\ " / ") do
    values
    |> Enum.map(&text_param/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "-"
      values -> Enum.join(values, separator)
    end
  end

  defp text_or_dash(value), do: text_param(value) || "-"

  defp form_value(form, field) do
    form
    |> then(& &1[field])
    |> Map.get(:value)
    |> text_param()
  end

  defp text_param(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text_param(value) when is_atom(value), do: Atom.to_string(value)
  defp text_param(value) when is_integer(value), do: Integer.to_string(value)
  defp text_param(_value), do: nil

  defp class_names(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map_join(" ", &dom_text/1)
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
