defmodule CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponents do
  @moduledoc """
  Grafana-style dashboard time range picker.

  Toolbar cluster: picker popover plus archive-only shift and zoom controls.
  The popover pairs an absolute From/To form and
  recently used ranges with a searchable quick-range list; quick ranges keep
  the dashboard live with a sliding window, absolute bounds freeze it into
  archive mode.
  """
  use CadenceWeb, :html

  alias Cadence.Dashboards.TimeRange
  alias CadenceWeb.OpsDashboardShowLive.DashboardTimeReplayComponents
  alias Phoenix.LiveView.JS

  attr(:time_mode, :string, required: true)
  attr(:time_axis, :string, default: "generation_time")
  attr(:time_from, :string, default: nil)
  attr(:time_to, :string, default: nil)
  attr(:replay_run_id, :string, default: nil)
  attr(:time_validation, :string, default: "ok")
  attr(:data_realm, :string, required: true)
  attr(:data_view, :string, required: true)
  attr(:compare_data_view, :string, default: nil)
  attr(:source_binding_id, :string, default: nil)
  attr(:limit_mode, :string, required: true)
  attr(:replay_runs, :list, default: [])
  attr(:selected_replay_run, :any, default: nil)
  attr(:selected_data_ref, :any, default: nil)
  attr(:quick_query, :string, default: "")
  attr(:recent_ranges, :list, default: [])

  def time_toolbar_cluster(assigns) do
    assigns = assign(assigns, :presentation, time_toolbar_presentation(assigns))

    ~H"""
    <.vue
      id="dashboard-time-picker-component"
      v-component="DashboardTimePicker"
      presentation={@presentation}
      v-on:recents-loaded={JS.push("time_recents_loaded")}
      v-on:select-range={JS.push("set_chart_time_range")}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def time_toolbar_presentation(assigns) do
    bounded? = range_bounded?(assigns)

    %{
      shift_back: bounded? && shift_button_presentation("dashboard-time-shift-back", "back"),
      overlay: overlay_presentation(assigns),
      time_picker: %{
        class: "flex gap-3",
        absolute_range_host: component_host("dashboard-time-absolute-range-component"),
        absolute_range: absolute_range_presentation(assigns),
        quick_ranges_host: component_host("dashboard-time-quick-ranges-component"),
        quick_ranges: quick_range_presentation(assigns)
      },
      replay_host: component_host("dashboard-time-replay-component"),
      replay: DashboardTimeReplayComponents.replay_presentation(assigns),
      selected_datum_host: component_host("dashboard-selected-datum-actions-component"),
      selected_datum: DashboardTimeReplayComponents.selected_datum_presentation(assigns),
      shift_forward:
        bounded? && shift_button_presentation("dashboard-time-shift-forward", "forward"),
      zoom_out: bounded? && zoom_out_presentation()
    }
  end

  defp component_host(id), do: %{attrs: %{id: id, class: "contents"}}

  defp overlay_presentation(assigns) do
    %{
      root: %{
        attrs: %{
          id: "dashboard-time-controls",
          "data-overlay-kind": "popover",
          "data-overlay-placement": "bottom-end",
          class: "cadence-overlay",
          "data-query-state": assigns.time_mode,
          "data-dashboard-primary-control": "time"
        }
      },
      trigger: %{
        attrs: %{
          id: "dashboard-time-controls-toggle",
          type: "button",
          "data-overlay-trigger": "",
          "aria-haspopup": "dialog",
          "aria-expanded": "false",
          "aria-controls": "dashboard-time-controls-panel",
          "aria-label": "Dashboard time range",
          class: "cadence-overlay-trigger cadence-dashboard-query-trigger"
        },
        live_indicator: %{
          attrs: %{
            id: "dashboard-live-follow-indicator",
            class: "cadence-dashboard-query-dot",
            "data-dashboard-live-follow": to_string(assigns.time_mode == "live"),
            "aria-hidden": "true"
          }
        },
        active_range: %{
          attrs: %{
            id: "dashboard-active-time-range",
            class: "cadence-dashboard-query-trigger-value max-w-48",
            "data-dashboard-time-mode": assigns.time_mode,
            "data-dashboard-time-summary": assigns.time_mode
          },
          text: time_query_label(assigns)
        },
        icon_class: "hero-chevron-down h-3 w-3 shrink-0 text-base-content/40"
      },
      panel: %{
        attrs: %{
          id: "dashboard-time-controls-panel",
          "data-overlay-panel": "",
          "data-overlay-width": "lg",
          "aria-label": "Dashboard time range",
          class: "cadence-overlay-panel cadence-popover-panel",
          hidden: true
        },
        header: %{
          class: "cadence-dashboard-query-panel-header",
          icon_class: "hero-clock mt-0.5 h-4 w-4 text-primary",
          title: %{class: "text-xs font-semibold text-base-content/85", text: "Dashboard time"},
          description: %{
            class: "mt-0.5 text-[0.68rem] text-base-content/50",
            text: "Follow live telemetry, inspect history, or select a replay run."
          }
        },
        body: %{
          class: "cadence-dashboard-query-panel-body",
          controls: %{
            attrs: %{
              id: "dashboard-time-query-controls",
              "data-dashboard-query-control-section": "time",
              class: "min-w-0"
            }
          }
        }
      }
    }
  end

  defp shift_button_presentation(id, direction) do
    label = "Move time range #{direction}wards"

    %{
      attrs: %{
        id: id,
        type: "button",
        class: "btn btn-ghost btn-xs",
        "phx-click": "shift_time_range",
        "phx-value-direction": direction,
        "aria-label": label,
        title: label
      },
      icon_class:
        "#{if(direction == "back", do: "hero-chevron-left", else: "hero-chevron-right")} h-3.5 w-3.5"
    }
  end

  defp zoom_out_presentation do
    %{
      attrs: %{
        id: "dashboard-time-zoom-out",
        type: "button",
        class: "btn btn-ghost btn-xs",
        "phx-click": "zoom_out_time_range",
        "aria-label": "Zoom out time range",
        title: "Zoom out time range"
      },
      icon_class: "hero-magnifying-glass-minus h-3.5 w-3.5"
    }
  end

  defp absolute_range_presentation(assigns) do
    range_form =
      to_form(%{"from" => assigns.time_from || "", "to" => assigns.time_to || ""})

    %{
      root: %{attrs: %{class: "min-w-0 flex-1"}},
      heading: %{
        attrs: %{
          id: "dashboard-range-heading",
          class: "text-xs font-semibold text-base-content/85"
        },
        text: "Absolute time range"
      },
      form: absolute_range_form_dto(range_form),
      validation: time_validation_dto(assigns.time_validation),
      recents: recent_ranges_dto(assigns.recent_ranges)
    }
  end

  defp absolute_range_form_dto(range_form) do
    %{
      attrs: %{
        id: "dashboard-custom-range-form",
        "phx-submit": "set_chart_time_range",
        class: "mt-2"
      },
      from:
        absolute_range_field_dto(
          range_form[:from],
          "dashboard-time-from",
          "From",
          "now-6h or 2026-08-01T16:30:00Z"
        ),
      to: %{
        margin_class: "mt-2",
        field: absolute_range_field_dto(range_form[:to], "dashboard-time-to", "To", "now")
      },
      submit: %{
        attrs: %{
          id: "dashboard-apply-time-range",
          type: "submit",
          class: "btn btn-primary btn-xs mt-2"
        },
        text: "Apply time range"
      }
    }
  end

  defp absolute_range_field_dto(field, id, label, placeholder) do
    %{
      wrapper_class: "fieldset",
      label: %{class: "hud-label block mb-1.5", text: label},
      attrs: %{
        id: id,
        name: field.name,
        type: "text",
        value: field.value,
        placeholder: placeholder,
        required: false,
        autocomplete: nil,
        class: "w-full input input-xs font-mono"
      }
    }
  end

  defp time_validation_dto("ok"), do: nil

  defp time_validation_dto(time_validation) do
    %{
      attrs: %{
        id: "dashboard-time-validation",
        "data-time-validation": time_validation,
        class: "badge badge-warning badge-xs mt-2"
      },
      text: "Time reset"
    }
  end

  defp recent_ranges_dto(recent_ranges) do
    %{
      attrs: %{
        id: "dashboard-time-recents",
        class: "mt-3 border-t border-base-300/60 pt-2"
      },
      ranges:
        Enum.map(recent_ranges, fn range ->
          %{
            from: range.from,
            to: range.to,
            label: TimeRange.label(range.from, range.to) || "#{range.from} to #{range.to}"
          }
        end)
    }
  end

  defp quick_range_presentation(assigns) do
    search_form = to_form(%{"query" => assigns.quick_query})
    search_field = search_form[:query]
    live_selected? = assigns.time_mode == "live" and is_nil(assigns.time_from)

    live_items =
      if quick_match?("Live", assigns.quick_query) do
        [
          quick_range_button_dto(
            "dashboard-time-preset-live",
            "live",
            "Live",
            live_selected?,
            live_selected?,
            "Return to live dashboard time"
          )
        ]
      else
        []
      end

    range_items =
      assigns.quick_query
      |> filter_quick_ranges()
      |> Enum.map(fn range ->
        quick_range_button_dto(
          "dashboard-time-preset-#{String.replace(range.key, "_", "-")}",
          range.key,
          range.label,
          quick_range_selected?(range, assigns.time_mode, assigns.time_from, assigns.time_to),
          false,
          "Follow the #{String.downcase(range.label)} as a sliding window"
        )
      end)

    %{
      root: %{
        attrs: %{class: "w-44 shrink-0 border-l border-base-300/60 pl-3"}
      },
      search: %{
        form: %{
          attrs: %{
            id: "dashboard-time-quick-search-form",
            "phx-change": "time_quick_search",
            onsubmit: "return false"
          }
        },
        field: %{
          wrapper_class: "fieldset",
          attrs: %{
            id: "dashboard-time-quick-search",
            name: search_field.name,
            type: "search",
            value: search_field.value,
            placeholder: "Search quick ranges",
            required: false,
            autocomplete: nil,
            class: "w-full input",
            "phx-debounce": "150"
          }
        }
      },
      presets: %{
        attrs: %{
          id: "dashboard-time-presets",
          role: "presentation",
          "aria-label": "Quick time ranges",
          class: "mt-2 max-h-56 overflow-y-auto"
        },
        items: live_items ++ range_items
      }
    }
  end

  defp quick_range_button_dto(id, preset, label, selected?, disabled, title) do
    state_class =
      if selected? do
        "bg-primary/10 font-semibold text-primary"
      else
        "text-base-content/80 hover:bg-base-300/40 hover:text-base-content"
      end

    %{
      key: id,
      attrs: %{
        id: id,
        type: "button",
        "phx-click": "set_time_preset",
        "phx-value-preset": preset,
        disabled: disabled,
        "aria-current": to_string(selected?),
        title: title,
        class: "flex w-full items-center gap-1.5 px-2 py-1 text-left text-xs #{state_class}"
      },
      indicator_class: if(preset == "live", do: "h-1.5 w-1.5 rounded-full bg-success"),
      label: label
    }
  end

  def time_query_label(%{time_mode: "live"} = assigns) do
    TimeRange.label(assigns.time_from, assigns.time_to) || "Live"
  end

  def time_query_label(%{time_mode: "replay_run"} = assigns) do
    case assigns.replay_run_id do
      value when is_binary(value) and value != "" -> "Replay · #{value}"
      _missing -> "Replay"
    end
  end

  def time_query_label(assigns) do
    case {short_timestamp(assigns.time_from), short_timestamp(assigns.time_to)} do
      {nil, nil} -> "Selected historical range"
      {from_text, to_text} -> "#{from_text || "…"} → #{to_text || "…"}"
    end
  end

  defp short_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> Calendar.strftime(timestamp, "%b %-d %H:%M UTC")
      _invalid -> value
    end
  end

  defp short_timestamp(_value), do: nil

  defp range_bounded?(assigns) do
    assigns.time_mode in ["live", "archive"] and
      match?(
        {:ok, _resolution},
        TimeRange.resolve(assigns.time_from, assigns.time_to, DateTime.utc_now())
      )
  end

  defp quick_range_selected?(range, "live", time_from, time_to),
    do: range.from == time_from and range.to == time_to

  defp quick_range_selected?(_range, _mode, _from, _to), do: false

  defp filter_quick_ranges(query) do
    Enum.filter(TimeRange.quick_ranges(), &quick_match?(&1.label, query))
  end

  defp quick_match?(_label, query) when query in [nil, ""], do: true

  defp quick_match?(label, query) do
    haystack = String.downcase(label)

    query
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.all?(&String.contains?(haystack, &1))
  end
end
