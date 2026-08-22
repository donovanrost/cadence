defmodule CadenceWeb.OpsDashboardShowLive.WidgetPointComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponents

  attr :widget, :map, required: true
  attr :data, :map, required: true
  attr :compare_data, :any, default: nil
  attr :point, :any, default: nil
  attr :compare_data_view, :string, default: nil

  def value_tile(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2">
      <span class="font-mono text-3xl font-bold tabular-nums" data-widget-value>
        {format_value(@data.sample, @widget.options.precision)}
      </span>
      <span
        :if={show_unit?(@widget) and value_tile_unit(@data, @point)}
        class="text-base text-base-content/70"
      >
        {value_tile_unit(@data, @point)}
      </span>
    </div>
    <p class="mt-1 font-mono text-[0.65rem] text-base-content/60">
      {Calendar.strftime(@data.sample.receipt_time, "%H:%M:%S UTC")}
    </p>
    <%= case value_tile_comparison(@data, @compare_data, @widget.options.precision) do %>
      <% nil -> %>
      <% comparison -> %>
        <p
          class="mt-1 font-mono text-[0.65rem] text-base-content/70"
          data-widget-compare-state={comparison.state}
          data-widget-compare-delta={comparison.delta_text}
          data-widget-compare-value={comparison.compare_text}
          data-widget-compare-data-view={@compare_data_view || ""}
        >
          {comparison_view_label(@compare_data_view)} compare {comparison.delta_text}
        </p>
    <% end %>
    """
  end

  attr :widget, :map, required: true
  attr :placement_id, :string, required: true
  attr :data, :any, default: nil
  attr :compare_data, :any, default: nil
  attr :point, :any, default: nil
  attr :backfill, :any, default: nil
  attr :compare_backfill, :any, default: nil
  attr :limit_markers, :list, default: []
  attr :event_markers, :list, default: []
  attr :annotations, :list, default: []
  attr :selected_data_ref, :any, default: nil
  attr :time_mode, :string, default: nil
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :time_axis, :string, default: nil
  attr :window_seconds, :integer, default: nil
  attr :replay_run_id, :string, default: nil
  attr :data_realm, :string, default: nil
  attr :data_view, :string, default: nil
  attr :compare_data_view, :string, default: nil
  attr :data_source_id, :string, default: nil
  attr :source_binding_id, :string, default: nil
  attr :context_spacecraft_id, :string, required: true
  attr :chart_epoch, :integer, required: true
  attr :edit_mode?, :boolean, default: false

  def time_series_chart(assigns) do
    ~H"""
    <div
      class={[
        "cadence-time-series-stage",
        "relative flex min-h-0 flex-1"
      ]}
      data-dashboard-time-series-stage
    >
      <WidgetDataManagementComponents.chart_data_management_strip
        data={@data}
        backfill={@backfill}
        compare_data={@compare_data}
        compare_backfill={@compare_backfill}
        data_view={@data_view}
        compare_data_view={@compare_data_view}
      />
      <div
        id={chart_dom_id(@widget, @context_spacecraft_id, @chart_epoch)}
        phx-hook="TelemetryChart"
        phx-update="ignore"
        data-widget-id={@widget.widget_id}
        data-placement-id={@placement_id}
        data-window-seconds={@window_seconds || @widget.options.window_seconds}
        data-correlation-group="cadence-dashboard-time"
        data-edit-mode={to_string(@edit_mode?)}
        data-show-min-max-band={option_text(@widget, :show_min_max_band, true)}
        data-legend-mode={option_text(@widget, :legend_mode, "auto")}
        data-line-width={option_text(@widget, :line_width, "normal")}
        data-fill-opacity={option_text(@widget, :fill_opacity, 8)}
        data-span-gaps={option_text(@widget, :span_gaps, false)}
        data-show-points={option_text(@widget, :show_points, false)}
        data-axis-mode={option_text(@widget, :axis_mode, "unit")}
        data-shared-tooltip={option_text(@widget, :shared_tooltip, true)}
        data-label={@widget.title}
        data-unit={(@point && @point.unit) || ""}
        data-backfill={Jason.encode!(@backfill || [])}
        data-compare-backfill={Jason.encode!(@compare_backfill || [])}
        data-limit-markers={Jason.encode!(@limit_markers || [])}
        data-event-markers={Jason.encode!(@event_markers || [])}
        data-annotations={Jason.encode!(@annotations || [])}
        data-selected-ref={Jason.encode!(@selected_data_ref)}
        data-time-mode={@time_mode || ""}
        data-time-from={@time_from || ""}
        data-time-to={@time_to || ""}
        data-time-axis={@time_axis || ""}
        data-replay-run-id={@replay_run_id || ""}
        data-data-realm={@data_realm || ""}
        data-data-view={@data_view || ""}
        data-compare-data-view={@compare_data_view || ""}
        data-data-source-id={
          @data_source_id || chart_payload_context_value(@backfill, :data_source_id)
        }
        data-source-binding-id={
          @source_binding_id || chart_payload_context_value(@backfill, :source_binding_id)
        }
        data-data-management-badges={
          WidgetDataManagementComponents.widget_data_management_badge_codes([@data, @backfill])
        }
        data-compare-data-management-badges={
          WidgetDataManagementComponents.widget_data_management_badge_codes([
            @compare_data,
            @compare_backfill
          ])
        }
        data-engine-backed={if engine_backed?(@data), do: "true"}
        data-panel-presentation="grafana"
        class={[
          "cadence-time-series-chart",
          "min-h-0 flex-1 overflow-hidden"
        ]}
      >
      </div>
    </div>
    """
  end

  attr :data, :map, required: true

  def constellation_health(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <.severity_badge
        :for={{state, severity} <- state_severities()}
        severity={severity}
        count={Map.get(@data.counts, state, 0)}
        label={state_label(state)}
      />
      <.severity_badge
        :if={Map.get(@data.counts, :no_data, 0) > 0}
        severity={:info}
        count={@data.counts.no_data}
        label="No Data"
      />
    </div>
    <div class="mt-2 flex flex-wrap gap-1" aria-label="Per-spacecraft worst limit state">
      <span
        :for={entry <- @data.spacecraft}
        title={"#{entry.spacecraft_id}: #{state_label(entry.worst_state)}"}
        class={["inline-block h-3 w-3 rounded-sm", state_dot_class(entry.worst_state)]}
      >
      </span>
    </div>
    """
  end

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

  defp option_text(widget, key, default), do: widget |> option_value(key, default) |> to_string()

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

  defp state_dot_class(:red), do: "bg-error"
  defp state_dot_class(:yellow), do: "bg-warning"
  defp state_dot_class(:blue), do: "bg-info"
  defp state_dot_class(:green), do: "bg-success"
  defp state_dot_class(nil), do: "bg-base-300"

  defp engine_backed?(%{engine_backed?: true}), do: true
  defp engine_backed?(_data), do: false
end
