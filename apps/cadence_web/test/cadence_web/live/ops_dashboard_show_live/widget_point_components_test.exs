defmodule CadenceWeb.OpsDashboardShowLive.WidgetPointComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetPointComponents

  test "value_tile renders displayed sample value, unit, and comparison delta" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: widget(:value_tile),
        data: point_data(42.25),
        compare_data: point_data(40.0),
        point: %{unit: "V"},
        compare_data_view: "all_revisions"
      )

    document = LazyHTML.from_fragment(html)

    assert "42.25" =
             document
             |> LazyHTML.query("[data-widget-value]")
             |> LazyHTML.text()
             |> String.trim()

    assert html =~ "V"

    assert ["increased"] =
             document
             |> LazyHTML.query("[data-widget-compare-delta]")
             |> LazyHTML.attribute("data-widget-compare-state")

    assert ["+2.25"] =
             document
             |> LazyHTML.query("[data-widget-compare-delta]")
             |> LazyHTML.attribute("data-widget-compare-delta")

    assert html =~ "All revisions compare +2.25"
  end

  test "value_tile falls back to raw sample value when engineering value is nil" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: widget(:value_tile),
        data: point_data("ON", engineering_value: nil, raw_value: "ON"),
        compare_data: nil,
        point: %{unit: ""},
        compare_data_view: nil
      )

    assert "ON" =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-widget-value]")
             |> LazyHTML.text()
             |> String.trim()
  end

  test "value_tile omits comparison delta for non-numeric comparison data" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: widget(:value_tile),
        data: point_data(42),
        compare_data: point_data("nominal"),
        point: %{unit: "V"},
        compare_data_view: "canonical"
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-widget-compare-delta]")
             |> LazyHTML.attribute("data-widget-compare-delta")
  end

  test "value_tile honors the catalog show-unit option" do
    html =
      render_component(&WidgetPointComponents.value_tile/1,
        widget: put_in(widget(:value_tile), [:options, :show_unit], false),
        data: point_data(42),
        compare_data: nil,
        point: %{unit: "V"},
        compare_data_view: nil
      )

    refute html =~ ">V<"
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

    document = LazyHTML.from_fragment(html)
    vue = LiveVue.Test.get_vue(html, id: "tlm-chart-widget-1-spacecraft-1-7-component")

    strip_vue =
      LiveVue.Test.get_vue(html, id: "chart-data-management-placement-1-component")

    assert vue.component == "TelemetryChart"
    assert vue.ssr == false
    assert vue.class == "min-h-0 flex-1 overflow-hidden"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props["chart_id"] == "tlm-chart-widget-1-spacecraft-1-7"
    assert vue.props["widget_id"] == "widget-1"
    assert vue.props["placement_id"] == "placement-1"
    assert vue.props["unit"] == "V"
    assert vue.props["time_mode"] == "replay_run"
    assert vue.props["time_from"] == "2026-06-25T11:55:00Z"
    assert vue.props["time_to"] == "2026-06-25T12:00:00Z"
    assert vue.props["time_axis"] == "receipt_time"
    assert vue.props["replay_run_id"] == "replay-run-1"
    assert vue.props["data_realm"] == "rehearsal"
    assert vue.props["data_view"] == "all_revisions"
    assert vue.props["compare_data_view"] == "canonical"
    assert vue.props["data_source_id"] == "questdb-rehearsal"
    assert vue.props["source_binding_id"] == "binding-rehearsal"
    assert vue.props["correlation_group"] == "cadence-dashboard-time"
    assert vue.props["edit_mode"] == false
    assert vue.props["legend_mode"] == "auto"
    assert vue.props["fill_opacity"] == 8
    assert vue.props["data_management_badges"] == "all_revisions,corrected"

    assert [""] =
             document
             |> LazyHTML.query("[data-dashboard-time-series-stage]")
             |> LazyHTML.attribute("data-dashboard-time-series-stage")

    assert vue.props["compare_data_management_badges"] == "recomputed,backfill"

    assert %{"series" => [%{"id" => "primary", "points" => [[_, 42, _]]}]} =
             vue.props["backfill"]

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
           } = vue.props["compare_backfill"]

    assert %{"kind" => "sample", "id" => "sample-1"} = vue.props["selected_ref"]

    assert strip_vue.component == "ChartDataManagementStrip"
    assert strip_vue.id == "chart-data-management-placement-1-component"
    assert strip_vue.class == "contents"
    refute strip_vue.ssr
    assert strip_vue.handlers == %{}
    assert strip_vue.props == Jason.decode!(Jason.encode!(strip_vue.props))

    comparison_attrs = strip_vue.props["presentation"]["comparison"]["attrs"]

    assert comparison_attrs["data-primary-data-view"] == "all_revisions"
    assert comparison_attrs["data-compare-data-view"] == "canonical"
  end

  test "constellation_health renders counts and per-spacecraft state dots" do
    html =
      render_component(&WidgetPointComponents.constellation_health/1,
        data: %{
          counts: %{red: 1, yellow: 2, blue: 0, green: 3, no_data: 1},
          spacecraft: [
            %{spacecraft_id: "spacecraft-1", worst_state: :red},
            %{spacecraft_id: "spacecraft-2", worst_state: :green},
            %{spacecraft_id: "spacecraft-3", worst_state: nil}
          ]
        }
      )

    document = LazyHTML.from_fragment(html)

    assert html =~ "Red"
    assert html =~ "No Data"

    assert ["spacecraft-1: Red"] =
             document
             |> LazyHTML.query(~s([title="spacecraft-1: Red"]))
             |> LazyHTML.attribute("title")

    assert ["spacecraft-2: Green"] =
             document
             |> LazyHTML.query(~s([title="spacecraft-2: Green"]))
             |> LazyHTML.attribute("title")
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
