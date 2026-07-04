defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesMarkers

  test "limit markers include active definition intervals" do
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

    assert [
             %{
               marker_type: "limit_definition_interval",
               starts_at_ms: 1_781_697_600_000,
               ends_at_ms: 1_781_698_200_000,
               limit_definition_id: "counter-limits",
               limit_definition_version: 2,
               limit_set_name: "ops"
             }
           ] = TimeSeriesMarkers.limit_markers(placement_frames)
  end

  test "event markers include source binding interval provenance" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :wide,
          meta: %{
            source_request_id: "req-replay",
            logical_source: :telemetry,
            source_binding_id: "binding-replay",
            data_source_id: "questdb-replay",
            realm: :replay,
            dataset: "replay-dataset",
            source_request_context: %{
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
            }
          }
        }
      ]
    }

    assert [
             %{
               marker_type: "source_binding_interval",
               marker_id: "source-binding:binding-replay:binding-event-1:1781690400000",
               starts_at_ms: 1_781_690_400_000,
               ends_at_ms: 1_781_697_600_000,
               target: "source_binding",
               target_id: "binding-replay",
               source_request_id: "req-replay",
               logical_source: "telemetry",
               source_binding_id: "binding-replay",
               data_source_id: "questdb-replay",
               replay_run_id: "replay-run-1",
               requested_realm: "replay",
               status: "active"
             }
           ] = TimeSeriesMarkers.event_markers(placement_frames)
  end

  test "event markers include late data policy execution summary" do
    placement_frames = %PlacementFrames{
      overlays: %{
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-22 12:21:00Z]]},
              %Field{name: "kind", kind: :enum, values: [:late_data_accepted]},
              %Field{name: "severity", kind: :enum, values: [:info]},
              %Field{name: "title", kind: :string, values: ["HK.counter late data accepted"]},
              %Field{name: "source_record_id", kind: :string, values: ["late-data-event-1"]},
              %Field{name: "backfill_run_id", kind: :string, values: ["late-data-run-1"]},
              %Field{name: "realm", kind: :enum, values: [:flight]},
              %Field{name: "data_source_id", kind: :string, values: ["flight-questdb"]},
              %Field{name: "source_binding_id", kind: :string, values: ["flight-telemetry"]},
              %Field{name: "observable_id", kind: :string, values: ["HK.counter"]},
              %Field{name: "point_id", kind: :string, values: ["HK.counter"]},
              %Field{name: "spacecraft_id", kind: :string, values: ["sc-1"]},
              %Field{name: "source_from", kind: :time, values: [~U[2026-06-22 11:00:00Z]]},
              %Field{name: "source_to", kind: :time, values: [~U[2026-06-22 12:00:00Z]]},
              %Field{name: "sample_count", kind: :number, values: [42]},
              %Field{name: "selected_sample_count", kind: :number, values: [2]},
              %Field{
                name: "projection_effect",
                kind: :enum,
                values: [:canonical_history_and_current_projection]
              },
              %Field{name: "write_validity_state", kind: :enum, values: [:canonical]},
              %Field{name: "record_current_values", kind: :boolean, values: [true]},
              %Field{name: "refresh_latest_value", kind: :boolean, values: [true]},
              %Field{name: "authority", kind: :enum, values: [:authoritative]},
              %Field{name: "reason", kind: :enum, values: [:late_arrival_policy]},
              %Field{name: "actor_id", kind: :string, values: ["ops-1"]},
              %Field{name: "actor_kind", kind: :enum, values: [:operator]}
            ],
            meta: %{
              family: :telemetry_backfill,
              source_request_id: "events-request-1",
              source_request_context: %{
                requested_realm: :flight,
                requested_data_view: :canonical,
                requested_data_source_id: "flight-questdb",
                requested_source_binding_id: "flight-telemetry"
              }
            }
          }
        ]
      }
    }

    assert [
             %{
               marker_type: "telemetry_backfill_lifecycle",
               marker_id: "telemetry-backfill-lifecycle:late-data-event-1:1782126000000",
               timestamp_ms: 1_782_130_860_000,
               starts_at_ms: 1_782_126_000_000,
               ends_at_ms: 1_782_129_600_000,
               target: "telemetry_backfill",
               target_id: "late-data-run-1",
               telemetry_backfill_lifecycle_event_id: "late-data-event-1",
               backfill_run_id: "late-data-run-1",
               event_kind: "late_data_accepted",
               selected_sample_count: 2,
               projection_effect: "canonical_history_and_current_projection",
               write_validity_state: "canonical",
               record_current_values: true,
               refresh_latest_value: true,
               summary:
                 "2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection",
               label: "Late data accepted / HK.counter / late-data-run-1"
             }
           ] = TimeSeriesMarkers.event_markers(placement_frames)
  end

  test "marker entry points tolerate missing placement frames" do
    assert TimeSeriesMarkers.limit_markers(nil) == []
    assert TimeSeriesMarkers.event_markers(nil) == []
  end
end
