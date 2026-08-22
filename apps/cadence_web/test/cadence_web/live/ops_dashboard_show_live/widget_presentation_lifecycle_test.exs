defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationLifecycleTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames, RenderWidget, ResolveWarning}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "widget presenter marks partial data from frame warning codes" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "source-request-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "HK.counter", kind: :number, values: [41]}
          ],
          meta: %{observable_id: "HK.counter", warning_codes: [:partial_data]}
        }
      ]
    }

    assert %{
             lifecycle_state: :partial,
             lifecycle: %{
               state: :partial,
               severity: :warning,
               reason_codes: [:partial, :partial_data]
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })
  end

  test "widget presenter returns unsupported lifecycle when source cannot satisfy the request" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :unsupported_source_capability,
          severity: :error,
          message: "Unsupported"
        }
      ]
    }

    assert %{
             kind: :point,
             sample: nil,
             lifecycle_state: :unsupported,
             lifecycle: %{
               state: :unsupported,
               severity: :error,
               reason_codes: [:unsupported, :no_data, :unsupported_source_capability]
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })
  end
end
