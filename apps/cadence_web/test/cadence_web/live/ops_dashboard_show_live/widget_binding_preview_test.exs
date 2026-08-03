defmodule CadenceWeb.OpsDashboardShowLive.WidgetBindingPreviewTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    Field,
    Frame,
    PlacementFrames,
    PlannedSourceRequest,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.WidgetBindingPreview

  test "classifies a binding with primary values as ready" do
    result = %DashboardResolveResult{
      planned_source_requests: [planned_request()],
      frames_by_placement: %{
        "placement-1" => %PlacementFrames{
          primary: [%Frame{fields: [%Field{name: "value", kind: :number, values: [42]}]}]
        }
      }
    }

    assert %{status: :ready, planned_request_count: 1, frame_count: 1} =
             WidgetBindingPreview.summarize(result, "placement-1")
  end

  test "distinguishes a valid empty request from an unplannable binding" do
    empty = %DashboardResolveResult{
      planned_source_requests: [planned_request()],
      frames_by_placement: %{"placement-1" => %PlacementFrames{primary: []}}
    }

    assert %{status: :no_data, planned_request_count: 1} =
             WidgetBindingPreview.summarize(empty, "placement-1")

    unsupported = %DashboardResolveResult{
      dashboard_warnings: [
        %ResolveWarning{severity: :error, message: "Source capability is unsupported."}
      ]
    }

    assert %{status: :error, message: "Source capability is unsupported."} =
             WidgetBindingPreview.summarize(unsupported, "placement-1")
  end

  defp planned_request do
    %PlannedSourceRequest{
      request_id: "request-1",
      logical_source: :telemetry,
      consumers: [
        %{placement_id: "placement-1", role: :primary, widget_type_id: "cadence.value_tile"}
      ]
    }
  end
end
