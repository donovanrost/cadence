defmodule CadenceWeb.OpsDashboardShowLive.ComparisonInspectorComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.ComparisonInspectorComponents

  test "renders Compare as a page-local dock with an explicit close action" do
    html =
      render_component(&ComparisonInspectorComponents.comparison_inspector/1,
        open?: true,
        rollup: rollup()
      )

    document = LazyHTML.from_fragment(html)

    assert ["Dashboard comparison inspector"] =
             document
             |> LazyHTML.query("#dashboard-comparison-inspector")
             |> LazyHTML.attribute("aria-label")

    assert ["close_comparison_inspector"] =
             document
             |> LazyHTML.query("#dashboard-comparison-inspector-close")
             |> LazyHTML.attribute("phx-click")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-open")

    assert [] =
             document
             |> LazyHTML.query("#ops-context-rail")
             |> LazyHTML.attribute("id")
  end

  test "does not render when closed or no comparison context exists" do
    closed =
      render_component(&ComparisonInspectorComponents.comparison_inspector/1,
        open?: false,
        rollup: rollup()
      )

    unavailable =
      render_component(&ComparisonInspectorComponents.comparison_inspector/1,
        open?: true,
        rollup: empty_rollup()
      )

    for html <- [closed, unavailable] do
      assert [] =
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#dashboard-comparison-inspector")
               |> LazyHTML.attribute("id")
    end
  end

  defp rollup do
    empty_rollup()
    |> Map.merge(%{
      visible?: true,
      widget_count: 2,
      delta_count: 1,
      missing_count: 1,
      handled_count: 1,
      open_count: 1,
      unhandled_count: 1,
      states: "increased,missing",
      groups: [],
      workflow_groups: []
    })
  end

  defp empty_rollup do
    %{
      visible?: false,
      widget_count: 0,
      delta_count: 0,
      unchanged_count: 0,
      coverage_count: 0,
      missing_count: 0,
      handled_count: 0,
      open_count: 0,
      unhandled_count: 0,
      states: "",
      groups: [],
      workflow_groups: []
    }
  end
end
