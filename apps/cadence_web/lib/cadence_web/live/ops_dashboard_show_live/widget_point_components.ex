defmodule CadenceWeb.OpsDashboardShowLive.WidgetPointComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponents

  attr(:widget, :map, required: true)
  attr(:placement_id, :string, required: true)
  attr(:data, :map, required: true)
  attr(:compare_data, :any, default: nil)
  attr(:point, :any, default: nil)
  attr(:compare_data_view, :string, default: nil)

  def value_tile(assigns) do
    presentation = value_tile_presentation(assigns)
    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetPoint"
      presentation={@presentation}
      v-ssr={false}
      class={@presentation.host.class}
    />
    """
  end

  attr(:widget, :map, required: true)
  attr(:placement_id, :string, required: true)
  attr(:data, :any, default: nil)
  attr(:compare_data, :any, default: nil)
  attr(:point, :any, default: nil)
  attr(:backfill, :any, default: nil)
  attr(:compare_backfill, :any, default: nil)
  attr(:limit_markers, :list, default: [])
  attr(:event_markers, :list, default: [])
  attr(:annotations, :list, default: [])
  attr(:selected_data_ref, :any, default: nil)
  attr(:time_mode, :string, default: nil)
  attr(:time_from, :string, default: nil)
  attr(:time_to, :string, default: nil)
  attr(:time_axis, :string, default: nil)
  attr(:window_seconds, :integer, default: nil)
  attr(:replay_run_id, :string, default: nil)
  attr(:data_realm, :string, default: nil)
  attr(:data_view, :string, default: nil)
  attr(:compare_data_view, :string, default: nil)
  attr(:data_source_id, :string, default: nil)
  attr(:source_binding_id, :string, default: nil)
  attr(:context_spacecraft_id, :string, required: true)
  attr(:chart_epoch, :integer, required: true)
  attr(:edit_mode?, :boolean, default: false)

  def time_series_chart(assigns) do
    presentation = time_series_presentation(assigns)
    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetPoint"
      presentation={@presentation}
      v-ssr={false}
      class={@presentation.host.class}
    />
    """
  end

  attr(:placement_id, :string, required: true)
  attr(:data, :map, required: true)

  def constellation_health(assigns) do
    presentation = constellation_health_presentation(assigns)
    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetPoint"
      presentation={@presentation}
      v-ssr={false}
      class={@presentation.host.class}
    />
    """
  end

  defp value_tile_presentation(assigns) do
    unit =
      if show_unit?(assigns.widget) do
        value_tile_unit(assigns.data, assigns.point)
      end

    comparison =
      case value_tile_comparison(
             assigns.data,
             assigns.compare_data,
             assigns.widget.options.precision
           ) do
        nil ->
          nil

        comparison ->
          %{
            class: "mt-1 font-mono text-[0.65rem] text-base-content/70",
            attrs: %{
              "data-widget-compare-state" => comparison.state,
              "data-widget-compare-delta" => comparison.delta_text,
              "data-widget-compare-value" => comparison.compare_text,
              "data-widget-compare-data-view" => assigns.compare_data_view || ""
            },
            text:
              "#{comparison_view_label(assigns.compare_data_view)} compare #{comparison.delta_text}"
          }
      end

    %{
      kind: "value_tile",
      component_id: widget_point_component_id(assigns.placement_id),
      host: %{class: "contents"},
      value: %{
        container_class: "flex items-baseline gap-2",
        text: format_value(assigns.data.sample, assigns.widget.options.precision),
        class: "font-mono text-3xl font-bold tabular-nums",
        attrs: %{"data-widget-value" => ""},
        unit:
          if(unit,
            do: %{text: unit, class: "text-base text-base-content/70"}
          )
      },
      timestamp: %{
        text: Calendar.strftime(assigns.data.sample.receipt_time, "%H:%M:%S UTC"),
        class: "mt-1 font-mono text-[0.65rem] text-base-content/60"
      },
      comparison: comparison
    }
  end

  defp time_series_presentation(assigns) do
    chart_id = chart_dom_id(assigns.widget, assigns.context_spacecraft_id, assigns.chart_epoch)

    %{
      kind: "time_series",
      component_id: "widget-point-#{chart_id}-component",
      host: %{class: "contents"},
      stage: %{
        class: "cadence-time-series-stage relative flex min-h-0 flex-1",
        attrs: %{"data-dashboard-time-series-stage" => ""}
      },
      data_management:
        WidgetDataManagementComponents.chart_data_management_strip_presentation(
          assigns.placement_id,
          assigns.data,
          assigns.backfill,
          assigns.compare_data,
          assigns.compare_backfill,
          assigns.data_view,
          assigns.compare_data_view
        ),
      chart: %{
        component_id: chart_id <> "-component",
        class: "min-h-0 flex-1 overflow-hidden",
        props: time_series_chart_props(assigns, chart_id)
      }
    }
  end

  defp time_series_chart_props(assigns, chart_id) do
    %{
      chart_id: chart_id,
      widget_id: assigns.widget.widget_id,
      placement_id: assigns.placement_id,
      window_seconds: assigns.window_seconds || assigns.widget.options.window_seconds,
      correlation_group: "cadence-dashboard-time",
      edit_mode: assigns.edit_mode?,
      show_min_max_band: option_value(assigns.widget, :show_min_max_band, true),
      legend_mode: option_value(assigns.widget, :legend_mode, "auto"),
      line_width: option_value(assigns.widget, :line_width, "normal"),
      fill_opacity: option_value(assigns.widget, :fill_opacity, 8),
      span_gaps: option_value(assigns.widget, :span_gaps, false),
      show_points: option_value(assigns.widget, :show_points, false),
      axis_mode: option_value(assigns.widget, :axis_mode, "unit"),
      shared_tooltip: option_value(assigns.widget, :shared_tooltip, true),
      label: assigns.widget.title,
      unit: (assigns.point && assigns.point.unit) || "",
      backfill: assigns.backfill || [],
      compare_backfill: assigns.compare_backfill || [],
      limit_markers: assigns.limit_markers || [],
      event_markers: assigns.event_markers || [],
      annotations: assigns.annotations || [],
      selected_ref: assigns.selected_data_ref,
      time_mode: assigns.time_mode || "",
      time_from: assigns.time_from || "",
      time_to: assigns.time_to || "",
      time_axis: assigns.time_axis || "",
      replay_run_id: assigns.replay_run_id || "",
      data_realm: assigns.data_realm || "",
      data_view: assigns.data_view || "",
      compare_data_view: assigns.compare_data_view || "",
      data_source_id:
        assigns.data_source_id || chart_payload_context_value(assigns.backfill, :data_source_id),
      source_binding_id:
        assigns.source_binding_id ||
          chart_payload_context_value(assigns.backfill, :source_binding_id),
      data_management_badges:
        WidgetDataManagementComponents.widget_data_management_badge_codes([
          assigns.data,
          assigns.backfill
        ]),
      compare_data_management_badges:
        WidgetDataManagementComponents.widget_data_management_badge_codes([
          assigns.compare_data,
          assigns.compare_backfill
        ]),
      engine_backed: engine_backed?(assigns.data)
    }
  end

  defp constellation_health_presentation(assigns) do
    badges =
      Enum.map(state_severities(), fn {state, severity} ->
        severity_badge_presentation(
          severity,
          Map.get(assigns.data.counts, state, 0),
          state_label(state)
        )
      end)

    badges =
      if Map.get(assigns.data.counts, :no_data, 0) > 0 do
        badges ++
          [severity_badge_presentation(:info, assigns.data.counts.no_data, "No Data")]
      else
        badges
      end

    %{
      kind: "constellation_health",
      component_id: widget_point_component_id(assigns.placement_id),
      host: %{class: "contents"},
      badges: %{
        class: "flex flex-wrap gap-2",
        items: badges
      },
      spacecraft: %{
        class: "mt-2 flex flex-wrap gap-1",
        attrs: %{"aria-label" => "Per-spacecraft worst limit state"},
        items:
          Enum.map(assigns.data.spacecraft, fn entry ->
            %{
              key: entry.spacecraft_id,
              class: "inline-block h-3 w-3 rounded-sm #{state_dot_class(entry.worst_state)}",
              attrs: %{
                "title" => "#{entry.spacecraft_id}: #{state_label(entry.worst_state)}"
              }
            }
          end)
      }
    }
  end

  defp severity_badge_presentation(severity, count, label) do
    %{
      class:
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium #{severity_badge_class(severity)}",
      dot_class: "w-1.5 h-1.5 rounded-full bg-current",
      count: count,
      count_class: "font-mono",
      label: label,
      label_class: "uppercase text-[0.65rem]"
    }
  end

  defp widget_point_component_id(placement_id), do: "widget-point-#{placement_id}-component"

  def chart_payload_empty?(nil), do: true
  def chart_payload_empty?([]), do: true

  def chart_payload_empty?(%{series: series}) when is_list(series),
    do: Enum.all?(series, &empty_series?/1)

  def chart_payload_empty?(_payload), do: false

  defp chart_payload_context_value(%{series: [first_series | _rest]}, key)
       when is_map(first_series) do
    Map.get(first_series, key) || Map.get(first_series, to_string(key)) || ""
  end

  defp chart_payload_context_value(%{"series" => [first_series | _rest]}, key)
       when is_map(first_series) do
    Map.get(first_series, key) || Map.get(first_series, to_string(key)) || ""
  end

  defp chart_payload_context_value(_payload, _key), do: ""

  def display_value(sample) do
    if is_nil(sample.engineering_value), do: sample.raw_value, else: sample.engineering_value
  end

  defp empty_series?(%{points: points}) when is_list(points), do: points == []
  defp empty_series?(_series), do: true

  defp chart_dom_id(widget, context_spacecraft_id, epoch) do
    "tlm-chart-#{widget.widget_id}-#{context_spacecraft_id || "none"}-#{epoch}"
  end

  defp format_value(sample, precision) do
    case display_value(sample) do
      value when is_float(value) -> :erlang.float_to_binary(value, decimals: precision)
      value when is_integer(value) -> Integer.to_string(value)
      value when is_binary(value) -> value
      value -> inspect(value)
    end
  end

  defp value_tile_comparison(primary_data, compare_data, precision) do
    with primary when is_number(primary) <- point_sample_number(primary_data),
         comparison when is_number(comparison) <- point_sample_number(compare_data) do
      delta = primary - comparison

      %{
        delta_text: format_signed_number(delta, precision),
        compare_text: format_number(comparison, precision),
        state: comparison_state(delta)
      }
    else
      _missing -> nil
    end
  end

  defp point_sample_number(%{sample: sample}) when is_map(sample) do
    sample
    |> display_value()
    |> case do
      value when is_number(value) -> value
      _value -> nil
    end
  end

  defp point_sample_number(_data), do: nil

  defp format_signed_number(value, precision) when is_number(value) do
    sign = if value > 0, do: "+", else: ""
    sign <> format_number(value, precision)
  end

  defp format_number(value, precision) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: precision)

  defp format_number(value, _precision) when is_integer(value), do: Integer.to_string(value)

  defp comparison_state(value) when value > 0, do: "increased"
  defp comparison_state(value) when value < 0, do: "decreased"
  defp comparison_state(_value), do: "unchanged"

  defp value_tile_unit(%{unit: unit}, _point) when is_binary(unit) and unit != "", do: unit
  defp value_tile_unit(_data, %{unit: unit}) when is_binary(unit) and unit != "", do: unit
  defp value_tile_unit(_data, _point), do: nil

  defp show_unit?(widget), do: option_value(widget, :show_unit, true) == true

  defp option_value(%{options: options}, key, default) when is_map(options) do
    Map.get(options, key, Map.get(options, to_string(key), default))
  end

  defp option_value(_widget, _key, default), do: default

  defp data_view_options do
    [
      {"Canonical", "canonical"},
      {"As recorded", "as_recorded"},
      {"All revisions", "all_revisions"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp data_view_label(value) do
    value = present_text(value)

    data_view_options()
    |> Enum.find_value(value || "Canonical", fn {label, option_value} ->
      if option_value == value, do: label
    end)
  end

  defp comparison_view_label(value) do
    case present_text(value) do
      nil -> "Compare"
      value -> data_view_label(value)
    end
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

  defp state_severities,
    do: [{:red, :critical}, {:yellow, :warning}, {:blue, :info}, {:green, :nominal}]

  defp state_label(:red), do: "Red"
  defp state_label(:yellow), do: "Yellow"
  defp state_label(:blue), do: "Blue"
  defp state_label(:green), do: "Green"
  defp state_label(nil), do: "No data"

  defp severity_badge_class(:critical), do: "bg-error/20 text-error"
  defp severity_badge_class(:warning), do: "bg-warning/20 text-warning"
  defp severity_badge_class(:info), do: "bg-info/20 text-info"
  defp severity_badge_class(:nominal), do: "bg-success/20 text-success"

  defp state_dot_class(:red), do: "bg-error"
  defp state_dot_class(:yellow), do: "bg-warning"
  defp state_dot_class(:blue), do: "bg-info"
  defp state_dot_class(:green), do: "bg-success"
  defp state_dot_class(nil), do: "bg-base-300"

  defp engine_backed?(%{engine_backed?: true}), do: true
  defp engine_backed?(_data), do: false
end
