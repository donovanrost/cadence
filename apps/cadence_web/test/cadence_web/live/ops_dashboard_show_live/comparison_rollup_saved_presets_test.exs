defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupSavedPresetsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.InvestigationPreset
  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents

  test "comparison rollup strip exposes saved preset metadata and controls" do
    html =
      render_component(&ComparisonRollupComponents.comparison_rollup_strip/1,
        rollup: inactive_rollup(),
        saved_presets: [saved_preset()]
      )

    document = LazyHTML.from_fragment(html)

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-rollup")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-presets")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-comparison-saved-presets")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-presets")

    assert ["preset-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset]")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-preset")

    assert ["All revisions vs canonical"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset]")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-preset-name")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset]")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-preset-primary-view")

    assert ["canonical"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset]")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-preset-compare-view")

    assert ["2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset]")
             |> LazyHTML.attribute("data-dashboard-comparison-saved-preset-affected")

    assert ["apply_comparison_preset"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-apply]")
             |> LazyHTML.attribute("phx-click")

    assert ["preset-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-apply]")
             |> LazyHTML.attribute("phx-value-preset-id")

    assert ["delete_comparison_preset"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-delete]")
             |> LazyHTML.attribute("phx-click")

    assert ["preset-1"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-delete]")
             |> LazyHTML.attribute("phx-value-preset-id")

    assert ["Delete this comparison preset?"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-saved-preset-delete]")
             |> LazyHTML.attribute("data-confirm")
  end

  defp inactive_rollup do
    %{
      visible?: false,
      widget_count: 0,
      delta_count: 0,
      unchanged_count: 0,
      coverage_count: 0,
      missing_count: 0,
      states: ""
    }
  end

  defp saved_preset do
    InvestigationPreset.new(%{
      dashboard_investigation_preset_id: "preset-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      name: "All revisions vs canonical",
      schema: "dashboard_comparison_investigation_preset.v1",
      preset_kind: :comparison,
      runtime_query: %{
        "data_view" => "all_revisions",
        "compare_data_view" => "canonical"
      },
      primary_data_view: "all_revisions",
      compare_data_view: "canonical",
      affected_placement_ids: ["placement-1", "placement-2"]
    })
  end
end
