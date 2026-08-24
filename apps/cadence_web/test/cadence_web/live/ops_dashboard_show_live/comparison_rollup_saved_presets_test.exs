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

    vue = LiveVue.Test.get_vue(html, id: "dashboard-comparison-rollup-component")
    rollup = vue.props["presentation"]["rollup"]
    saved = rollup["saved_presets"]
    [preset] = saved["body"]["items"]

    assert rollup["root"]["attrs"]["data-dashboard-comparison-saved-presets"] == "1"
    assert saved["root"]["attrs"]["data-dashboard-comparison-saved-presets"] == "1"
    assert preset["root"]["attrs"]["data-dashboard-comparison-saved-preset"] == "preset-1"

    assert preset["root"]["attrs"]["data-dashboard-comparison-saved-preset-name"] ==
             "All revisions vs canonical"

    assert preset["root"]["attrs"]["data-dashboard-comparison-saved-preset-primary-view"] ==
             "all_revisions"

    assert preset["root"]["attrs"]["data-dashboard-comparison-saved-preset-compare-view"] ==
             "canonical"

    assert preset["root"]["attrs"]["data-dashboard-comparison-saved-preset-affected"] == "2"

    assert preset["actions"]["apply"]["attrs"]["phx-click"] == "apply_comparison_preset"
    assert preset["actions"]["apply"]["attrs"]["phx-value-preset-id"] == "preset-1"
    assert preset["actions"]["delete"]["attrs"]["phx-click"] == "delete_comparison_preset"
    assert preset["actions"]["delete"]["attrs"]["phx-value-preset-id"] == "preset-1"

    assert preset["actions"]["delete"]["attrs"]["data-confirm"] ==
             "Delete this comparison preset?"

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
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
