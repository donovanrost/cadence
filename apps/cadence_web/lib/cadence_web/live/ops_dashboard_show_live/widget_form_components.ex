defmodule CadenceWeb.OpsDashboardShowLive.WidgetFormComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetFormPresentation

  @checkbox_form_fields [
    :show_unit,
    :show_min_max_band,
    :show_points,
    :span_gaps,
    :shared_tooltip
  ]

  attr(:panel, :any, required: true)
  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:binding_preview, :map, default: nil)
  attr(:spacecraft, :list, required: true)
  attr(:operational_observables, :list, required: true)
  attr(:filtered_points, :list, required: true)
  attr(:filtered_operational_observables, :list, required: true)
  attr(:points_empty?, :boolean, required: true)
  attr(:selected_point, :any, required: true)
  attr(:selected_points, :list, required: true)
  attr(:selected_operational_observables, :list, required: true)
  attr(:dashboard_scope_context, :any, required: true)
  attr(:dashboard_editor_focus, :map, default: nil)
  attr(:error, :string, required: true)
  attr(:mission_id, :string, required: true)
  attr(:dashboard_document, :any, default: %{sections: []})

  def widget_form(assigns) do
    assigns = assign(assigns, :presentation, widget_form_dto(assigns))

    ~H"""
    <.vue
      id="widget-form-component"
      v-component="WidgetForm"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc "Builds the JSON-safe presentation contract for the dashboard widget form."
  def widget_form_dto(assigns) do
    point_widget? = WidgetFormPresentation.point_widget?(assigns.form)

    %{
      root: %{
        id: "widget-form",
        class: "space-y-4",
        attrs: %{"phx-change" => "validate_widget", "phx-submit" => "save_widget"},
        param: assigns.form.name,
        params: active_form_params(assigns, point_widget?)
      },
      fields: primary_fields_dto(assigns),
      point_widget: point_widget_dto(assigns, point_widget?),
      non_point_help: non_point_help_dto(assigns.form, point_widget?),
      error: optional_text_dto(assigns.error, "text-sm text-error"),
      binding_preview: binding_preview_dto(assigns.binding_preview),
      actions: actions_dto(assigns.panel)
    }
  end

  defp primary_fields_dto(assigns) do
    fields = [
      field_dto(assigns.form, :type, "select", "Widget Type",
        options: WidgetFormPresentation.type_options()
      ),
      field_dto(assigns.form, :title, "text", "Title", required: true)
    ]

    if assigns.dashboard_document.sections == [] do
      fields
    else
      fields ++
        [
          field_dto(assigns.form, :section_id, "select", "Operational section",
            options: section_options(assigns.dashboard_document.sections)
          )
        ]
    end
  end

  defp point_widget_dto(_assigns, false), do: nil

  defp point_widget_dto(assigns, true) do
    form = assigns.form
    operational? = WidgetFormPresentation.operational_observable_widget?(form)
    mode = WidgetFormPresentation.form_value(form, :mode)
    type = WidgetFormPresentation.form_value(form, :type)

    %{
      hidden_fields: scope_hidden_fields_dto(form, assigns.dashboard_scope_context),
      binding_fields: binding_fields_dto(form),
      scope_override: scope_override_dto(mode, assigns.dashboard_scope_context),
      fixed_fields: fixed_fields_dto(form, mode, operational?, assigns.spacecraft),
      repeat: repeat_dto(form, mode),
      point_picker: point_picker_dto(assigns, operational?),
      operational_observable_picker: operational_observable_picker_dto(assigns, operational?),
      trailing_fields: trailing_fields_dto(form, type),
      chart_options: chart_options_dto(form, type)
    }
  end

  defp scope_hidden_fields_dto(form, dashboard_scope_context) do
    [
      hidden_field_dto(
        form[:scope_kind].name,
        WidgetFormPresentation.scope_override_kind(dashboard_scope_context)
      ),
      hidden_field_dto(
        form[:scope_id].name,
        WidgetFormPresentation.scope_override_id(dashboard_scope_context)
      )
    ]
  end

  defp binding_fields_dto(form) do
    binding_source =
      if WidgetFormPresentation.binding_source_select?(form) do
        [
          field_dto(form, :binding_source, "select", "Binding Source",
            options: WidgetFormPresentation.binding_source_options(form)
          )
        ]
      else
        []
      end

    binding_source ++
      [
        field_dto(form, :mode, "select", "Widget Scope",
          options: WidgetFormPresentation.mode_options(form)
        )
      ]
  end

  defp scope_override_dto("scope", dashboard_scope_context) do
    available? = WidgetFormPresentation.scope_override_available?(dashboard_scope_context)

    %{
      class:
        class_names([
          "flex items-start gap-1.5 rounded border px-2 py-1 text-xs",
          if(available?,
            do: "border-primary/30 bg-primary/10 text-primary",
            else: "border-warning/40 bg-warning/10 text-warning"
          )
        ]),
      attrs: %{
        "data-widget-scope-override" => "",
        "data-widget-scope-override-kind" =>
          dom_text(WidgetFormPresentation.scope_override_kind(dashboard_scope_context)),
        "data-widget-scope-override-id" =>
          dom_text(WidgetFormPresentation.scope_override_id(dashboard_scope_context)),
        "data-widget-scope-override-state" => if(available?, do: "ready", else: "missing_context")
      },
      icon: %{name: "hero-map-pin", class: "mt-0.5 h-3.5 w-3.5 shrink-0"},
      text: WidgetFormPresentation.scope_override_summary(dashboard_scope_context)
    }
  end

  defp scope_override_dto(_mode, _dashboard_scope_context), do: nil

  defp fixed_fields_dto(form, "fixed", false, spacecraft) do
    [
      field_dto(form, :spacecraft_id, "select", "Spacecraft",
        options: WidgetFormPresentation.spacecraft_options(spacecraft)
      )
    ]
  end

  defp fixed_fields_dto(_form, _mode, _operational?, _spacecraft), do: []

  defp repeat_dto(form, "repeat") do
    %{
      id: "widget-repeat-options",
      class: "space-y-3 rounded border border-primary/30 bg-primary/5 p-3",
      guidance: %{
        class: "flex items-start gap-2 text-xs text-base-content/75",
        icon: %{name: "hero-squares-2x2", class: "mt-0.5 h-4 w-4 shrink-0 text-primary"},
        text:
          "Creates one scoped widget for each resource selected in the dashboard context. Instance IDs stay stable as the selection changes."
      },
      fields: [
        field_dto(form, :repeat_over, "select", "Repeat domain",
          options: WidgetFormPresentation.repeat_over_options()
        ),
        field_dto(form, :repeat_layout, "select", "Instance layout",
          options: WidgetFormPresentation.repeat_layout_options()
        ),
        field_dto(form, :repeat_max_instances, "select", "Safety limit",
          options: WidgetFormPresentation.repeat_max_options()
        )
      ]
    }
  end

  defp repeat_dto(_form, _mode), do: nil

  defp point_picker_dto(_assigns, true), do: nil

  defp point_picker_dto(assigns, false) do
    multi? = WidgetFormPresentation.multi_point_widget?(assigns.form)

    %{
      class: "space-y-2",
      legend: WidgetFormPresentation.point_picker_legend(assigns.form),
      empty: point_picker_empty_dto(assigns.points_empty?, assigns.mission_id),
      selected_point: selected_point_dto(assigns.selected_point, multi?, assigns.points_empty?),
      selected_points:
        selected_points_dto(assigns.selected_points, multi?, assigns.points_empty?),
      search:
        point_search_dto(
          assigns.form,
          assigns.points_empty?,
          "Filter points by name or description"
        ),
      list:
        point_list_dto(
          assigns.form,
          assigns.filtered_points,
          assigns.selected_points,
          assigns.selected_point,
          assigns.points_empty?
        )
    }
  end

  defp point_picker_empty_dto(false, _mission_id), do: nil

  defp point_picker_empty_dto(true, mission_id) do
    %{
      class: "text-sm text-base-content/70",
      before_link: "No telemetry points available. Activate packet definitions in",
      link: %{
        href: ~p"/missions/#{mission_id}/catalog",
        class: "text-primary hover:underline",
        text: "Catalog",
        attrs: %{"data-phx-link" => "redirect", "data-phx-link-state" => "push"}
      },
      after_link: "/ Telemetry Decom first."
    }
  end

  defp selected_point_dto(_point, true, _empty?), do: nil
  defp selected_point_dto(_point, _multi?, true), do: nil
  defp selected_point_dto(nil, _multi?, _empty?), do: nil

  defp selected_point_dto(point, false, false) do
    %{
      class: "flex items-center gap-2 text-sm",
      point: %{class: "badge badge-primary badge-outline font-mono", text: point.point_id},
      unit: optional_text_dto(point.unit, "text-base-content/60")
    }
  end

  defp selected_points_dto(_points, false, _empty?), do: nil
  defp selected_points_dto(_points, _multi?, true), do: nil
  defp selected_points_dto([], _multi?, _empty?), do: nil

  defp selected_points_dto(points, true, false) do
    %{
      class: "flex flex-wrap gap-1",
      attrs: %{"data-selected-points" => ""},
      buttons:
        Enum.map(points, fn point ->
          %{
            key: point.point_id,
            type: "button",
            class: "badge badge-primary badge-outline gap-1 font-mono",
            attrs: %{
              "phx-click" => "pick_point",
              "phx-value-point-id" => point.point_id,
              "data-selected-point" => point.point_id,
              "aria-label" => "Remove #{point.point_id}"
            },
            text: point.point_id,
            icon: %{name: "hero-x-mark", class: "h-3 w-3"}
          }
        end)
    }
  end

  defp point_search_dto(_form, true, _placeholder), do: nil

  defp point_search_dto(form, false, placeholder) do
    field_dto(form, :point_q, "search", nil,
      placeholder: placeholder,
      attrs: %{"phx-debounce" => "150"}
    )
  end

  defp point_list_dto(_form, _points, _selected_points, _selected_point, true), do: nil

  defp point_list_dto(form, points, selected_points, selected_point, false) do
    %{
      class: "max-h-48 space-y-1 overflow-y-auto rounded border border-base-300/60 p-1",
      options:
        Enum.map(points, fn point ->
          selected? =
            WidgetFormPresentation.selected_point?(form, point, selected_points, selected_point)

          %{
            key: point.point_id,
            type: "button",
            class:
              class_names(
                WidgetFormPresentation.point_button_class(
                  form,
                  point,
                  selected_points,
                  selected_point
                )
              ),
            attrs: %{
              "phx-click" => "pick_point",
              "phx-value-point-id" => point.point_id,
              "aria-pressed" => boolean_text(selected?),
              "data-point-selected" => boolean_text(selected?)
            },
            icon:
              if(selected?,
                do: %{name: "hero-check", class: "mt-0.5 h-3.5 w-3.5 shrink-0 text-primary"},
                else: nil
              ),
            point_id: point.point_id,
            unit: optional_text_dto(point.unit, "ml-2 text-base-content/60"),
            description: optional_text_dto(point.description, "ml-2 text-base-content/60")
          }
        end),
      empty: points == [],
      empty_class: "px-2 py-1 text-sm text-base-content/60",
      empty_text: "No points match the filter."
    }
  end

  defp operational_observable_picker_dto(_assigns, false), do: nil

  defp operational_observable_picker_dto(assigns, true) do
    observables_available? = assigns.operational_observables != []
    focus_ids = readiness_focus_observable_ids(assigns.dashboard_editor_focus)

    warning =
      WidgetFormPresentation.selected_operational_observable_scope_warning(
        assigns.selected_operational_observables,
        assigns.dashboard_scope_context
      )

    warning_ids =
      assigns.selected_operational_observables
      |> WidgetFormPresentation.unsupported_selected_operational_observable_ids(
        assigns.dashboard_scope_context
      )
      |> Enum.join(" ")

    groups =
      WidgetFormPresentation.operational_observable_picker_groups(
        assigns.filtered_operational_observables,
        assigns.form
      )

    %{
      class: "space-y-2",
      attrs: %{
        "data-operational-observable-picker" => "",
        "data-operational-observable-readiness-focus-ids" => Enum.join(focus_ids, " "),
        "data-operational-observable-readiness-source-empty-reason" =>
          focus_value(assigns.dashboard_editor_focus, :source_empty_reason) || "",
        "data-operational-observable-readiness-requested-sampling" =>
          focus_value(assigns.dashboard_editor_focus, :requested_sampling) || "",
        "data-operational-observable-readiness-requested-products" =>
          focus_product_value(assigns.dashboard_editor_focus),
        "data-operational-observable-readiness-supported-products" =>
          focus_list_value(assigns.dashboard_editor_focus, :supported_products)
      },
      legend: "Operational Observables",
      empty: operational_observable_empty_dto(assigns.operational_observables),
      capability_warning:
        if(observables_available?,
          do: readiness_capability_guidance_dto(assigns.dashboard_editor_focus),
          else: nil
        ),
      selected:
        if(
          observables_available?,
          do:
            selected_operational_observables_dto(
              assigns.selected_operational_observables,
              assigns.dashboard_scope_context,
              focus_ids
            ),
          else: nil
        ),
      scope_warning:
        if(observables_available?,
          do: operational_scope_warning_dto(warning, warning_ids),
          else: nil
        ),
      search: operational_observable_search_dto(assigns.form, assigns.operational_observables),
      list:
        operational_observable_list_dto(
          groups,
          assigns.filtered_operational_observables,
          assigns.selected_operational_observables,
          assigns.dashboard_scope_context,
          focus_ids,
          assigns.operational_observables
        )
    }
  end

  defp operational_observable_empty_dto([]) do
    %{
      class: "text-sm text-base-content/70",
      text: "No backed operational observables are available for dashboard binding."
    }
  end

  defp operational_observable_empty_dto(_observables), do: nil

  defp readiness_capability_guidance_dto(focus) do
    case readiness_capability_guidance(focus) do
      nil ->
        nil

      guidance ->
        %{
          class:
            "flex items-start gap-1.5 rounded border border-warning/40 bg-warning/10 px-2 py-1 text-xs text-warning",
          attrs: %{
            "data-operational-observable-capability-warning" => "",
            "data-operational-observable-capability-warning-products" =>
              focus_product_value(focus),
            "data-operational-observable-capability-warning-supported-products" =>
              focus_list_value(focus, :supported_products)
          },
          icon: %{
            name: "hero-exclamation-triangle",
            class: "mt-0.5 h-3.5 w-3.5 shrink-0"
          },
          text: guidance
        }
    end
  end

  defp selected_operational_observables_dto([], _scope_context, _focus_ids), do: nil

  defp selected_operational_observables_dto(observables, scope_context, focus_ids) do
    %{
      class: "flex flex-wrap gap-1",
      attrs: %{"data-selected-operational-observables" => ""},
      buttons:
        Enum.map(observables, fn observable ->
          focused? = operational_observable_readiness_focus?(observable, focus_ids)

          %{
            key: observable.observable_id,
            type: "button",
            class:
              class_names([
                "badge badge-primary badge-outline gap-1 font-mono",
                focused? && "ring-2 ring-warning ring-offset-1 ring-offset-base-200"
              ]),
            attrs:
              raw_attrs(%{
                "phx-click" => "pick_point",
                "phx-value-point-id" => observable.observable_id,
                "data-selected-operational-observable" => observable.observable_id,
                "data-selected-operational-observable-readiness-focus" => boolean_text(focused?),
                "data-selected-operational-observable-scopes" =>
                  WidgetFormPresentation.operational_observable_scope_values(observable),
                "data-selected-operational-observable-source-product" =>
                  WidgetFormPresentation.operational_observable_source_product_value(observable),
                "data-selected-operational-observable-product-family" =>
                  WidgetFormPresentation.operational_observable_product_family_value(observable),
                "data-selected-operational-observable-scope-supported" =>
                  boolean_text(
                    WidgetFormPresentation.operational_observable_scope_supported?(
                      observable,
                      scope_context
                    )
                  ),
                "title" => WidgetFormPresentation.operational_observable_scope_title(observable),
                "aria-label" => "Remove #{observable.observable_id}"
              }),
            text: observable.observable_id,
            icon: %{name: "hero-x-mark", class: "h-3 w-3"}
          }
        end)
    }
  end

  defp operational_scope_warning_dto(nil, _warning_ids), do: nil

  defp operational_scope_warning_dto(warning, warning_ids) do
    %{
      class:
        "flex items-start gap-1.5 rounded border border-warning/40 bg-warning/10 px-2 py-1 text-xs text-warning",
      attrs: %{
        "data-operational-observable-scope-warning" => "",
        "data-operational-observable-scope-warning-ids" => warning_ids
      },
      icon: %{
        name: "hero-exclamation-triangle",
        class: "mt-0.5 h-3.5 w-3.5 shrink-0"
      },
      text: warning
    }
  end

  defp operational_observable_search_dto(_form, []), do: nil

  defp operational_observable_search_dto(form, _observables) do
    field_dto(form, :point_q, "search", nil,
      placeholder: "Filter operational observables",
      attrs: %{"phx-debounce" => "150"}
    )
  end

  defp operational_observable_list_dto(
         _groups,
         _filtered,
         _selected,
         _scope_context,
         _focus_ids,
         []
       ),
       do: nil

  defp operational_observable_list_dto(
         groups,
         filtered,
         selected,
         scope_context,
         focus_ids,
         _observables
       ) do
    %{
      class: "max-h-48 space-y-1 overflow-y-auto rounded border border-base-300/60 p-1",
      groups:
        Enum.map(groups, fn group ->
          %{
            key: group.id,
            attrs: %{
              "data-operational-observable-product-group" => group.id,
              "data-operational-observable-source-product" => group.source_product_value,
              "data-operational-observable-product-family" => group.product_family_value
            },
            label: %{
              class:
                "px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-normal text-base-content/50",
              attrs: %{"data-operational-observable-product-group-label" => group.id},
              text: group.label
            },
            options:
              Enum.map(group.observables, fn observable ->
                operational_observable_option_dto(
                  observable,
                  selected,
                  scope_context,
                  focus_ids
                )
              end)
          }
        end),
      empty: filtered == [],
      empty_class: "px-2 py-1 text-sm text-base-content/60",
      empty_text: "No operational observables match the filter."
    }
  end

  defp operational_observable_option_dto(observable, selected, scope_context, focus_ids) do
    selected? = WidgetFormPresentation.selected_operational_observable?(observable, selected)
    focused? = operational_observable_readiness_focus?(observable, focus_ids)

    selectable? =
      WidgetFormPresentation.operational_observable_selectable?(
        observable,
        selected,
        scope_context
      )

    %{
      key: observable.observable_id,
      type: "button",
      class:
        class_names(
          WidgetFormPresentation.operational_observable_button_class(
            observable,
            selected,
            scope_context
          ) ++ [focused? && "ring-1 ring-warning"]
        ),
      attrs:
        raw_attrs(%{
          "phx-click" => "pick_point",
          "phx-value-point-id" => observable.observable_id,
          "disabled" => not selectable?,
          "aria-pressed" => boolean_text(selected?),
          "data-operational-observable" => observable.observable_id,
          "data-operational-observable-readiness-focus" => boolean_text(focused?),
          "data-operational-observable-scopes" =>
            WidgetFormPresentation.operational_observable_scope_values(observable),
          "data-operational-observable-source-product" =>
            WidgetFormPresentation.operational_observable_source_product_value(observable),
          "data-operational-observable-product-family" =>
            WidgetFormPresentation.operational_observable_product_family_value(observable),
          "data-operational-observable-scope-supported" =>
            boolean_text(
              WidgetFormPresentation.operational_observable_scope_supported?(
                observable,
                scope_context
              )
            ),
          "data-operational-observable-selected" => boolean_text(selected?)
        }),
      icon:
        if(selected?,
          do: %{name: "hero-check", class: "mt-0.5 h-3.5 w-3.5 shrink-0 text-primary"},
          else: nil
        ),
      observable_id: observable.observable_id,
      unit: optional_text_dto(observable.unit, "ml-2 text-base-content/60"),
      name: dom_text(observable.name),
      scope_badges: WidgetFormPresentation.operational_observable_scope_badges(observable)
    }
  end

  defp trailing_fields_dto(form, type) do
    fields = [
      field_dto(form, :precision, "select", "Precision",
        options: WidgetFormPresentation.precision_options()
      )
    ]

    fields =
      if type == "value_tile" do
        fields ++ [field_dto(form, :show_unit, "checkbox", "Show engineering unit")]
      else
        fields
      end

    if type == "time_series" do
      fields ++
        [
          field_dto(form, :window_seconds, "select", "Chart Window",
            options: WidgetFormPresentation.window_options()
          )
        ]
    else
      fields
    end
  end

  defp chart_options_dto(_form, type) when type != "time_series", do: nil

  defp chart_options_dto(form, "time_series") do
    %{
      id: "time-series-presentation-options",
      class: "space-y-3 rounded border border-base-300/60 bg-base-200/30 p-3",
      label: %{class: "hud-label", text: "Chart presentation"},
      select_grid_class: "grid grid-cols-2 gap-3",
      select_fields: [
        field_dto(form, :legend_mode, "select", "Legend",
          options: WidgetFormPresentation.legend_mode_options()
        ),
        field_dto(form, :line_width, "select", "Line width",
          options: WidgetFormPresentation.line_width_options()
        ),
        field_dto(form, :fill_opacity, "select", "Area fill",
          options: WidgetFormPresentation.fill_opacity_options()
        ),
        field_dto(form, :axis_mode, "select", "Value axes",
          options: WidgetFormPresentation.axis_mode_options()
        )
      ],
      checkbox_grid_class: "grid grid-cols-2 gap-2",
      checkbox_fields: [
        field_dto(form, :show_min_max_band, "checkbox", "Show min/max band"),
        field_dto(form, :show_points, "checkbox", "Show point markers"),
        field_dto(form, :span_gaps, "checkbox", "Connect data gaps"),
        field_dto(form, :shared_tooltip, "checkbox", "Shared hover values")
      ]
    }
  end

  defp non_point_help_dto(_form, true), do: nil

  defp non_point_help_dto(form, false) do
    %{
      class: "text-sm text-base-content/70",
      text: WidgetFormPresentation.non_point_widget_help(form)
    }
  end

  defp binding_preview_dto(nil), do: nil

  defp binding_preview_dto(preview) do
    %{
      id: "widget-binding-preview",
      class: class_names(["rounded border px-3 py-2", preview_class(preview.status)]),
      attrs: raw_attrs(%{"data-binding-preview-status" => preview.status}),
      content_class: "flex items-start gap-2",
      icon: %{name: preview_icon(preview.status), class: "mt-0.5 h-4 w-4 shrink-0"},
      body_class: "min-w-0",
      title: %{class: "text-sm font-semibold", text: dom_text(preview.title)},
      message: %{class: "mt-0.5 text-xs opacity-80", text: dom_text(preview.message)},
      summary: %{
        class: "mt-2 font-mono text-[0.65rem] uppercase tracking-wide opacity-65",
        text:
          "#{preview.planned_request_count} requests / #{preview.frame_count} frames / #{preview.warning_count} warnings"
      }
    }
  end

  defp actions_dto(panel) do
    %{
      class: "flex flex-wrap items-center gap-2 border-t border-base-300/60 pt-4",
      preview: %{
        id: "test-widget-binding",
        type: "button",
        class: "btn btn-secondary",
        attrs: %{"phx-click" => "preview_widget_binding"},
        icon: %{name: "hero-beaker", class: "-ml-0.5 mr-1 h-4 w-4"},
        text: "Test binding"
      },
      submit: %{
        id: "save-dashboard-widget",
        type: "submit",
        class: "btn btn-primary",
        attrs: %{},
        text: if(match?({:edit_placement, _id}, panel), do: "Save Widget", else: "Add Widget")
      }
    }
  end

  defp field_dto(form, field, type, label, options \\ []) do
    form_field = form[field]
    errors = if Phoenix.Component.used_input?(form_field), do: form_field.errors, else: []

    if type == "checkbox" do
      checkbox_field_dto(field, form_field, label)
    else
      standard_field_dto(field, form_field, type, label, errors, options)
    end
  end

  defp standard_field_dto(field, form_field, type, label, errors, options) do
    control =
      if type == "select" do
        %{
          class: class_names(["w-full select", errors != [] && "select-error"]),
          attrs:
            raw_attrs(%{
              "id" => form_field.id,
              "name" => form_field.name,
              "required" => Keyword.get(options, :required, false),
              "multiple" => Keyword.get(options, :multiple, false)
            }),
          options:
            options
            |> Keyword.get(:options, [])
            |> Enum.map(&option_dto(&1, form_field.value))
        }
      else
        attrs =
          %{
            "id" => form_field.id,
            "name" => form_field.name,
            "type" => type,
            "value" => form_field.value,
            "placeholder" => Keyword.get(options, :placeholder),
            "required" => Keyword.get(options, :required, false)
          }
          |> Map.merge(Keyword.get(options, :attrs, %{}))
          |> raw_attrs()

        %{
          class: class_names(["w-full input", errors != [] && "input-error"]),
          attrs: attrs,
          options: []
        }
      end

    %{
      key: Atom.to_string(field),
      type: type,
      wrapper_class: "fieldset mb-3",
      label: if(label, do: %{class: "hud-label block mb-1.5", text: label}, else: nil),
      control: control,
      hidden_control: nil,
      description: nil,
      errors: Enum.map(errors, &error_dto/1)
    }
  end

  defp checkbox_field_dto(field, form_field, label) do
    %{
      key: Atom.to_string(field),
      type: "checkbox",
      wrapper_class: "fieldset mb-3",
      label: %{class: "block text-sm font-medium", text: label},
      control: %{
        class: "checkbox checkbox-sm mt-0.5",
        attrs:
          raw_attrs(%{
            "type" => "checkbox",
            "id" => form_field.id,
            "name" => form_field.name,
            "value" => "true",
            "checked" => to_string(form_field.value) == "true"
          }),
        options: []
      },
      hidden_control: %{
        attrs: %{"type" => "hidden", "name" => form_field.name, "value" => "false"}
      },
      description: nil,
      errors: []
    }
  end

  defp option_dto({label, value}, selected_value),
    do: option_dto({label, value, []}, selected_value)

  defp option_dto({label, value, attrs}, selected_value) when is_list(attrs) do
    %{
      key: dom_text(value),
      text: dom_text(label),
      attrs:
        raw_attrs(%{
          "value" => value,
          "selected" => option_selected?(selected_value, value),
          "disabled" => Keyword.get(attrs, :disabled, false),
          "title" => Keyword.get(attrs, :title)
        })
    }
  end

  defp option_dto(%{} = option, selected_value) do
    value = Map.fetch!(option, :value)

    %{
      key: dom_text(value),
      text: dom_text(Map.fetch!(option, :label)),
      attrs:
        raw_attrs(%{
          "value" => value,
          "selected" => option_selected?(selected_value, value),
          "disabled" => Map.get(option, :disabled, false),
          "title" => Map.get(option, :title, Map.get(option, :description))
        })
    }
  end

  defp hidden_field_dto(name, value) do
    %{attrs: %{"type" => "hidden", "name" => name, "value" => dom_text(value)}}
  end

  defp error_dto({message, _opts}),
    do: %{class: "mt-1.5 text-sm text-error", text: dom_text(message)}

  defp error_dto(message),
    do: %{class: "mt-1.5 text-sm text-error", text: dom_text(message)}

  defp active_form_params(assigns, point_widget?) do
    fields =
      [:type, :title] ++
        if(assigns.dashboard_document.sections == [], do: [], else: [:section_id]) ++
        active_point_form_fields(assigns, point_widget?)

    params =
      Map.new(fields, fn field ->
        {Atom.to_string(field), active_form_param_value(assigns.form, field)}
      end)

    if point_widget? do
      params
      |> Map.put(
        "scope_kind",
        dom_text(WidgetFormPresentation.scope_override_kind(assigns.dashboard_scope_context))
      )
      |> Map.put(
        "scope_id",
        dom_text(WidgetFormPresentation.scope_override_id(assigns.dashboard_scope_context))
      )
    else
      params
    end
  end

  defp active_point_form_fields(_assigns, false), do: []

  defp active_point_form_fields(assigns, true) do
    form = assigns.form
    type = WidgetFormPresentation.form_value(form, :type)
    mode = WidgetFormPresentation.form_value(form, :mode)
    operational? = WidgetFormPresentation.operational_observable_widget?(form)

    fields =
      [:scope_kind, :scope_id] ++
        if(WidgetFormPresentation.binding_source_select?(form),
          do: [:binding_source],
          else: []
        ) ++ [:mode]

    fields =
      if mode == "fixed" and not operational?, do: fields ++ [:spacecraft_id], else: fields

    fields =
      if mode == "repeat" do
        fields ++ [:repeat_over, :repeat_layout, :repeat_max_instances]
      else
        fields
      end

    fields =
      if picker_search?(assigns, operational?), do: fields ++ [:point_q], else: fields

    fields = fields ++ [:precision]
    fields = if type == "value_tile", do: fields ++ [:show_unit], else: fields

    if type == "time_series" do
      fields ++
        [
          :window_seconds,
          :legend_mode,
          :line_width,
          :fill_opacity,
          :axis_mode,
          :show_min_max_band,
          :show_points,
          :span_gaps,
          :shared_tooltip
        ]
    else
      fields
    end
  end

  defp picker_search?(assigns, true), do: assigns.operational_observables != []
  defp picker_search?(assigns, false), do: not assigns.points_empty?

  defp option_selected?(values, option_value) when is_list(values) do
    Enum.any?(values, &(to_string(&1) == to_string(option_value)))
  end

  defp option_selected?(value, option_value),
    do: to_string(value) == to_string(option_value)

  defp active_form_param_value(form, field) when field in @checkbox_form_fields do
    boolean_text(to_string(WidgetFormPresentation.form_value(form, field)) == "true")
  end

  defp active_form_param_value(form, field) do
    dom_text(WidgetFormPresentation.form_value(form, field))
  end

  defp preview_class(status) when status in [:ready, "ready"],
    do: "border-success/40 bg-success/10 text-success"

  defp preview_class(status) when status in [:no_data, "no_data"],
    do: "border-warning/40 bg-warning/10 text-warning"

  defp preview_class(_status), do: "border-error/40 bg-error/10 text-error"

  defp preview_icon(status) when status in [:ready, "ready"], do: "hero-check-circle"

  defp preview_icon(status) when status in [:no_data, "no_data"],
    do: "hero-information-circle"

  defp preview_icon(_status), do: "hero-exclamation-triangle"

  defp readiness_focus_observable_ids(%{unsupported_observables: observables})
       when is_list(observables),
       do: non_empty_strings(observables)

  defp readiness_focus_observable_ids(%{"unsupported_observables" => observables})
       when is_list(observables),
       do: non_empty_strings(observables)

  defp readiness_focus_observable_ids(%{requested_observables: observables})
       when is_list(observables),
       do: non_empty_strings(observables)

  defp readiness_focus_observable_ids(%{"requested_observables" => observables})
       when is_list(observables),
       do: non_empty_strings(observables)

  defp readiness_focus_observable_ids(_focus), do: []

  defp readiness_capability_guidance(focus) do
    if focus_value(focus, :source_empty_reason) == "unsupported_source_capability" do
      requested_sampling = focus_value(focus, :requested_sampling) || "requested"
      requested_products = focus_product_value(focus)
      supported_products = focus_list_value(focus, :supported_products)

      "Selected source cannot satisfy #{requested_sampling} for #{fallback_text(requested_products, "these operational source products")}. Supported source products: #{fallback_text(supported_products, "none")}."
    end
  end

  defp focus_value(focus, key) when is_map(focus) do
    Map.get(focus, key) || Map.get(focus, Atom.to_string(key))
  end

  defp focus_value(_focus, _key), do: nil

  defp focus_list_value(focus, key) do
    focus
    |> focus_value(key)
    |> List.wrap()
    |> non_empty_strings()
    |> Enum.join(" ")
  end

  defp focus_product_value(focus) do
    case focus_list_value(focus, :requested_source_products) do
      "" -> focus_list_value(focus, :requested_products)
      source_products -> source_products
    end
  end

  defp fallback_text("", fallback), do: fallback
  defp fallback_text(value, _fallback), do: value

  defp operational_observable_readiness_focus?(observable, focus_ids) when is_list(focus_ids) do
    observable.observable_id in focus_ids
  end

  defp non_empty_strings(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp section_options(sections) do
    [{"Unsectioned canvas", ""}] ++ Enum.map(sections, &{&1.title, &1.section_id})
  end

  defp optional_text_dto(value, _class) when value in [nil, false], do: nil
  defp optional_text_dto(value, class), do: %{class: class, text: dom_text(value)}

  defp boolean_text(true), do: "true"
  defp boolean_text(false), do: "false"

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
    |> List.flatten()
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map_join(" ", &dom_text/1)
  end

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value) when is_number(value), do: to_string(value)
  defp dom_text(value), do: to_string(value)
end
