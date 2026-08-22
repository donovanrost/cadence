defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetData

  test "renders fixed telemetry scalar value tiles" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "source-request-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          scope: %{primary: %{ids: ["spacecraft-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "HK.counter", kind: :number, values: [41]}
          ],
          meta: %{observable_id: "HK.counter", warning_codes: []}
        }
      ]
    }

    assert %{
             kind: :point,
             spacecraft_id: "spacecraft-alpha",
             sample: %{
               raw_value: 41,
               engineering_value: 41,
               receipt_time: ~U[2026-06-17 12:00:00Z],
               quality_state: :good
             },
             unresolved?: false,
             engine_backed?: true,
             lifecycle_state: :ready
           } =
             WidgetData.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })
  end

  test "context widgets remain unresolved without scoped identity" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "HK.counter", kind: :number, values: [41]}
          ],
          meta: %{observable_id: "HK.counter", warning_codes: []}
        }
      ]
    }

    assert %{
             kind: :point,
             sample: nil,
             unresolved?: true,
             lifecycle_state: :no_data
           } =
             WidgetData.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :context}
             })
  end

  test "unknown widget types preserve legacy data" do
    legacy_data = %{kind: :legacy, value: 123}

    assert WidgetData.data(legacy_data, nil, %RenderWidget{type: :unknown}) == legacy_data
  end
end
