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

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-comparison-inspector-component"
      )

    presentation = vue.props["presentation"]

    assert presentation["inspector"]["root"]["attrs"]["aria-label"] ==
             "Dashboard comparison inspector"

    assert presentation["inspector"]["header"]["close"]["attrs"]["phx-click"] ==
             "close_comparison_inspector"

    assert presentation["rollup"]["root"]["attrs"]["data-dashboard-comparison-open"] ==
             "1"

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#ops-context-rail")
             |> LazyHTML.attribute("id")
  end

  test "renders the exact comparison inspector header LiveVue boundary" do
    html =
      render_component(&ComparisonInspectorComponents.comparison_inspector/1,
        open?: true,
        rollup: rollup()
      )

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-comparison-inspector-component"
      )

    assert vue.component == "DashboardComparisonInspector"
    assert vue.id == "dashboard-comparison-inspector-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props["presentation"]["inspector"]["header"] == %{
             "root" => %{
               "tag" => "header",
               "class" =>
                 "flex min-h-12 items-center gap-2 border-b border-base-300/60 px-3 py-2",
               "attrs" => %{}
             },
             "leading" => %{
               "tag" => "div",
               "class" =>
                 "flex h-7 w-7 shrink-0 items-center justify-center rounded border border-info/35 bg-info/10 text-info",
               "attrs" => %{},
               "icon" => %{
                 "name" => "hero-scale",
                 "class" => "h-4 w-4",
                 "text" => ""
               }
             },
             "copy" => %{
               "tag" => "div",
               "class" => "min-w-0 flex-1",
               "attrs" => %{},
               "title" => %{
                 "tag" => "p",
                 "class" => "hud-label text-info",
                 "attrs" => %{},
                 "text" => "Dashboard compare"
               },
               "subtitle" => %{
                 "tag" => "p",
                 "class" => "truncate text-[0.65rem] text-base-content/50",
                 "attrs" => %{},
                 "text" => "Page-local revision evidence"
               }
             },
             "close" => %{
               "tag" => "button",
               "class" => "btn btn-ghost btn-xs btn-square",
               "attrs" => %{
                 "id" => "dashboard-comparison-inspector-close",
                 "type" => "button",
                 "phx-click" => "close_comparison_inspector",
                 "aria-label" => "Close dashboard comparison inspector"
               },
               "icon" => %{
                 "name" => "hero-x-mark",
                 "class" => "h-4 w-4",
                 "text" => ""
               }
             }
           }
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

    closed_with_saved =
      render_component(&ComparisonInspectorComponents.comparison_inspector/1,
        open?: false,
        rollup: empty_rollup(),
        saved_presets: [%{dashboard_investigation_preset_id: "preset-1"}]
      )

    for html <- [closed, unavailable, closed_with_saved] do
      assert [] =
               html
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#dashboard-comparison-inspector-component")
               |> LazyHTML.attribute("id")
    end

    saved_only =
      render_component(&ComparisonInspectorComponents.comparison_inspector/1,
        open?: true,
        rollup: empty_rollup(),
        saved_presets: [%{dashboard_investigation_preset_id: "preset-1"}]
      )

    vue = LiveVue.Test.get_vue(saved_only, id: "dashboard-comparison-inspector-component")

    assert vue.props["presentation"]["inspector"]["root"]["attrs"]["id"] ==
             "dashboard-comparison-inspector"

    assert vue.props["presentation"]["rollup"]["root"]["attrs"][
             "data-dashboard-comparison-saved-presets"
           ] == "1"
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
