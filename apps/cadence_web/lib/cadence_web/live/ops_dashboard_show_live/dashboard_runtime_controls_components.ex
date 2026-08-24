defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.MarkerCategories

  attr :time_mode, :string, required: true
  attr :time_axis, :string, default: "generation_time"
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :replay_run_id, :string, default: nil
  attr :time_validation, :string, default: "ok"
  attr :data_realm, :string, required: true
  attr :data_realms, :list, required: true
  attr :data_view, :string, required: true
  attr :compare_data_view, :string, default: nil
  attr :data_source_id, :string, default: nil
  attr :source_binding_id, :string, default: nil
  attr :data_bindings, :list, required: true
  attr :replay_runs, :list, default: []
  attr :selected_replay_run, :any, default: nil
  attr :limit_mode, :string, required: true
  attr :limit_mode_fallback, :map, default: nil
  attr :hidden_marker_categories, :list, default: []
  attr :selected_data_ref, :any, default: nil
  attr :section, :atom, values: [:all, :data], default: :all

  def runtime_context_controls(assigns) do
    data_form = to_form(runtime_form_params(assigns))
    assigns = assign(assigns, :runtime_controls, runtime_controls_dto(assigns, data_form))

    ~H"""
    <.vue
      id="dashboard-runtime-controls-component"
      v-component="DashboardRuntimeControls"
      runtime_controls={@runtime_controls}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp runtime_controls_dto(assigns, data_form) do
    %{
      root: %{
        attrs: %{
          id: runtime_controls_id(assigns.section),
          "data-dashboard-query-control-section": to_string(assigns.section),
          class: "min-w-0"
        }
      },
      header: %{
        class: "flex items-start justify-between gap-3",
        copy: %{
          heading: %{
            class: "text-xs font-semibold text-base-content/85",
            text: "Active telemetry source"
          },
          description: %{
            class: "mt-0.5 text-[0.68rem] text-base-content/50",
            text: "Defaults follow the dashboard definition. Overrides stay in the URL."
          }
        },
        active_source: active_source_dto(assigns.data_source_id, assigns.source_binding_id)
      },
      form: %{
        attrs: %{
          id: "runtime-context-form",
          "phx-change": "set_runtime_context",
          class: "mt-3"
        },
        hidden_fields: [
          hidden_field_dto(data_form[:time_mode], "dashboard-time-mode"),
          hidden_field_dto(data_form[:from], "dashboard-data-form-from"),
          hidden_field_dto(data_form[:to], "dashboard-data-form-to"),
          hidden_field_dto(data_form[:replay_run_id], "dashboard-replay-run-id")
        ],
        source:
          section_dto(
            "dashboard-source-query-heading",
            "Source",
            "grid gap-2 sm:grid-cols-[9rem_minmax(0,1fr)]",
            [
              select_field_dto(
                data_form[:realm],
                "dashboard-data-realm",
                "Realm",
                realm_options(assigns.data_realms),
                "select-xs"
              ),
              select_field_dto(
                data_form[:source_binding_id],
                "dashboard-source-binding",
                "Source binding",
                source_binding_options(assigns.data_bindings, assigns.data_realm),
                "select-xs font-mono"
              )
            ]
          ),
        representation:
          section_dto(
            "dashboard-representation-query-heading",
            "Representation",
            "grid gap-2 sm:grid-cols-2",
            [
              select_field_dto(
                data_form[:data_view],
                "dashboard-data-view",
                "Data view",
                data_view_options(),
                "select-xs"
              ),
              select_field_dto(
                data_form[:compare_data_view],
                "dashboard-compare-data-view",
                "Compare against",
                compare_data_view_options(assigns.data_view),
                "select-xs"
              )
            ]
          ),
        semantics:
          section_dto(
            "dashboard-semantics-query-heading",
            "Operational semantics",
            "grid gap-2 sm:grid-cols-2",
            [
              select_field_dto(
                data_form[:time_axis],
                "dashboard-time-axis",
                "Time basis",
                time_axis_options(),
                "select-xs"
              ),
              select_field_dto(
                data_form[:limit_mode],
                "dashboard-limit-mode",
                "Limit semantics",
                limit_mode_options(),
                "select-xs"
              )
            ],
            limit_mode_fallback_dto(assigns.limit_mode_fallback)
          ),
        markers: marker_section_dto(assigns.hidden_marker_categories)
      }
    }
  end

  defp active_source_dto(data_source_id, source_binding_id) do
    label = source_context_label(data_source_id, source_binding_id)

    %{
      attrs: %{
        id: "dashboard-active-source",
        "data-dashboard-active-data-source": data_source_id,
        "data-dashboard-active-source-binding": source_binding_id,
        class: "badge badge-primary badge-outline badge-xs max-w-64 truncate font-mono",
        title: label
      },
      text: label
    }
  end

  defp hidden_field_dto(field, id) do
    %{
      wrapper_class: "fieldset",
      attrs: %{
        id: id,
        name: field.name,
        type: "hidden",
        value: field.value,
        required: false,
        disabled: false,
        class: "w-full input"
      }
    }
  end

  defp select_field_dto(field, id, label, options, class) do
    %{
      wrapper_class: "fieldset",
      label: %{class: "hud-label block mb-1.5", text: label},
      attrs: %{
        id: id,
        name: field.name,
        required: false,
        multiple: false,
        disabled: false,
        class: "w-full select #{class}"
      },
      options: Enum.map(options, &select_option_dto(&1, field.value))
    }
  end

  defp select_option_dto({label, value}, selected_value) do
    %{
      label: label,
      value: to_string(value),
      selected: to_string(selected_value) == to_string(value),
      disabled: false,
      title: nil
    }
  end

  defp section_dto(heading_id, heading, fields_class, fields, badge \\ nil) do
    %{
      attrs: %{
        class: "cadence-dashboard-query-section",
        "aria-labelledby": heading_id
      },
      heading: %{
        attrs: %{
          id: heading_id,
          class: "mb-2 text-xs font-semibold text-base-content/85"
        },
        text: heading
      },
      fields_class: fields_class,
      fields: fields,
      badge: badge
    }
  end

  defp limit_mode_fallback_dto(fallback) do
    if limit_mode_fallback?(fallback) do
      %{
        attrs: %{
          id: "dashboard-limit-mode-fallback",
          "data-requested-limit-mode": limit_mode_fallback_value(fallback, "requested_mode"),
          "data-applied-limit-mode": limit_mode_fallback_value(fallback, "applied_mode"),
          "data-limit-mode-fallback-reason": limit_mode_fallback_value(fallback, "reason"),
          class: "badge badge-warning badge-xs mt-2 gap-1",
          title: limit_mode_fallback_title(fallback)
        },
        icon_class: "hero-exclamation-triangle h-3 w-3",
        text: "Observed only"
      }
    end
  end

  defp marker_section_dto(hidden_marker_categories) do
    hidden_count = length(hidden_marker_categories)

    %{
      attrs: %{
        class: "cadence-dashboard-query-section",
        "aria-labelledby": "dashboard-markers-query-heading"
      },
      heading: %{
        attrs: %{
          id: "dashboard-markers-query-heading",
          class: "mb-2 text-xs font-semibold text-base-content/85"
        },
        text: "Chart markers",
        hidden_count:
          if(hidden_count > 0,
            do: %{
              attrs: %{
                id: "dashboard-markers-hidden-count",
                class: "badge badge-warning badge-xs ml-1"
              },
              text: "#{hidden_count} hidden"
            }
          )
      },
      toggles: %{
        attrs: %{
          id: "dashboard-marker-toggles",
          class: "grid gap-1 sm:grid-cols-2"
        },
        fields:
          Enum.map(MarkerCategories.category_options(), fn {label, key} ->
            marker_field_dto(label, key, hidden_marker_categories)
          end)
      }
    }
  end

  defp marker_field_dto(label, key, hidden_marker_categories) do
    name = "markers[#{key}]"

    %{
      wrapper_class: "fieldset",
      label_class: "flex cursor-pointer items-start gap-3",
      false_input_attrs: %{
        type: "hidden",
        name: name,
        value: "false"
      },
      input_attrs: %{
        type: "checkbox",
        id: "dashboard-marker-#{key}",
        name: name,
        value: "true",
        checked: not MarkerCategories.hidden?(hidden_marker_categories, key),
        required: false,
        disabled: false,
        class: "checkbox checkbox-sm mt-0.5 checkbox-xs"
      },
      label: %{
        class: "block text-sm font-medium",
        text: label
      }
    }
  end

  defp runtime_controls_id(:all), do: "runtime-context-controls"
  defp runtime_controls_id(:data), do: "dashboard-data-query-controls"

  defp runtime_form_params(assigns) do
    %{
      "time_mode" => assigns.time_mode,
      "time_axis" => assigns.time_axis,
      "from" => assigns.time_from || "",
      "to" => assigns.time_to || "",
      "replay_run_id" => assigns.replay_run_id || "",
      "realm" => assigns.data_realm,
      "data_view" => assigns.data_view,
      "compare_data_view" => assigns.compare_data_view || "",
      "limit_mode" => assigns.limit_mode,
      "source_binding_id" => assigns.source_binding_id || ""
    }
  end

  defp limit_mode_options do
    [
      {"Observed", "observed"},
      {"Current", "current"},
      {"Recomputed", "recomputed"},
      {"Compare", "compare"}
    ]
  end

  defp time_axis_options do
    [
      {"Generation", "generation_time"},
      {"Receipt", "receipt_time"}
    ]
  end

  defp limit_mode_fallback?(fallback) when is_map(fallback),
    do: present_text(Map.get(fallback, "requested_mode")) != nil

  defp limit_mode_fallback?(_fallback), do: false

  defp limit_mode_fallback_value(fallback, key) when is_map(fallback),
    do: present_text(Map.get(fallback, key))

  defp limit_mode_fallback_value(_fallback, _key), do: nil

  defp limit_mode_fallback_title(fallback) do
    requested = limit_mode_fallback_value(fallback, "requested_mode") || "requested"
    applied = limit_mode_fallback_value(fallback, "applied_mode") || "observed"

    "Requested #{requested} limit semantics; using #{applied}."
  end

  defp data_view_options do
    [
      {"Canonical", "canonical"},
      {"As recorded", "as_recorded"},
      {"All revisions", "all_revisions"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp compare_data_view_options(active_data_view) do
    [
      {"No compare", ""}
      | Enum.reject(data_view_options(), fn {_label, view} -> view == active_data_view end)
    ]
  end

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil

  defp realm_options(realms) do
    Enum.map(realms, fn realm -> {String.capitalize(to_string(realm)), realm} end)
  end

  defp source_binding_options(bindings, realm) do
    options =
      bindings
      |> Enum.filter(&telemetry_binding_for_realm?(&1, realm))
      |> Enum.sort_by(&{&1.priority, &1.binding_id})
      |> Enum.map(fn binding -> {source_binding_option_label(binding), binding.binding_id} end)

    [{"Primary source", ""} | options]
  end

  defp telemetry_binding_for_realm?(binding, realm) do
    binding.logical_source == :telemetry and normalize_realm(binding.realm) == realm and
      DataBinding.active?(binding)
  end

  defp source_binding_option_label(binding) do
    "#{binding.binding_id} / #{binding.data_source_id}"
  end

  defp source_context_label(nil, nil), do: "Primary source"
  defp source_context_label(nil, ""), do: "Primary source"
  defp source_context_label("", ""), do: "Primary source"
  defp source_context_label(data_source_id, nil), do: data_source_id
  defp source_context_label(data_source_id, ""), do: data_source_id
  defp source_context_label(_data_source_id, source_binding_id), do: source_binding_id

  defp normalize_realm(realm) when is_atom(realm), do: Atom.to_string(realm)
  defp normalize_realm(realm) when is_binary(realm), do: realm
  defp normalize_realm(_realm), do: nil
end
