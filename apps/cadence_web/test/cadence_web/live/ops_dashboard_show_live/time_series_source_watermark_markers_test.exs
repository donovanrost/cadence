defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceWatermarkMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceWatermarkMarkers

  test "event_frame? identifies source watermark event frames" do
    assert TimeSeriesSourceWatermarkMarkers.event_frame?(%Frame{
             meta: %{family: :source_watermark}
           })

    assert TimeSeriesSourceWatermarkMarkers.event_frame?(%Frame{
             meta: %{"family" => "source_watermark"}
           })

    refute TimeSeriesSourceWatermarkMarkers.event_frame?(%Frame{
             meta: %{family: :source_health}
           })
  end

  test "event_markers projects source watermark events at the cursor time" do
    frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-21 12:00:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:advanced]},
        %Field{name: "severity", kind: :enum, values: [:info]},
        %Field{name: "title", kind: :string, values: ["telemetry watermark advanced"]},
        %Field{name: "source_record_id", kind: :string, values: ["watermark-event-1"]},
        %Field{name: "logical_source", kind: :enum, values: [:telemetry]},
        %Field{name: "data_source_id", kind: :string, values: ["questdb-flight"]},
        %Field{name: "source_binding_id", kind: :string, values: ["binding-flight"]},
        %Field{name: "realm", kind: :enum, values: [:flight]},
        %Field{name: "dataset", kind: :string, values: ["samples"]},
        %Field{name: "complete_through", kind: :time, values: [~U[2026-06-21 12:05:00Z]]},
        %Field{
          name: "previous_complete_through",
          kind: :time,
          values: [~U[2026-06-21 12:01:00Z]]
        },
        %Field{
          name: "latest_receipt_time",
          kind: :time,
          values: [~U[2026-06-21 12:05:30Z]]
        },
        %Field{
          name: "previous_latest_receipt_time",
          kind: :time,
          values: [~U[2026-06-21 12:01:30Z]]
        },
        %Field{name: "retention_starts_at", kind: :time, values: [~U[2026-06-20 00:00:00Z]]},
        %Field{name: "confidence", kind: :enum, values: [:best_effort]},
        %Field{name: "reason", kind: :enum, values: [:source_watermark_observed]}
      ],
      meta: %{
        family: :source_watermark,
        source_request_id: "req-watermark",
        logical_source: :telemetry,
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        realm: :flight,
        dataset: "samples",
        source_request_context: %{
          time_mode: :archive,
          time_axis: :receipt_time,
          requested_data_view: :canonical
        },
        links: [
          %DataLink{
            link_id: "source_watermark_event:watermark-event-1:req-watermark",
            label: "Source watermark event",
            target: :source_watermark_event,
            target_id: "watermark-event-1",
            source: :frame
          }
        ]
      }
    }

    assert [
             %{
               marker_type: "source_watermark_event",
               marker_id: "source-watermark-event:watermark-event-1:1782043500000",
               timestamp_ms: 1_782_043_500_000,
               observed_at_ms: 1_782_043_200_000,
               link_id: "source_watermark_event:watermark-event-1:req-watermark",
               data_link_target: "source_watermark_event",
               data_link_target_id: "watermark-event-1",
               target: "source_watermark",
               target_id: "watermark-event-1",
               source_watermark_event_id: "watermark-event-1",
               source_request_id: "req-watermark",
               logical_source: "telemetry",
               source_binding_id: "binding-flight",
               data_source_id: "questdb-flight",
               dataset: "samples",
               realm: "flight",
               time_mode: "archive",
               time_axis: "receipt_time",
               requested_data_view: "canonical",
               event_kind: "advanced",
               severity: "info",
               title: "telemetry watermark advanced",
               reason: "source_watermark_observed",
               confidence: "best_effort",
               complete_through_ms: 1_782_043_500_000,
               previous_complete_through_ms: 1_782_043_260_000,
               latest_receipt_time_ms: 1_782_043_530_000,
               previous_latest_receipt_time_ms: 1_782_043_290_000,
               retention_starts_at_ms: 1_781_913_600_000,
               label: "Watermark advanced / binding-flight / questdb-flight"
             }
           ] = TimeSeriesSourceWatermarkMarkers.event_markers(frame)
  end

  test "frame_markers projects retention gaps and watermark cursors" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :wide,
          meta: %{
            source_request_id: "req-watermark",
            logical_source: :telemetry,
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            realm: :flight,
            dataset: "samples",
            source_request_context: %{
              time_mode: :archive,
              time_axis: :receipt_time,
              requested_data_view: :canonical
            },
            source_request_time_context: %{from: ~U[2026-06-17 09:55:00Z]},
            source_watermarks: [
              source_watermark(),
              source_watermark()
            ]
          }
        }
      ]
    }

    markers = TimeSeriesSourceWatermarkMarkers.frame_markers(placement_frames)

    assert [%{marker_type: "retention_gap"} = retention_marker] =
             Enum.filter(markers, &(&1.marker_type == "retention_gap"))

    assert [%{marker_type: "source_watermark_cursor"} = cursor_marker] =
             Enum.filter(markers, &(&1.marker_type == "source_watermark_cursor"))

    assert retention_marker.marker_id == "retention-gap:req-watermark:1781690400000"
    assert retention_marker.starts_at_ms == 1_781_690_100_000
    assert retention_marker.ends_at_ms == 1_781_690_400_000
    assert retention_marker.timestamp_ms == 1_781_690_400_000
    assert retention_marker.source_request_id == "req-watermark"
    assert retention_marker.logical_source == "telemetry"
    assert retention_marker.data_source_id == "questdb-flight"
    assert retention_marker.source_binding_id == "binding-flight"
    assert retention_marker.dataset == "samples"
    assert retention_marker.realm == "flight"
    assert retention_marker.time_mode == "archive"
    assert retention_marker.time_axis == "receipt_time"
    assert retention_marker.requested_data_view == "canonical"
    assert retention_marker.confidence == "best_effort"
    assert retention_marker.freshness_state == "retention_gap"
    assert retention_marker.complete_through_ms == 1_781_690_670_000
    assert retention_marker.latest_receipt_time_ms == 1_781_690_685_000
    assert retention_marker.retention_starts_at_ms == 1_781_690_400_000
    assert retention_marker.label == "Retention gap / binding-flight / questdb-flight"

    assert cursor_marker.marker_id ==
             "source-watermark-cursor:req-watermark:complete_through:1781690670000"

    assert cursor_marker.timestamp_ms == 1_781_690_670_000
    assert cursor_marker.target == "source_watermark"
    assert cursor_marker.target_id == "req-watermark"
    assert cursor_marker.cursor_kind == "complete_through"
    assert cursor_marker.source_watermark_event_id == "watermark-event-1"
    assert cursor_marker.label == "Watermark complete through / binding-flight / questdb-flight"
  end

  defp source_watermark do
    %{
      request_id: "req-watermark",
      logical_source: :telemetry,
      data_source_id: "questdb-flight",
      source_binding_id: "binding-flight",
      realm: :flight,
      dataset: "samples",
      freshness_state: :retention_gap,
      retention_starts_at: ~U[2026-06-17 10:00:00Z],
      complete_through: ~U[2026-06-17 10:04:30Z],
      latest_receipt_time: ~U[2026-06-17 10:04:45Z],
      confidence: :best_effort,
      source_watermark_event_id: "watermark-event-1"
    }
  end
end
