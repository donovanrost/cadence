defmodule CadenceWeb.OpsDashboardShowLive.WidgetInspectPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectModel
  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectPanelComponents

  @t0 1_700_000_000_000

  defp model(points_count \\ 2) do
    points = for offset <- 0..(points_count - 1), do: [@t0 + offset * 1_000, offset * 1.5]

    WidgetInspectModel.from_series("placement-1", "Bus Voltage", [
      %{id: "volts", label: "volts", unit: "V", points: points}
    ])
  end

  test "renders header badges, stats, table rows, and the download payload" do
    document =
      LazyHTML.from_fragment(
        render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: model())
      )

    assert ["ready"] =
             document
             |> LazyHTML.query("#dashboard-widget-inspector")
             |> LazyHTML.attribute("data-widget-inspect-state")

    assert ["1"] =
             document
             |> LazyHTML.query("[data-widget-inspect-series-count]")
             |> LazyHTML.attribute("data-widget-inspect-series-count")

    assert ["2"] =
             document
             |> LazyHTML.query("[data-widget-inspect-row-total]")
             |> LazyHTML.attribute("data-widget-inspect-row-total")

    stats = document |> LazyHTML.query(~s([data-widget-inspect-stat="volts"])) |> LazyHTML.text()
    assert stats =~ "volts"
    assert stats =~ "1.5"

    table = document |> LazyHTML.query("[data-widget-inspect-table]") |> LazyHTML.text()
    assert table =~ "2023-11-14T22:13:20.000Z"
    assert table =~ "volts (V)"

    assert [csv] =
             document
             |> LazyHTML.query("#dashboard-widget-inspect-download")
             |> LazyHTML.attribute("data-csv")

    assert csv =~ "time_utc,volts (V)"

    assert ["bus-voltage-inspect.csv"] =
             document
             |> LazyHTML.query("#dashboard-widget-inspect-download")
             |> LazyHTML.attribute("data-filename")
  end

  test "shows the cap notice when rows exceed the display limit" do
    document =
      LazyHTML.from_fragment(
        render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: model(600))
      )

    assert document |> LazyHTML.query("#dashboard-widget-inspect-capped") |> LazyHTML.text() =~
             "Showing latest 500 of 600 rows"
  end

  test "renders a fallback when the widget is gone" do
    document =
      LazyHTML.from_fragment(
        render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: nil)
      )

    assert ["missing"] =
             document
             |> LazyHTML.query("#dashboard-widget-inspector")
             |> LazyHTML.attribute("data-widget-inspect-state")

    assert document |> LazyHTML.query("#dashboard-widget-inspector") |> LazyHTML.text() =~
             "no longer on the dashboard"
  end
end
