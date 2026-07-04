defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceBindingMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceBindingMarkers

  test "interval_markers projects source binding interval provenance" do
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
              requested_data_view: :canonical,
              requested_data_source_id: "questdb-replay",
              requested_source_binding_id: "binding-replay",
              requested_dataset: "replay-dataset",
              requested_validity_state: :canonical
            },
            source_binding_interval: %{
              source_binding_id: "binding-replay",
              source_binding_version: 3,
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
               source_binding_version: 3,
               data_binding_event_id: "binding-event-1",
               data_source_id: "questdb-replay",
               dataset: "replay-dataset",
               realm: "replay",
               time_mode: "replay_run",
               time_axis: "receipt_time",
               replay_run_id: "replay-run-1",
               requested_realm: "replay",
               requested_data_view: "canonical",
               requested_data_source_id: "questdb-replay",
               requested_source_binding_id: "binding-replay",
               requested_dataset: "replay-dataset",
               requested_validity_state: "canonical",
               event_type: "activated",
               status: "active",
               label: "binding-replay / questdb-replay"
             }
           ] = TimeSeriesSourceBindingMarkers.interval_markers(placement_frames)
  end

  test "interval_markers normalizes binding segments and dedupes duplicate markers" do
    segment = %{
      binding_id: "binding-flight",
      binding_version: 2,
      data_binding_event_id: "binding-event-2",
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      from: ~U[2026-06-18 01:00:00Z],
      to: ~U[2026-06-18 02:00:00Z],
      interval: %{
        event_type: :activated,
        status: :active,
        logical_source: :telemetry
      }
    }

    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :wide,
          meta: %{
            source_request_id: "req-flight",
            logical_source: :telemetry,
            source_binding_segments: [segment, segment]
          }
        }
      ]
    }

    assert [
             %{
               marker_type: "source_binding_interval",
               marker_id: "source-binding:binding-flight:binding-event-2:1781744400000",
               starts_at_ms: 1_781_744_400_000,
               ends_at_ms: 1_781_748_000_000,
               source_request_id: "req-flight",
               logical_source: "telemetry",
               source_binding_id: "binding-flight",
               source_binding_version: 2,
               data_binding_event_id: "binding-event-2",
               data_source_id: "questdb-flight",
               dataset: "flight",
               realm: "flight",
               event_type: "activated",
               status: "active",
               label: "binding-flight / questdb-flight"
             }
           ] = TimeSeriesSourceBindingMarkers.interval_markers(placement_frames)
  end

  test "interval_markers ignores incomplete source binding intervals" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{meta: %{source_binding_interval: %{source_binding_id: "missing-start"}}},
        %Frame{meta: %{source_binding_interval: %{started_at: ~U[2026-06-18 01:00:00Z]}}}
      ]
    }

    assert TimeSeriesSourceBindingMarkers.interval_markers(placement_frames) == []
  end
end
