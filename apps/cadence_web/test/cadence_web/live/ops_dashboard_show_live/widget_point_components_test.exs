defmodule CadenceWeb.OpsDashboardShowLive.WidgetPointComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetPointComponents

  test "value_tile renders displayed sample value, unit, and comparison delta" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: widget(:value_tile),
        placement_id: "placement-1",
        data: point_data(42.25),
        compare_data: point_data(40.0),
        point: %{unit: "V"},
        compare_data_view: "all_revisions"
      )

    {_vue, presentation} = point_presentation(html, "widget-point-placement-1-component")

    assert presentation["value"]["text"] == "42.25"
    assert presentation["value"]["container_class"] == "flex items-baseline gap-2"
    assert presentation["value"]["class"] == "font-mono text-3xl font-bold tabular-nums"
    assert presentation["value"]["attrs"] == %{"data-widget-value" => ""}
    assert presentation["value"]["unit"]["text"] == "V"
    assert presentation["value"]["unit"]["class"] == "text-base text-base-content/70"

    assert presentation["timestamp"] == %{
             "text" => "12:00:00 UTC",
             "class" => "mt-1 font-mono text-[0.65rem] text-base-content/60"
           }

    assert presentation["comparison"]["attrs"]["data-widget-compare-state"] == "increased"
    assert presentation["comparison"]["attrs"]["data-widget-compare-delta"] == "+2.25"
    assert presentation["comparison"]["attrs"]["data-widget-compare-value"] == "40.00"

    assert presentation["comparison"]["attrs"]["data-widget-compare-data-view"] ==
             "all_revisions"

    assert presentation["comparison"]["text"] == "All revisions compare +2.25"
  end

  test "value_tile falls back to raw sample value when engineering value is nil" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: widget(:value_tile),
        placement_id: "placement-1",
        data: point_data("ON", engineering_value: nil, raw_value: "ON"),
        compare_data: nil,
        point: %{unit: ""},
        compare_data_view: nil
      )

    {_vue, presentation} = point_presentation(html, "widget-point-placement-1-component")

    assert presentation["value"]["text"] == "ON"
  end

  test "value_tile omits comparison delta for non-numeric comparison data" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: widget(:value_tile),
        placement_id: "placement-1",
        data: point_data(42),
        compare_data: point_data("nominal"),
        point: %{unit: "V"},
        compare_data_view: "canonical"
      )

    {_vue, presentation} = point_presentation(html, "widget-point-placement-1-component")

    assert presentation["comparison"] == nil
  end

  test "value_tile honors the catalog show-unit option" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: put_in(widget(:value_tile), [:options, :show_unit], false),
        placement_id: "placement-1",
        data: point_data(42),
        compare_data: nil,
        point: %{unit: "V"},
        compare_data_view: nil
      )

    {_vue, presentation} = point_presentation(html, "widget-point-placement-1-component")

    assert presentation["value"]["unit"] == nil
  end

  test "time_series_chart exposes a JSON-safe LiveVue chart contract" do
    html =
      render_component(&WidgetPointComponents.time_series_chart/1,
        widget: widget(:time_series),
        placement_id: "placement-1",
        data: point_data(42),
        compare_data: point_data(40),
        point: %{unit: "V"},
        backfill: backfill("primary", 42),
        compare_backfill: backfill("compare", 40),
        limit_markers: [%{state: "red"}],
        event_markers: [%{title: "Limit crossed"}],
        selected_data_ref: %{kind: "sample", id: "sample-1"},
        time_mode: "replay_run",
        time_from: "2026-06-25T11:55:00Z",
        time_to: "2026-06-25T12:00:00Z",
        time_axis: "receipt_time",
        replay_run_id: "replay-run-1",
        data_realm: "rehearsal",
        data_view: "all_revisions",
        compare_data_view: "canonical",
        data_source_id: "questdb-rehearsal",
        source_binding_id: "binding-rehearsal",
        context_spacecraft_id: "spacecraft-1",
        chart_epoch: 7
      )

    {vue, presentation} =
      point_presentation(html, "widget-point-tlm-chart-widget-1-spacecraft-1-7-component")

    chart_props = presentation["chart"]["props"]

    assert vue.class == "contents"
    assert presentation["kind"] == "time_series"

    assert presentation["stage"] == %{
             "class" => "cadence-time-series-stage relative flex min-h-0 flex-1",
             "attrs" => %{"data-dashboard-time-series-stage" => ""}
           }

    assert presentation["chart"]["class"] == "min-h-0 flex-1 overflow-hidden"

    assert presentation["chart"]["component_id"] ==
             "tlm-chart-widget-1-spacecraft-1-7-component"

    assert chart_props["chart_id"] == "tlm-chart-widget-1-spacecraft-1-7"
    assert chart_props["widget_id"] == "widget-1"
    assert chart_props["placement_id"] == "placement-1"
    assert chart_props["unit"] == "V"
    assert chart_props["time_mode"] == "replay_run"
    assert chart_props["time_from"] == "2026-06-25T11:55:00Z"
    assert chart_props["time_to"] == "2026-06-25T12:00:00Z"
    assert chart_props["time_axis"] == "receipt_time"
    assert chart_props["replay_run_id"] == "replay-run-1"
    assert chart_props["data_realm"] == "rehearsal"
    assert chart_props["data_view"] == "all_revisions"
    assert chart_props["compare_data_view"] == "canonical"
    assert chart_props["data_source_id"] == "questdb-rehearsal"
    assert chart_props["source_binding_id"] == "binding-rehearsal"
    assert chart_props["correlation_group"] == "cadence-dashboard-time"
    assert chart_props["edit_mode"] == false
    assert chart_props["legend_mode"] == "auto"
    assert chart_props["fill_opacity"] == 8
    assert chart_props["show_min_max_band"] == true
    assert chart_props["line_width"] == "normal"
    assert chart_props["span_gaps"] == false
    assert chart_props["show_points"] == false
    assert chart_props["axis_mode"] == "unit"
    assert chart_props["shared_tooltip"] == true
    assert chart_props["data_management_badges"] == "all_revisions,corrected"
    assert chart_props["limit_markers"] == [%{"state" => "red"}]
    assert chart_props["event_markers"] == [%{"title" => "Limit crossed"}]
    assert chart_props["annotations"] == []

    assert chart_props["compare_data_management_badges"] == "recomputed,backfill"

    assert %{"series" => [%{"id" => "primary", "points" => [[_, 42, _]]}]} =
             chart_props["backfill"]

    assert %{
             "series" => [
               %{
                 "id" => "compare",
                 "points" => [
                   [
                     _,
                     40,
                     %{
                       "sample_id" => "compare-sample"
                     }
                   ]
                 ]
               }
             ]
           } = chart_props["compare_backfill"]

    assert %{"kind" => "sample", "id" => "sample-1"} = chart_props["selected_ref"]

    strip = presentation["data_management"]

    assert strip["component_id"] == "chart-data-management-placement-1-component"

    comparison_attrs = strip["presentation"]["comparison"]["attrs"]

    assert comparison_attrs["data-primary-data-view"] == "all_revisions"
    assert comparison_attrs["data-compare-data-view"] == "canonical"
  end

  test "constellation_health renders counts and per-spacecraft state dots" do
    html =
      render_component(&WidgetPointComponents.constellation_health/1,
        placement_id: "placement-1",
        data: %{
          counts: %{red: 1, yellow: 2, blue: 0, green: 3, no_data: 1},
          spacecraft: [
            %{spacecraft_id: "spacecraft-1", worst_state: :red},
            %{spacecraft_id: "spacecraft-2", worst_state: :green},
            %{spacecraft_id: "spacecraft-3", worst_state: nil}
          ]
        }
      )

    {_vue, presentation} = point_presentation(html, "widget-point-placement-1-component")

    assert Enum.map(presentation["badges"]["items"], & &1["label"]) == [
             "Red",
             "Yellow",
             "Blue",
             "Green",
             "No Data"
           ]

    assert Enum.map(presentation["badges"]["items"], & &1["count"]) == [1, 2, 0, 3, 1]
    assert presentation["badges"]["class"] == "flex flex-wrap gap-2"

    assert Enum.map(presentation["badges"]["items"], & &1["class"]) == [
             "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium bg-error/20 text-error",
             "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium bg-warning/20 text-warning",
             "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium bg-info/20 text-info",
             "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium bg-success/20 text-success",
             "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium bg-info/20 text-info"
           ]

    assert presentation["spacecraft"]["class"] == "mt-2 flex flex-wrap gap-1"

    assert presentation["spacecraft"]["attrs"] == %{
             "aria-label" => "Per-spacecraft worst limit state"
           }

    assert Enum.map(presentation["spacecraft"]["items"], & &1["attrs"]["title"]) == [
             "spacecraft-1: Red",
             "spacecraft-2: Green",
             "spacecraft-3: No data"
           ]

    assert Enum.map(presentation["spacecraft"]["items"], & &1["class"]) == [
             "inline-block h-3 w-3 rounded-sm bg-error",
             "inline-block h-3 w-3 rounded-sm bg-success",
             "inline-block h-3 w-3 rounded-sm bg-base-300"
           ]
  end

  test "chart_payload_empty? treats missing and empty series as empty" do
    assert WidgetPointComponents.chart_payload_empty?(nil)
    assert WidgetPointComponents.chart_payload_empty?([])
    assert WidgetPointComponents.chart_payload_empty?(%{series: [%{points: []}]})
    refute WidgetPointComponents.chart_payload_empty?(%{series: [%{points: [[1, 2, %{}]]}]})
  end

  defp widget(type) do
    %{
      widget_id: "widget-1",
      type: type,
      title: "Voltage",
      options: %{precision: 2, window_seconds: 300}
    }
  end

  defp point_presentation(html, component_id) do
    vue = LiveVue.Test.get_vue(html, id: component_id)

    assert vue.component == "WidgetPoint"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert vue.props["presentation"]["component_id"] == component_id

    {vue, vue.props["presentation"]}
  end

  defp point_data(value, opts \\ []) do
    raw_value = Keyword.get(opts, :raw_value, value)
    engineering_value = Keyword.get(opts, :engineering_value, value)

    %{
      kind: :point,
      sample: %{
        raw_value: raw_value,
        engineering_value: engineering_value,
        receipt_time: ~U[2026-06-17 12:00:00Z],
        quality_state: :good
      },
      data_management: nil,
      engine_backed?: true
    }
  end

  defp backfill(series_id, value) do
    %{
      data_management: backfill_data_management(series_id),
      series: [
        %{
          id: series_id,
          label: series_id,
          unit: "V",
          data_management: backfill_data_management(series_id),
          points: [[1_781_568_000_000, value, %{sample_id: "#{series_id}-sample"}]]
        }
      ]
    }
  end

  defp backfill_data_management("primary") do
    %{
      badges: [
        %{
          kind: :data_view,
          value: "all_revisions",
          label: "All revisions",
          status: :attention,
          code: nil
        },
        %{
          kind: :revision_state,
          value: "corrected",
          label: "Corrected",
          status: :warning,
          code: nil
        }
      ]
    }
  end

  defp backfill_data_management("compare") do
    %{
      badges: [
        %{
          kind: :data_view,
          value: "recomputed",
          label: "Recomputed",
          status: :attention,
          code: nil
        },
        %{
          kind: :revision_state,
          value: "backfill",
          label: "Backfill",
          status: :warning,
          code: nil
        }
      ]
    }
  end
end
