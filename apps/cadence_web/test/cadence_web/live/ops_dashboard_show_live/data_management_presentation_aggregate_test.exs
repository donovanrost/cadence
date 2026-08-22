defmodule CadenceWeb.OpsDashboardShowLive.DataManagementPresentationAggregateTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.DataManagementPresentation

  test "placement returns the first frame summary and aggregate rows deduplicates badges" do
    first = %Frame{meta: %{}}
    second = %Frame{meta: %{data_view: :all_revisions, warning_codes: [:late_arrival]}}
    placement = %PlacementFrames{primary: [first, second]}

    summary = DataManagementPresentation.placement(placement)

    assert %{data_view: "all_revisions", warning_codes: ["late_arrival"]} = summary

    assert %{
             data_views: ["all_revisions"],
             warning_codes: ["late_arrival"],
             badges: badges
           } =
             DataManagementPresentation.aggregate_rows([
               %{data_management: summary},
               %{data_management: summary}
             ])

    assert [%{kind: :data_view, value: "all_revisions"}, %{kind: :revision_state, value: "late"}] =
             badges
  end

  test "returns nil when no data-management context is present" do
    assert DataManagementPresentation.frame(%Frame{meta: %{}}) == nil

    assert DataManagementPresentation.placement(%PlacementFrames{primary: [%Frame{meta: %{}}]}) ==
             nil

    assert DataManagementPresentation.aggregate_rows([%{data_management: nil}]) == nil
  end
end
