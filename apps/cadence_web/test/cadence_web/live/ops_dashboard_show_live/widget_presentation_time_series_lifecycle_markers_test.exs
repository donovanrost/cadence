defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationTimeSeriesLifecycleMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "time-series event markers include telemetry revision decisions" do
    placement_frames = %PlacementFrames{
      overlays: %{
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-22 12:10:00Z]]},
              %Field{name: "category", kind: :enum, values: [:telemetry_revision]},
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
                requested_dataset: "mission_events"
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
        ]
      }
    }

    widget = %RenderWidget{type: :time_series}

    [marker] = WidgetPresentation.event_markers(placement_frames, widget)

    assert marker.marker_type == "telemetry_revision_decision"
    assert marker.marker_id == "telemetry-revision-decision:decision-event-1:1782130200000"
    assert marker.timestamp_ms == 1_782_130_200_000
    assert marker.link_id == "telemetry_revision_decision_event:decision-event-1:events-request-1"
    assert marker.data_link_target == "telemetry_revision_decision_event"
    assert marker.data_link_target_id == "decision-event-1"
    assert marker.target == "telemetry_revision"
    assert marker.target_id == "identity-1"
    assert marker.telemetry_revision_decision_event_id == "decision-event-1"
    assert marker.observation_identity_id == "identity-1"
    assert marker.source_request_id == "events-request-1"
    assert marker.logical_source == "telemetry"
    assert marker.data_source_id == "flight-questdb"
    assert marker.source_binding_id == "flight-telemetry"
    assert marker.dataset == "mission_events"
    assert marker.realm == "flight"
    assert marker.observable_id == "HK.counter"
    assert marker.point_id == "HK.counter"
    assert marker.spacecraft_id == "sc-1"
    assert marker.time_mode == "archive"
    assert marker.time_axis == "occurred_at"
    assert marker.requested_realm == "flight"
    assert marker.requested_data_view == "canonical"
    assert marker.requested_data_source_id == "events-projection"
    assert marker.requested_source_binding_id == "events-binding"
    assert marker.requested_dataset == "mission_events"
    assert marker.event_kind == "mark_canonical"
    assert marker.severity == "info"
    assert marker.title == "HK.counter revision canonical"
    assert marker.decision_reason == "operator_selected_corrected_value"
    assert marker.actor_id == "ops-1"
    assert marker.actor_kind == "operator"
    assert marker.previous_validity_state == "conflict"
    assert marker.new_validity_state == "canonical"
    assert marker.previous_canonical_revision == 1
    assert marker.new_canonical_revision == 2
    assert marker.label == "Revision mark_canonical / HK.counter / identity-1"
  end

  test "time-series event markers include telemetry backfill lifecycle events" do
    placement_frames = %PlacementFrames{
      overlays: %{
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-22 12:21:00Z]]},
              %Field{name: "category", kind: :enum, values: [:telemetry_backfill]},
              %Field{name: "kind", kind: :enum, values: [:backfill_completed]},
              %Field{name: "severity", kind: :enum, values: [:info]},
              %Field{name: "title", kind: :string, values: ["HK.counter backfill completed"]},
              %Field{name: "source_record_id", kind: :string, values: ["backfill-event-1"]},
              %Field{name: "backfill_run_id", kind: :string, values: ["backfill-run-1"]},
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
              %Field{name: "authority", kind: :enum, values: [:authoritative]},
              %Field{name: "reason", kind: :enum, values: [:operator_backfill]},
              %Field{name: "actor_id", kind: :string, values: ["ops-1"]},
              %Field{name: "actor_kind", kind: :enum, values: ["operator"]}
            ],
            meta: %{
              family: :telemetry_backfill,
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
                  link_id: "telemetry_backfill_lifecycle_event:backfill-event-1:events-request-1",
                  label: "Telemetry backfill lifecycle event",
                  target: :telemetry_backfill_lifecycle_event,
                  target_id: "backfill-event-1",
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

    assert marker.marker_type == "telemetry_backfill_lifecycle"
    assert marker.marker_id == "telemetry-backfill-lifecycle:backfill-event-1:1782126000000"
    assert marker.timestamp_ms == 1_782_130_860_000
    assert marker.starts_at_ms == 1_782_126_000_000
    assert marker.ends_at_ms == 1_782_129_600_000

    assert marker.link_id ==
             "telemetry_backfill_lifecycle_event:backfill-event-1:events-request-1"

    assert marker.data_link_target == "telemetry_backfill_lifecycle_event"
    assert marker.data_link_target_id == "backfill-event-1"
    assert marker.target == "telemetry_backfill"
    assert marker.target_id == "backfill-run-1"
    assert marker.telemetry_backfill_lifecycle_event_id == "backfill-event-1"
    assert marker.backfill_run_id == "backfill-run-1"
    assert marker.source_request_id == "events-request-1"
    assert marker.logical_source == "telemetry"
    assert marker.data_source_id == "flight-questdb"
    assert marker.source_binding_id == "flight-telemetry"
    assert marker.dataset == "mission_events"
    assert marker.realm == "flight"
    assert marker.observable_id == "HK.counter"
    assert marker.point_id == "HK.counter"
    assert marker.spacecraft_id == "sc-1"
    assert marker.time_mode == "archive"
    assert marker.time_axis == "occurred_at"
    assert marker.requested_realm == "flight"
    assert marker.requested_data_view == "canonical"
    assert marker.requested_data_source_id == "events-projection"
    assert marker.requested_source_binding_id == "events-binding"
    assert marker.requested_dataset == "mission_events"
    assert marker.event_kind == "backfill_completed"
    assert marker.severity == "info"
    assert marker.title == "HK.counter backfill completed"
    assert marker.reason == "operator_backfill"
    assert marker.authority == "authoritative"
    assert marker.sample_count == 42
    assert marker.source_from_ms == 1_782_126_000_000
    assert marker.source_to_ms == 1_782_129_600_000
    assert marker.receipt_from_ms == 1_782_130_200_000
    assert marker.receipt_to_ms == 1_782_130_800_000
    assert marker.actor_id == "ops-1"
    assert marker.actor_kind == "operator"
    assert marker.revision_state == "backfill"
    assert marker.label == "Backfill completed / HK.counter / backfill-run-1"
  end
end
