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

  test "time_series_chart exposes chart hook payload and data-management attrs" do
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
    chart = LazyHTML.query(document, ~s([phx-hook="TelemetryChart"]))

    assert ["tlm-chart-widget-1-spacecraft-1-7"] = LazyHTML.attribute(chart, "id")
    assert ["placement-1"] = LazyHTML.attribute(chart, "data-placement-id")
    assert ["V"] = LazyHTML.attribute(chart, "data-unit")
    assert ["replay_run"] = LazyHTML.attribute(chart, "data-time-mode")
    assert ["receipt_time"] = LazyHTML.attribute(chart, "data-time-axis")
    assert ["replay-run-1"] = LazyHTML.attribute(chart, "data-replay-run-id")
    assert ["rehearsal"] = LazyHTML.attribute(chart, "data-data-realm")
    assert ["all_revisions"] = LazyHTML.attribute(chart, "data-data-view")
    assert ["canonical"] = LazyHTML.attribute(chart, "data-compare-data-view")
    assert ["questdb-rehearsal"] = LazyHTML.attribute(chart, "data-data-source-id")
    assert ["binding-rehearsal"] = LazyHTML.attribute(chart, "data-source-binding-id")
    assert ["cadence-dashboard-time"] = LazyHTML.attribute(chart, "data-correlation-group")
    assert ["false"] = LazyHTML.attribute(chart, "data-edit-mode")
    assert ["auto"] = LazyHTML.attribute(chart, "data-legend-mode")
    assert ["8"] = LazyHTML.attribute(chart, "data-fill-opacity")
    assert ["grafana"] = LazyHTML.attribute(chart, "data-panel-presentation")
    assert ["all_revisions,corrected"] = LazyHTML.attribute(chart, "data-data-management-badges")

    assert [""] =
             document
             |> LazyHTML.query("[data-dashboard-time-series-stage]")
             |> LazyHTML.attribute("data-dashboard-time-series-stage")

    assert ["recomputed,backfill"] =
             LazyHTML.attribute(chart, "data-compare-data-management-badges")

    [encoded_backfill] = LazyHTML.attribute(chart, "data-backfill")

    assert %{"series" => [%{"id" => "primary", "points" => [[_, 42, _]]}]} =
             Jason.decode!(encoded_backfill)

    [encoded_compare_backfill] = LazyHTML.attribute(chart, "data-compare-backfill")

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
           } = Jason.decode!(encoded_compare_backfill)

    [encoded_selected] = LazyHTML.attribute(chart, "data-selected-ref")
    assert %{"kind" => "sample", "id" => "sample-1"} = Jason.decode!(encoded_selected)

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("[data-chart-data-view-comparison]")
             |> LazyHTML.attribute("data-primary-data-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-chart-data-view-comparison]")
             |> LazyHTML.attribute("data-compare-data-view")
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
