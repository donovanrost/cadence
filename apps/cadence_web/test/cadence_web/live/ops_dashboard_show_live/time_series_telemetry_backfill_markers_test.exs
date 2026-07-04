defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesTelemetryBackfillMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesTelemetryBackfillMarkers

  test "event_markers projects telemetry backfill lifecycle events with source context" do
    frame = %Frame{
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
        %Field{name: "receipt_from", kind: :time, values: [~U[2026-06-22 12:10:00Z]]},
        %Field{name: "receipt_to", kind: :time, values: [~U[2026-06-22 12:20:00Z]]},
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
        dataset: "flight-telemetry-dataset",
        source_request_context: %{
          time_mode: :live,
          time_axis: :source_time,
          requested_realm: :flight,
          requested_data_view: :canonical,
          requested_data_source_id: "flight-questdb",
          requested_source_binding_id: "flight-telemetry",
          requested_dataset: "flight-request",
          requested_validity_state: :canonical
        },
        links: [
          %{
            "link_id" => "backfill-link-1",
            "target" => "telemetry_backfill_lifecycle_event",
            "target_id" => "late-data-event-1"
          }
        ]
      }
    }

    assert TimeSeriesTelemetryBackfillMarkers.event_frame?(frame)

    assert [
             %{
               marker_type: "telemetry_backfill_lifecycle",
               marker_id: "telemetry-backfill-lifecycle:late-data-event-1:1782126000000",
               timestamp_ms: 1_782_130_860_000,
               starts_at_ms: 1_782_126_000_000,
               ends_at_ms: 1_782_129_600_000,
               source_from_ms: 1_782_126_000_000,
               source_to_ms: 1_782_129_600_000,
               receipt_from_ms: 1_782_130_200_000,
               receipt_to_ms: 1_782_130_800_000,
               link_id: "backfill-link-1",
               data_link_target: "telemetry_backfill_lifecycle_event",
               data_link_target_id: "late-data-event-1",
               target: "telemetry_backfill",
               target_id: "late-data-run-1",
               telemetry_backfill_lifecycle_event_id: "late-data-event-1",
               backfill_run_id: "late-data-run-1",
               source_request_id: "events-request-1",
               logical_source: "telemetry",
               source_binding_id: "flight-telemetry",
               data_source_id: "flight-questdb",
               dataset: "flight-telemetry-dataset",
               realm: "flight",
               observable_id: "HK.counter",
               point_id: "HK.counter",
               spacecraft_id: "sc-1",
               time_mode: "live",
               time_axis: "source_time",
               requested_realm: "flight",
               requested_data_view: "canonical",
               requested_data_source_id: "flight-questdb",
               requested_source_binding_id: "flight-telemetry",
               requested_dataset: "flight-request",
               requested_validity_state: "canonical",
               event_kind: "late_data_accepted",
               severity: "info",
               title: "HK.counter late data accepted",
               reason: "late_arrival_policy",
               authority: "authoritative",
               sample_count: 42,
               selected_sample_count: 2,
               projection_effect: "canonical_history_and_current_projection",
               write_validity_state: "canonical",
               record_current_values: true,
               refresh_latest_value: true,
               summary:
                 "2 selected samples; writes canonical history; refreshes current/latest; effect canonical_history_and_current_projection",
               actor_id: "ops-1",
               actor_kind: "operator",
               revision_state: "backfill",
               label: "Late data accepted / HK.counter / late-data-run-1"
             }
           ] = TimeSeriesTelemetryBackfillMarkers.event_markers(frame)
  end

  test "event_markers falls back to source context identifiers" do
    frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-22 12:21:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:backfill_completed]},
        %Field{name: "source_record_id", kind: :string, values: ["backfill-event-1"]},
        %Field{name: "backfill_run_id", kind: :string, values: ["backfill-run-1"]},
        %Field{name: "point_id", kind: :string, values: ["PAYLOAD.rate"]},
        %Field{name: "selected_sample_count", kind: :number, values: [1]},
        %Field{name: "write_validity_state", kind: :enum, values: [:advisory]},
        %Field{name: "record_current_values", kind: :boolean, values: [false]},
        %Field{name: "refresh_latest_value", kind: :boolean, values: [false]}
      ],
      meta: %{
        "family" => "telemetry_backfill",
        "source_request_context" => %{
          data_source_id: "replay-questdb",
          source_binding_id: "replay-binding",
          realm: :replay,
          replay_run_id: "replay-1"
        }
      }
    }

    assert [
             %{
               data_source_id: "replay-questdb",
               source_binding_id: "replay-binding",
               realm: "replay",
               replay_run_id: "replay-1",
               observable_id: "PAYLOAD.rate",
               summary:
                 "1 selected sample; writes advisory history; does not refresh current/latest",
               label: "Backfill completed / PAYLOAD.rate / backfill-run-1"
             }
           ] = TimeSeriesTelemetryBackfillMarkers.event_markers(frame)
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
        %Field{name: "occurred_at", kind: :string, values: ["2026-06-22T12:21:00Z"]},
        %Field{name: "source_record_id", kind: :string, values: ["backfill-event-1"]}
      ],
      meta: %{family: :telemetry_backfill}
    }

    refute TimeSeriesTelemetryBackfillMarkers.event_frame?(unrelated_frame)
    assert TimeSeriesTelemetryBackfillMarkers.event_markers(incomplete_frame) == []
    assert TimeSeriesTelemetryBackfillMarkers.event_markers(nil) == []
  end
end
