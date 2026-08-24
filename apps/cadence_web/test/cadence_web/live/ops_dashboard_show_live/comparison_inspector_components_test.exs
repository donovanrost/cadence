defmodule CadenceWeb.OpsDashboardShowLive.ComparisonInspectorComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.ComparisonInspectorComponents
  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents

  test "presents Compare as a page-local dock through the actual LiveVue host" do
    {html, vue} = render_inspector_host(rollup())

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

  test "preserves the exact comparison inspector header LiveVue boundary" do
    {_html, vue} = render_inspector_host(rollup())

    assert vue.component == "DashboardComparisonInspector"
    assert vue.id == "dashboard-comparison-inspector-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    expected_presentation =
      ComparisonInspectorComponents.presentation(true, rollup(), nil, %{}, [])
      |> Jason.encode!()
      |> Jason.decode!()

    assert vue.props["presentation"] == expected_presentation

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

  test "presentation closes cleanly and saved-only context still reaches the LiveVue host" do
    assert ComparisonInspectorComponents.presentation(false, rollup(), nil, %{}, []) == nil

    assert ComparisonInspectorComponents.presentation(true, empty_rollup(), nil, %{}, []) == nil

    assert ComparisonInspectorComponents.presentation(
             false,
             empty_rollup(),
             nil,
             %{},
             [%{dashboard_investigation_preset_id: "preset-1"}]
           ) == nil

    {_html, vue} =
      render_inspector_host(empty_rollup(), [
        %{dashboard_investigation_preset_id: "preset-1"}
      ])

    assert vue.props["presentation"]["inspector"]["root"]["attrs"]["id"] ==
             "dashboard-comparison-inspector"

    assert vue.props["presentation"]["rollup"]["root"]["attrs"][
             "data-dashboard-comparison-saved-presets"
           ] == "1"
  end

  test "retired comparison_inspector/1 render API is absent" do
    refute function_exported?(ComparisonInspectorComponents, :comparison_inspector, 1)
  end

  defp render_inspector_host(rollup, saved_presets \\ []) do
    presentation =
      ComparisonInspectorComponents.presentation(true, rollup, nil, %{}, saved_presets)

    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        inspector: presentation.inspector,
        rollup: rollup,
        saved_presets: saved_presets
      )

    {html, LiveVue.Test.get_vue(html, id: "dashboard-comparison-inspector-component")}
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
