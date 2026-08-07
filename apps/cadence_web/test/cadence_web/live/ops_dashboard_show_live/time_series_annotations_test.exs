defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesAnnotationsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Annotation, AnnotationSpan, DataLink, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesAnnotations

  test "serializes generic annotation geometry, presentation hints, and evidence context" do
    placement_frames = %PlacementFrames{
      annotations: [
        %Annotation{
          annotation_id: "cadence.contacts:scheduled_contact:contact-1",
          provider_id: "cadence.contacts",
          layer_id: "mission-contacts",
          kind: "contact_interval",
          span: %AnnotationSpan{
            kind: :interval,
            starts_at: ~U[2026-06-17 12:01:00Z],
            ends_at: ~U[2026-06-17 12:05:00Z]
          },
          title: "DSS-14 pass",
          text: "Scheduled contact",
          tags: ["contact", "scheduled_contact"],
          severity: :info,
          style: %{primitive: :rail, color: "cyan", lane: "operations", glyph: "CONTACT"},
          link: %DataLink{
            link_id: "contact:contact-1",
            label: "Open contact",
            target: :contact,
            target_id: "contact-1",
            source: :annotation
          },
          provenance: %{
            source_request_context: %{
              source_request_id: "events-request-1",
              logical_source: :events,
              requested_realm: :flight,
              requested_data_view: :canonical,
              requested_data_source_id: "managed-events",
              requested_source_binding_id: "events-flight",
              time_mode: :archive,
              time_axis: :occurred_at
            }
          },
          metadata: %{contact_id: "contact-1"}
        }
      ]
    }

    assert [annotation] = TimeSeriesAnnotations.annotations(placement_frames)

    assert annotation == %{
             annotation_id: "cadence.contacts:scheduled_contact:contact-1",
             provider_id: "cadence.contacts",
             layer_id: "mission-contacts",
             annotation_kind: "contact_interval",
             geometry: "interval",
             starts_at_ms: 1_781_697_660_000,
             ends_at_ms: 1_781_697_900_000,
             title: "DSS-14 pass",
             text: "Scheduled contact",
             tags: ["contact", "scheduled_contact"],
             severity: "info",
             primitive: "rail",
             color: "cyan",
             lane: "operations",
             glyph: "CONTACT",
             link_id: "contact:contact-1",
             target: :contact,
             target_id: "contact-1",
             source_request_id: "events-request-1",
             logical_source: :events,
             requested_realm: :flight,
             requested_data_view: :canonical,
             requested_data_source_id: "managed-events",
             requested_source_binding_id: "events-flight",
             time_mode: :archive,
             time_axis: :occurred_at,
             metadata: %{contact_id: "contact-1"}
           }
  end
end
