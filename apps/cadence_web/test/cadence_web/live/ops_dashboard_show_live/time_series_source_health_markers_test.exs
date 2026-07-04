defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceHealthMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesSourceHealthMarkers

  test "event_markers projects source health transition events with source context" do
    frame = %Frame{
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
          requested_dataset: "mission_events",
          requested_validity_state: :canonical
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

    assert TimeSeriesSourceHealthMarkers.event_frame?(frame)

    assert [
             %{
               marker_type: "source_health_transition",
               timestamp_ms: 1_782_043_320_000,
               link_id: "source_health_event:source-health-1:events-request-1",
               target: "source_health_event",
               target_id: "source-health-1",
               source_health_event_id: "source-health-1",
               event_kind: "degraded",
               severity: "warning",
               title: "telemetry source degraded",
               source_record_id: "source-health-1",
               source_health: "degraded",
               previous_source_health: "healthy",
               reason: "source_probe_failed",
               source_request_id: "events-request-1",
               logical_source: "telemetry",
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry",
               dataset: "mission_events",
               realm: "replay",
               time_mode: "replay_run",
               time_axis: "occurred_at",
               replay_run_id: "replay-run-1",
               requested_realm: "replay",
               requested_data_view: "all_revisions",
               requested_data_source_id: "events-projection",
               requested_source_binding_id: "events-binding",
               requested_dataset: "mission_events",
               requested_validity_state: "canonical"
             }
           ] = TimeSeriesSourceHealthMarkers.event_markers(frame)
  end

  test "event_markers falls back to source context identifiers" do
    frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-21 12:02:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:recovered]},
        %Field{name: "source_health", kind: :enum, values: [:healthy]}
      ],
      meta: %{
        "family" => "source_health",
        "source_request_context" => %{
          logical_source: :telemetry,
          data_source_id: "replay-questdb",
          source_binding_id: "replay-binding",
          realm: :replay,
          replay_run_id: "replay-1"
        },
        links: [
          %{
            "link_id" => "source-health-link-2",
            "target" => "source_health_event",
            "target_id" => "source-health-2"
          }
        ]
      }
    }

    assert [
             %{
               target_id: "source-health-2",
               source_health_event_id: "source-health-2",
               logical_source: "telemetry",
               data_source_id: "replay-questdb",
               source_binding_id: "replay-binding",
               realm: "replay",
               replay_run_id: "replay-1",
               event_kind: "recovered",
               source_health: "healthy"
             }
           ] = TimeSeriesSourceHealthMarkers.event_markers(frame)
  end

  test "event_markers ignores incomplete or unrelated frames" do
    unrelated_frame = %Frame{
      source: :events,
      shape: :events,
      fields: [],
      meta: %{family: :events}
    }

    incomplete_frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :string, values: ["2026-06-21T12:02:00Z"]},
        %Field{name: "source_health", kind: :enum, values: [:degraded]}
      ],
      meta: %{family: :source_health}
    }

    refute TimeSeriesSourceHealthMarkers.event_frame?(unrelated_frame)
    assert TimeSeriesSourceHealthMarkers.event_markers(incomplete_frame) == []
    assert TimeSeriesSourceHealthMarkers.event_markers(nil) == []
  end
end
