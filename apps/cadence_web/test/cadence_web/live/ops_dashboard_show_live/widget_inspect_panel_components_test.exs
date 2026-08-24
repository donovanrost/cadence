defmodule CadenceWeb.OpsDashboardShowLive.WidgetInspectPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectModel
  alias CadenceWeb.OpsDashboardShowLive.WidgetInspectPanelComponents

  @t0 1_700_000_000_000

  defp model(points_count \\ 2) do
    points =
      if points_count == 0 do
        []
      else
        for offset <- 0..(points_count - 1), do: [@t0 + offset * 1_000, offset * 1.5]
      end

    WidgetInspectModel.from_series("placement-1", "Bus Voltage", [
      %{id: "volts", label: "volts", unit: "V", points: points}
    ])
  end

  test "renders header badges, stats, table rows, and the download payload" do
    html = render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: model())
    document = LazyHTML.from_fragment(html)

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

    download = LiveVue.Test.get_vue(html, id: "dashboard-widget-inspect-download-component")

    assert download.component == "CsvDownloadButton"
    assert download.props["csv"] =~ "time_utc,volts (V)"
    assert download.props["filename"] == "bus-voltage-inspect.csv"
    refute download.props["disabled"]
    refute download.ssr
  end

  test "disables the download component when there are no rows" do
    html = render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: model(0))

    download = LiveVue.Test.get_vue(html, id: "dashboard-widget-inspect-download-component")

    assert download.props["disabled"]
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
