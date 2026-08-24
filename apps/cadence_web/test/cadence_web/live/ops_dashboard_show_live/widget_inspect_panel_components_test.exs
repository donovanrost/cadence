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
    vue = LiveVue.Test.get_vue(html, id: "dashboard-widget-inspector-component")
    presentation = vue.props["presentation"]

    assert ["ready"] =
             presentation["root"]["attrs"]
             |> attribute("data-widget-inspect-state")

    assert ["1"] =
             presentation["header"]["series_badge"]["attrs"]
             |> attribute("data-widget-inspect-series-count")

    assert ["2"] =
             presentation["header"]["rows_badge"]["attrs"]
             |> attribute("data-widget-inspect-row-total")

    stats =
      Enum.find(
        presentation["stats"]["rows"],
        &(&1["attrs"]["data-widget-inspect-stat"] == "volts")
      )

    assert stats["label"]["text"] =~ "volts"
    assert Enum.any?(stats["values"], &(&1["value"]["text"] == "1.5"))

    table = table_text(presentation["table"])
    assert table =~ "2023-11-14T22:13:20.000Z"
    assert table =~ "volts (V)"

    download = presentation["download"]

    assert download["component"] == "CsvDownloadButton"
    assert download["props"]["csv"] =~ "time_utc,volts (V)"
    assert download["props"]["filename"] == "bus-voltage-inspect.csv"
    refute download["props"]["disabled"]
    refute vue.ssr
  end

  test "disables the download component when there are no rows" do
    html = render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: model(0))

    download = inspect_presentation(html)["download"]

    assert download["props"]["disabled"]
  end

  test "shows the cap notice when rows exceed the display limit" do
    presentation =
      render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: model(600))
      |> inspect_presentation()

    assert presentation["header"]["capped"]["text"] =~
             "Showing latest 500 of 600 rows"
  end

  test "renders a fallback when the widget is gone" do
    presentation =
      render_component(&WidgetInspectPanelComponents.inspect_panel/1, inspect: nil)
      |> inspect_presentation()

    assert ["missing"] =
             presentation["root"]["attrs"]
             |> attribute("data-widget-inspect-state")

    assert presentation["missing"]["text"] =~
             "no longer on the dashboard"
  end

  defp inspect_presentation(html) do
    html
    |> LiveVue.Test.get_vue(id: "dashboard-widget-inspector-component")
    |> then(& &1.props["presentation"])
  end

  defp attribute(attrs, name) do
    case Map.fetch(attrs, name) do
      {:ok, value} -> [to_string(value)]
      :error -> []
    end
  end

  defp table_text(table) do
    headers =
      table["series_headers"]
      |> Enum.map_join(" ", &(&1["text"] <> (&1["unit"] || "")))

    rows =
      table["rows"]
      |> Enum.map_join(" ", fn row ->
        values = Enum.map_join(row["values"], " ", & &1["text"])
        row["timestamp"]["text"] <> " " <> values
      end)

    headers <> " " <> rows
  end
end
