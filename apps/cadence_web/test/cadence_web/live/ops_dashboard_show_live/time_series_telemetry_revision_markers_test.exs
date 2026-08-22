defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesTelemetryRevisionMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesTelemetryRevisionMarkers

  test "event_markers projects telemetry revision decision events with source context" do
    frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-22 12:10:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:mark_canonical]},
        %Field{name: "severity", kind: :enum, values: [:info]},
        %Field{name: "title", kind: :string, values: ["HK.counter revision canonical"]},
        %Field{name: "source_record_id", kind: :string, values: ["decision-event-1"]},
        %Field{name: "observation_identity_id", kind: :string, values: ["identity-1"]},
        %Field{name: "realm", kind: :enum, values: [:flight]},
        %Field{name: "data_source_id", kind: :string, values: ["flight-questdb"]},
        %Field{name: "source_binding_id", kind: :string, values: ["flight-telemetry"]},
        %Field{name: "observable_id", kind: :string, values: ["HK.counter"]},
        %Field{name: "point_id", kind: :string, values: ["HK.counter"]},
        %Field{name: "spacecraft_id", kind: :string, values: ["sc-1"]},
        %Field{
          name: "decision_reason",
          kind: :string,
          values: ["operator_selected_corrected_value"]
        },
        %Field{name: "actor_id", kind: :string, values: ["ops-1"]},
        %Field{name: "actor_kind", kind: :enum, values: ["operator"]},
        %Field{name: "previous_validity_state", kind: :enum, values: ["conflict"]},
        %Field{name: "new_validity_state", kind: :enum, values: ["canonical"]},
        %Field{name: "previous_canonical_revision", kind: :number, values: [1]},
        %Field{name: "new_canonical_revision", kind: :number, values: [2]}
      ],
      meta: %{
        family: :telemetry_revision,
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
          requested_dataset: "mission_events",
          requested_validity_state: :canonical
        },
        links: [
          %DataLink{
            link_id: "telemetry_revision_decision_event:decision-event-1:events-request-1",
            label: "Telemetry revision decision event",
            target: :telemetry_revision_decision_event,
            target_id: "decision-event-1",
            source: :frame
          }
        ]
      }
    }

    assert TimeSeriesTelemetryRevisionMarkers.event_frame?(frame)

    assert [
             %{
               marker_type: "telemetry_revision_decision",
               marker_id: "telemetry-revision-decision:decision-event-1:1782130200000",
               timestamp_ms: 1_782_130_200_000,
               link_id: "telemetry_revision_decision_event:decision-event-1:events-request-1",
               data_link_target: "telemetry_revision_decision_event",
               data_link_target_id: "decision-event-1",
               target: "telemetry_revision",
               target_id: "identity-1",
               telemetry_revision_decision_event_id: "decision-event-1",
               observation_identity_id: "identity-1",
               source_request_id: "events-request-1",
               logical_source: "telemetry",
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry",
               dataset: "mission_events",
               realm: "flight",
               observable_id: "HK.counter",
               point_id: "HK.counter",
               spacecraft_id: "sc-1",
               time_mode: "archive",
               time_axis: "occurred_at",
               requested_realm: "flight",
               requested_data_view: "canonical",
               requested_data_source_id: "events-projection",
               requested_source_binding_id: "events-binding",
               requested_dataset: "mission_events",
               requested_validity_state: "canonical",
               event_kind: "mark_canonical",
               severity: "info",
               title: "HK.counter revision canonical",
               decision_reason: "operator_selected_corrected_value",
               actor_id: "ops-1",
               actor_kind: "operator",
               previous_validity_state: "conflict",
               new_validity_state: "canonical",
               previous_canonical_revision: 1,
               new_canonical_revision: 2,
               label: "Revision mark_canonical / HK.counter / identity-1"
             }
           ] = TimeSeriesTelemetryRevisionMarkers.event_markers(frame)
  end

  test "event_markers falls back to source record target when identity is absent" do
    frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-22 12:10:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:mark_advisory]},
        %Field{name: "source_record_id", kind: :string, values: ["decision-event-2"]},
        %Field{name: "point_id", kind: :string, values: ["PAYLOAD.rate"]}
      ],
      meta: %{
        "family" => "telemetry_revision",
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
               target_id: "decision-event-2",
               telemetry_revision_decision_event_id: "decision-event-2",
               data_source_id: "replay-questdb",
               source_binding_id: "replay-binding",
               realm: "replay",
               replay_run_id: "replay-1",
               observable_id: "PAYLOAD.rate",
               label: "Revision mark_advisory / PAYLOAD.rate"
             }
           ] = TimeSeriesTelemetryRevisionMarkers.event_markers(frame)
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
        %Field{name: "occurred_at", kind: :string, values: ["2026-06-22T12:10:00Z"]},
        %Field{name: "source_record_id", kind: :string, values: ["decision-event-1"]}
      ],
      meta: %{family: :telemetry_revision}
    }

    refute TimeSeriesTelemetryRevisionMarkers.event_frame?(unrelated_frame)
    assert TimeSeriesTelemetryRevisionMarkers.event_markers(incomplete_frame) == []
    assert TimeSeriesTelemetryRevisionMarkers.event_markers(nil) == []
  end

  test "range_markers projects corrected and advisory telemetry revision ranges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :wide,
          fields: [
            %Field{
              name: "time",
              kind: :time,
              values: [~U[2026-06-17 10:00:00Z], ~U[2026-06-17 10:05:00Z]]
            },
            %Field{name: "HK.counter", kind: :number, values: [41, 42]}
          ],
          meta: %{
            source_request_id: "req-revisions",
            logical_source: :telemetry,
            observable_id: "HK.counter",
            point_id: "HK.counter",
            source_binding_id: "binding-flight",
            data_source_id: "questdb-flight",
            dataset: "flight-telemetry",
            realm: :flight,
            data_view: :canonical,
            warning_codes: ["corrected_range", :advisory_backfill],
            revision_state: %{
              identity_count: 2,
              canonical_count: 1,
              superseded_count: 1,
              advisory_count: 1,
              dependency_fingerprint: "telemetry-revision:abc"
            },
            telemetry_revision_dependency: %{
              fingerprint: "telemetry-revision:abc",
              observation_identity_ids: ["identity-1", "identity-2"]
            },
            source_request_context: %{
              time_mode: :archive,
              time_axis: :receipt_time,
              requested_realm: :flight,
              requested_data_view: :canonical,
              requested_data_source_id: "questdb-flight",
              requested_source_binding_id: "binding-flight",
              requested_dataset: "flight-telemetry",
              requested_validity_state: :canonical
            }
          }
        }
      ]
    }

    markers =
      placement_frames
      |> TimeSeriesTelemetryRevisionMarkers.range_markers()
      |> Enum.sort_by(& &1.warning_code)

    assert [
             %{
               marker_type: "telemetry_revision_range",
               marker_id:
                 "telemetry-revision:advisory_backfill:telemetry-revision:abc:1781690400000:1781690700000",
               starts_at_ms: 1_781_690_400_000,
               ends_at_ms: 1_781_690_700_000,
               timestamp_ms: 1_781_690_700_000,
               target: "telemetry_revision_state",
               target_id: "telemetry-revision:abc",
               source_request_id: "req-revisions",
               logical_source: "telemetry",
               source_binding_id: "binding-flight",
               data_source_id: "questdb-flight",
               dataset: "flight-telemetry",
               realm: "flight",
               time_mode: "archive",
               time_axis: "receipt_time",
               requested_realm: "flight",
               requested_data_view: "canonical",
               requested_data_source_id: "questdb-flight",
               requested_source_binding_id: "binding-flight",
               requested_dataset: "flight-telemetry",
               requested_validity_state: "canonical",
               observable_id: "HK.counter",
               point_id: "HK.counter",
               data_view: "canonical",
               revision_state: "backfill",
               warning_code: "advisory_backfill",
               dependency_fingerprint: "telemetry-revision:abc",
               identity_count: 2,
               canonical_count: 1,
               superseded_count: 1,
               advisory_count: 1,
               label: "Backfilled telemetry range / HK.counter"
             },
             %{
               marker_type: "telemetry_revision_range",
               marker_id:
                 "telemetry-revision:corrected_range:telemetry-revision:abc:1781690400000:1781690700000",
               revision_state: "corrected",
               warning_code: "corrected_range",
               label: "Corrected telemetry range / HK.counter"
             }
           ] = markers
  end

  test "range_markers falls back to nested revision dependency and bucket ranges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :wide,
          fields: [
            %Field{
              name: "bucket_start",
              kind: :time,
              values: ["2026-06-17T10:00:00Z"]
            },
            %Field{
              name: "bucket_end",
              kind: :time,
              values: ["2026-06-17T10:05:00Z"]
            }
          ],
          meta: %{
            observable_id: "HK.counter",
            warning_codes: [:corrected_range],
            revision_state: %{
              dependency: %{fingerprint: "nested-revision:abc"}
            }
          }
        },
        %Frame{
          source: :telemetry,
          shape: :wide,
          fields: [
            %Field{name: "bucket_start", kind: :time, values: ["2026-06-17T10:00:00Z"]},
            %Field{name: "bucket_end", kind: :time, values: ["2026-06-17T10:05:00Z"]}
          ],
          meta: %{
            observable_id: "HK.counter",
            warning_codes: [:corrected_range],
            revision_state: %{
              dependency: %{fingerprint: "nested-revision:abc"}
            }
          }
        }
      ]
    }

    assert [
             %{
               marker_id:
                 "telemetry-revision:corrected_range:nested-revision:abc:1781690400000:1781690700000",
               starts_at_ms: 1_781_690_400_000,
               ends_at_ms: 1_781_690_700_000,
               target_id: "nested-revision:abc",
               observable_id: "HK.counter"
             }
           ] = TimeSeriesTelemetryRevisionMarkers.range_markers(placement_frames)
  end

  test "range_markers ignores unsupported frames and incomplete ranges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{source: :events, shape: :events, meta: %{warning_codes: [:corrected_range]}},
        %Frame{
          source: :telemetry,
          shape: :wide,
          fields: [%Field{name: "time", kind: :time, values: []}],
          meta: %{warning_codes: [:corrected_range]}
        },
        %Frame{
          source: :telemetry,
          shape: :wide,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 10:00:00Z]]}
          ],
          meta: %{warning_codes: [:source_unavailable]}
        }
      ]
    }

    assert TimeSeriesTelemetryRevisionMarkers.range_markers(placement_frames) == []
    assert TimeSeriesTelemetryRevisionMarkers.range_markers(nil) == []
  end
end
