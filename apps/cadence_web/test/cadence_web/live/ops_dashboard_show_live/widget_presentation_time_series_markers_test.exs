defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationTimeSeriesMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "time-series limit markers include definition intervals" do
    placement_frames = %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :intervals,
            fields: [
              %Field{name: "active_from", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
              %Field{name: "active_to", kind: :time, values: [~U[2026-06-17 12:10:00Z]]},
              %Field{name: "limit_definition_id", kind: :string, values: ["counter-limits"]},
              %Field{name: "limit_definition_version", kind: :number, values: [2]},
              %Field{name: "limit_set_name", kind: :string, values: ["ops"]},
              %Field{name: "red_low", kind: :number, values: [0]},
              %Field{name: "yellow_low", kind: :number, values: [5]},
              %Field{name: "yellow_high", kind: :number, values: [10]},
              %Field{name: "red_high", kind: :number, values: [20]}
            ],
            meta: %{
              links: [
                %{
                  "link_id" => "limit_definition:counter-limits:req-1",
                  "target" => "limit_definition",
                  "target_id" => "counter-limits",
                  "label" => "Limit definition",
                  "presentation" => "side_panel",
                  "source" => "frame"
                }
              ]
            }
          }
        ]
      }
    }

    widget = %RenderWidget{type: :time_series}

    assert [
             %{
               marker_type: "limit_definition_interval",
               starts_at_ms: 1_781_697_600_000,
               ends_at_ms: 1_781_698_200_000,
               link_id: "limit_definition:counter-limits:req-1",
               target: "limit_definition",
               target_id: "counter-limits",
               limit_definition_id: "counter-limits",
               limit_definition_version: 2,
               limit_set_name: "ops",
               red_low: 0,
               yellow_low: 5,
               yellow_high: 10,
               red_high: 20
             }
           ] = WidgetPresentation.limit_markers(placement_frames, widget)
  end

  test "time-series source markers carry replay request provenance" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-replay",
          source: :telemetry,
          shape: :wide,
          meta: %{
            source_request_id: "req-replay",
            logical_source: :telemetry,
            source_binding_id: "binding-replay",
            data_source_id: "questdb-replay",
            realm: :replay,
            dataset: "replay-dataset",
            source_request_time_context: %{
              mode: :replay_run,
              axis: :receipt_time,
              from: ~U[2026-06-17 10:00:00Z],
              to: ~U[2026-06-17 12:00:00Z],
              replay_run_id: "replay-run-1"
            },
            source_request_context: %{
              source_request_id: "req-replay",
              logical_source: :telemetry,
              time_mode: :replay_run,
              time_axis: :receipt_time,
              replay_run_id: "replay-run-1",
              requested_realm: :replay,
              requested_data_source_id: "questdb-replay",
              requested_source_binding_id: "binding-replay",
              requested_dataset: "replay-dataset"
            },
            source_binding_interval: %{
              source_binding_id: "binding-replay",
              data_binding_event_id: "binding-event-1",
              data_source_id: "questdb-replay",
              dataset: "replay-dataset",
              realm: :replay,
              logical_source: :telemetry,
              started_at: ~U[2026-06-17 10:00:00Z],
              ended_at: ~U[2026-06-17 12:00:00Z],
              event_type: :activated,
              status: :active
            },
            source_watermarks: [
              %{
                logical_source: :telemetry,
                request_id: "req-replay",
                source_binding_id: "binding-replay",
                data_source_id: "questdb-replay",
                dataset: "replay-dataset",
                realm: :replay,
                freshness_state: :retention_gap,
                confidence: :authoritative,
                retention_starts_at: ~U[2026-06-17 11:00:00Z]
              }
            ]
          }
        }
      ]
    }

    widget = %RenderWidget{type: :time_series}
    markers = WidgetPresentation.event_markers(placement_frames, widget)

    source_binding_marker =
      Enum.find(markers, &(&1.marker_type == "source_binding_interval"))

    assert source_binding_marker.replay_run_id == "replay-run-1"
    assert source_binding_marker.time_mode == "replay_run"
    assert source_binding_marker.time_axis == "receipt_time"
    assert source_binding_marker.requested_realm == "replay"
    assert source_binding_marker.requested_data_source_id == "questdb-replay"
    assert source_binding_marker.requested_source_binding_id == "binding-replay"
    assert source_binding_marker.requested_dataset == "replay-dataset"

    retention_marker = Enum.find(markers, &(&1.marker_type == "retention_gap"))

    assert retention_marker.replay_run_id == "replay-run-1"
    assert retention_marker.time_mode == "replay_run"
    assert retention_marker.time_axis == "receipt_time"
    assert retention_marker.requested_realm == "replay"
    assert retention_marker.requested_data_source_id == "questdb-replay"
    assert retention_marker.requested_source_binding_id == "binding-replay"
    assert retention_marker.requested_dataset == "replay-dataset"
  end

  test "time-series event markers exclude source-health transitions from the legacy path" do
    placement_frames = %PlacementFrames{
      overlays: %{
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-21 12:02:00Z]]},
              %Field{name: "category", kind: :enum, values: [:source_health]},
              %Field{name: "kind", kind: :enum, values: [:degraded]},
              %Field{name: "severity", kind: :enum, values: [:warning]},
              %Field{name: "title", kind: :string, values: ["telemetry source degraded"]},
              %Field{name: "source_record_id", kind: :string, values: ["source-health-1"]},
              %Field{name: "source_health", kind: :enum, values: [:degraded]},
              %Field{name: "previous_source_health", kind: :enum, values: [:healthy]},
              %Field{name: "reason", kind: :enum, values: [:source_probe_failed]},
              %Field{name: "logical_source", kind: :enum, values: [:telemetry]},
              %Field{name: "data_source_id", kind: :string, values: ["flight-questdb"]},
              %Field{name: "source_binding_id", kind: :string, values: ["flight-telemetry"]}
            ],
            meta: %{
              family: :source_health,
              source_request_id: "events-request-1",
              logical_source: :events,
              source_binding_id: "events-binding",
              data_source_id: "events-projection",
              realm: :replay,
              dataset: "mission_events",
              replay_run_id: "replay-run-1",
              source_request_context: %{
                source_request_id: "events-request-1",
                logical_source: :events,
                time_mode: :replay_run,
                time_axis: :occurred_at,
                replay_run_id: "replay-run-1",
                requested_realm: :replay,
                requested_data_view: :all_revisions,
                requested_data_source_id: "events-projection",
                requested_source_binding_id: "events-binding",
                requested_dataset: "mission_events"
              },
              links: [
                %DataLink{
                  link_id: "source_health_event:source-health-1:events-request-1",
                  label: "Source health event",
                  target: :source_health_event,
                  target_id: "source-health-1",
                  source: :frame
                }
              ]
            }
          }
        ]
      }
    }

    widget = %RenderWidget{type: :time_series}

    assert WidgetPresentation.event_markers(placement_frames, widget) == []
  end

  test "time-series event markers include source-watermark events" do
    placement_frames = %PlacementFrames{
      overlays: %{
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-21 12:06:00Z]]},
              %Field{name: "category", kind: :enum, values: [:source_watermark]},
              %Field{name: "kind", kind: :enum, values: [:advanced]},
              %Field{name: "severity", kind: :enum, values: [:info]},
              %Field{name: "title", kind: :string, values: ["telemetry watermark advanced"]},
              %Field{name: "source_record_id", kind: :string, values: ["watermark-event-1"]},
              %Field{name: "logical_source", kind: :enum, values: [:telemetry]},
              %Field{name: "data_source_id", kind: :string, values: ["flight-questdb"]},
              %Field{name: "source_binding_id", kind: :string, values: ["flight-telemetry"]},
              %Field{name: "realm", kind: :enum, values: [:flight]},
              %Field{name: "dataset", kind: :string, values: ["flight"]},
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
              %Field{
                name: "retention_starts_at",
                kind: :time,
                values: [~U[2026-06-20 00:00:00Z]]
              },
              %Field{name: "confidence", kind: :enum, values: [:authoritative]},
              %Field{name: "reason", kind: :enum, values: [:source_watermark_observed]}
            ],
            meta: %{
              family: :source_watermark,
              source_request_id: "events-request-1",
              logical_source: :events,
              source_binding_id: "events-binding",
              data_source_id: "events-projection",
              realm: :flight,
              dataset: "mission_events",
              source_request_context: %{
                source_request_id: "events-request-1",
                logical_source: :events,
                time_mode: :archive,
                time_axis: :occurred_at,
                requested_realm: :flight,
                requested_data_view: :canonical,
                requested_data_source_id: "events-projection",
                requested_source_binding_id: "events-binding",
                requested_dataset: "mission_events"
              },
              links: [
                %DataLink{
                  link_id: "source_watermark_event:watermark-event-1:events-request-1",
                  label: "Source watermark event",
                  target: :source_watermark_event,
                  target_id: "watermark-event-1",
                  source: :frame
                }
              ]
            }
          }
        ]
      }
    }

    widget = %RenderWidget{type: :time_series}

    [marker] = WidgetPresentation.event_markers(placement_frames, widget)

    assert marker.marker_type == "source_watermark_event"
    assert marker.marker_id == "source-watermark-event:watermark-event-1:1782043500000"
    assert marker.timestamp_ms == 1_782_043_500_000
    assert marker.observed_at_ms == 1_782_043_560_000
    assert marker.link_id == "source_watermark_event:watermark-event-1:events-request-1"
    assert marker.data_link_target == "source_watermark_event"
    assert marker.data_link_target_id == "watermark-event-1"
    assert marker.target == "source_watermark"
    assert marker.target_id == "watermark-event-1"
    assert marker.source_watermark_event_id == "watermark-event-1"
    assert marker.source_request_id == "events-request-1"
    assert marker.logical_source == "telemetry"
    assert marker.data_source_id == "flight-questdb"
    assert marker.source_binding_id == "flight-telemetry"
    assert marker.dataset == "flight"
    assert marker.realm == "flight"
    assert marker.time_mode == "archive"
    assert marker.time_axis == "occurred_at"
    assert marker.requested_realm == "flight"
    assert marker.requested_data_view == "canonical"
    assert marker.requested_data_source_id == "events-projection"
    assert marker.requested_source_binding_id == "events-binding"
    assert marker.requested_dataset == "mission_events"
    assert marker.event_kind == "advanced"
    assert marker.severity == "info"
    assert marker.title == "telemetry watermark advanced"
    assert marker.reason == "source_watermark_observed"
    assert marker.confidence == "authoritative"
    assert marker.complete_through_ms == 1_782_043_500_000
    assert marker.previous_complete_through_ms == 1_782_043_260_000
    assert marker.latest_receipt_time_ms == 1_782_043_530_000
    assert marker.previous_latest_receipt_time_ms == 1_782_043_290_000
    assert marker.retention_starts_at_ms == 1_781_913_600_000
    assert marker.label == "Watermark advanced / flight-telemetry / flight-questdb"
  end
end
