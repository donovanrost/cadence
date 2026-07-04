defmodule CadenceWeb.OpsDashboardShowLive.RuntimeResultTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DashboardResolveResult, PlacementFrames, PlannedSourceRequest}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeResult

  test "reads result fields from dashboard engine structs" do
    placement_frames = %PlacementFrames{}

    result = %DashboardResolveResult{
      resolve_mode: :live_tick,
      frames_by_placement: %{"placement-1" => placement_frames},
      dashboard_warnings: [%{code: :source_degraded}],
      planned_source_requests: [%PlannedSourceRequest{request_id: "request-1"}],
      plan_metadata: %{
        source_request_count: 1,
        snapshot?: true,
        time: %{mode: :live},
        cache: %{plan_cache: %{status: :hit}}
      }
    }

    assert RuntimeResult.resolve_mode(result) == :live_tick
    assert RuntimeResult.resolve_mode_text(result) == "live_tick"
    assert RuntimeResult.live_tick?(result)
    assert RuntimeResult.frames_by_placement(result) == %{"placement-1" => placement_frames}
    assert RuntimeResult.placement_frames(result, "placement-1") == placement_frames
    assert RuntimeResult.dashboard_warnings(result) == [%{code: :source_degraded}]
    assert RuntimeResult.metadata(result, :source_request_count) == 1
    assert RuntimeResult.boolean_metadata?(result, :snapshot?)
    assert RuntimeResult.metadata_path(result, [:time, :mode]) == :live
    assert RuntimeResult.metadata_path(result, [:cache, :plan_cache, :status]) == :hit

    assert [%PlannedSourceRequest{request_id: "request-1"}] =
             RuntimeResult.planned_source_requests(result)
  end

  test "reads result fields from map-backed results" do
    result = %{
      "resolve_mode" => "context_change",
      "frames_by_placement" => %{"placement-1" => :frames},
      "dashboard_warnings" => [:warning],
      "planned_source_requests" => [%{request_id: "request-1"}],
      "plan_metadata" => %{
        "source_request_count" => 2,
        "snapshot?" => true,
        "cache" => %{"plan_cache" => %{"status" => "miss"}}
      }
    }

    assert RuntimeResult.resolve_mode(result) == "context_change"
    assert RuntimeResult.resolve_mode_text(result) == "context_change"
    assert RuntimeResult.frames_by_placement(result) == %{"placement-1" => :frames}
    assert RuntimeResult.dashboard_warnings(result) == [:warning]
    assert RuntimeResult.metadata(result, :source_request_count) == 2
    assert RuntimeResult.boolean_metadata?(result, :snapshot?)
    assert RuntimeResult.metadata_path(result, [:cache, :plan_cache, :status]) == "miss"
    assert RuntimeResult.planned_source_requests(result) == [%{request_id: "request-1"}]
  end

  test "returns safe empty values for nil and invalid results" do
    assert RuntimeResult.resolve_mode(nil) == nil
    assert RuntimeResult.resolve_mode_text(nil) == nil
    assert RuntimeResult.frames_by_placement(nil) == %{}
    assert RuntimeResult.placement_frames(nil, "placement-1") == nil
    assert RuntimeResult.plan_metadata(nil) == %{}
    assert RuntimeResult.metadata(nil, :source_request_count) == nil
    refute RuntimeResult.boolean_metadata?(nil, :snapshot?)
    assert RuntimeResult.planned_source_requests(nil) == []
    assert RuntimeResult.dashboard_warnings(nil) == []

    assert RuntimeResult.frames_by_placement(%{frames_by_placement: :invalid}) == %{}
    assert RuntimeResult.plan_metadata(%{plan_metadata: :invalid}) == %{}
    assert RuntimeResult.planned_source_requests(%{planned_source_requests: :invalid}) == []
  end
end
