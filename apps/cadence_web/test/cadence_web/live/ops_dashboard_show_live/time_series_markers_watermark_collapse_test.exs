defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkersWatermarkCollapseTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkers

  test "collapses high-frequency watermark advances behind the current completeness cursor" do
    placement_frames = %PlacementFrames{
      primary: [primary_frame()],
      overlays: %{events: [watermark_event_frame()]}
    }

    assert [
             %{
               marker_type: "source_watermark_cursor",
               display_mode: "status",
               timestamp_ms: 1_782_043_500_000
             }
           ] = TimeSeriesMarkers.event_markers(placement_frames)
  end

  test "retains only the latest watermark event when no source cursor is available" do
    placement_frames = %PlacementFrames{overlays: %{events: [watermark_event_frame()]}}

    assert [
             %{
               marker_type: "source_watermark_event",
               source_watermark_event_id: "watermark-event-2",
               timestamp_ms: 1_782_043_500_000
             }
           ] = TimeSeriesMarkers.event_markers(placement_frames)
  end

  defp primary_frame do
    %Frame{
      source: :telemetry,
      shape: :wide,
      meta: %{
        source_request_id: "telemetry-request",
        logical_source: :telemetry,
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        realm: :flight,
        dataset: "samples",
        source_request_context: %{time_mode: :live, time_axis: :generation_time},
        source_watermarks: [
          %{
            request_id: "telemetry-request",
            logical_source: :telemetry,
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            realm: :flight,
            dataset: "samples",
            freshness_state: :fresh,
            complete_through: ~U[2026-06-21 12:05:00Z],
            latest_receipt_time: ~U[2026-06-21 12:05:01Z],
            confidence: :best_effort,
            source_watermark_event_id: "watermark-event-2"
          }
        ]
      }
    }
  end

  defp watermark_event_frame do
    %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{
          name: "occurred_at",
          kind: :time,
          values: [~U[2026-06-21 12:04:30Z], ~U[2026-06-21 12:05:00Z]]
        },
        %Field{name: "kind", kind: :enum, values: [:advanced, :advanced]},
        %Field{name: "severity", kind: :enum, values: [:info, :info]},
        %Field{
          name: "title",
          kind: :string,
          values: ["Watermark advanced", "Watermark advanced"]
        },
        %Field{
          name: "source_record_id",
          kind: :string,
          values: ["watermark-event-1", "watermark-event-2"]
        },
        %Field{name: "logical_source", kind: :enum, values: [:telemetry, :telemetry]},
        %Field{
          name: "data_source_id",
          kind: :string,
          values: ["questdb-flight", "questdb-flight"]
        },
        %Field{
          name: "source_binding_id",
          kind: :string,
          values: ["binding-flight", "binding-flight"]
        },
        %Field{name: "realm", kind: :enum, values: [:flight, :flight]},
        %Field{name: "dataset", kind: :string, values: ["samples", "samples"]},
        %Field{
          name: "complete_through",
          kind: :time,
          values: [~U[2026-06-21 12:04:30Z], ~U[2026-06-21 12:05:00Z]]
        },
        %Field{name: "confidence", kind: :enum, values: [:best_effort, :best_effort]},
        %Field{
          name: "reason",
          kind: :enum,
          values: [:telemetry_storage_write, :telemetry_storage_write]
        }
      ],
      meta: %{
        family: :source_watermark,
        source_request_id: "events-request",
        source_request_context: %{time_mode: :live, time_axis: :occurred_at},
        links: [
          %DataLink{
            link_id: "watermark-event-1-link",
            label: "Watermark event",
            target: :source_watermark_event,
            target_id: "watermark-event-1",
            source: :frame
          },
          %DataLink{
            link_id: "watermark-event-2-link",
            label: "Watermark event",
            target: :source_watermark_event,
            target_id: "watermark-event-2",
            source: :frame
          }
        ]
      }
    }
  end
end
