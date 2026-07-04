defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesWidgetMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesWidgetMarkers

  test "markers are gated to time-series widgets" do
    placement_frames = placement_frames()
    time_series_widget = %RenderWidget{type: :time_series}
    value_tile_widget = %RenderWidget{type: :value_tile}

    assert [%{limit_event_id: "limit-event-red"}] =
             TimeSeriesWidgetMarkers.limit_markers(placement_frames, time_series_widget)

    assert [%{mission_event_id: "mission-event-1"}] =
             TimeSeriesWidgetMarkers.event_markers(placement_frames, time_series_widget)

    assert TimeSeriesWidgetMarkers.limit_markers(placement_frames, value_tile_widget) == []
    assert TimeSeriesWidgetMarkers.event_markers(placement_frames, value_tile_widget) == []
    assert TimeSeriesWidgetMarkers.append_markers(placement_frames, value_tile_widget) == %{}
  end

  test "append_markers returns typed marker buckets" do
    assert %{
             limit_markers: [%{limit_event_id: "limit-event-red"}],
             event_markers: [%{mission_event_id: "mission-event-1"}]
           } =
             TimeSeriesWidgetMarkers.append_markers(
               placement_frames(),
               %RenderWidget{type: :time_series}
             )
  end

  test "append_markers filters markers already present in a previous snapshot" do
    placement_frames = placement_frames()
    widget = %RenderWidget{type: :time_series}

    assert TimeSeriesWidgetMarkers.append_markers(
             placement_frames,
             widget,
             TimeSeriesWidgetMarkers.snapshot(placement_frames, widget)
           ) == %{}
  end

  defp placement_frames do
    %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :events,
            fields: [
              %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
              %Field{name: "sample_id", kind: :string, values: ["sample-red"]},
              %Field{name: "normalized_state", kind: :enum, values: [:red]},
              %Field{name: "limit_state", kind: :enum, values: [:high_red]},
              %Field{name: "violation", kind: :boolean, values: [true]}
            ],
            meta: %{
              links: [
                %{
                  "link_id" => "limit-link-red",
                  "target" => "limit_event",
                  "target_id" => "limit-event-red",
                  "label" => "Limit event"
                }
              ]
            }
          }
        ],
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
              %Field{name: "category", kind: :enum, values: [:mission_timeline]},
              %Field{name: "kind", kind: :enum, values: [:operator_note]},
              %Field{name: "severity", kind: :enum, values: [:info]},
              %Field{name: "title", kind: :string, values: ["AOS confirmed"]},
              %Field{name: "source_record_id", kind: :string, values: ["mission-event-1"]}
            ],
            meta: %{
              family: :mission_timeline,
              links: [
                %DataLink{
                  link_id: "mission-event:mission-event-1",
                  target: :mission_event,
                  target_id: "mission-event-1",
                  label: "Mission event"
                }
              ]
            }
          }
        ]
      }
    }
  end
end
