defmodule Cadence.Dashboards.Sources.Events.AnnotationsTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{Annotation, AnnotationSpan, DataLink, Field, Frame}
  alias Cadence.Dashboards.Sources.Events.Annotations

  test "coalesces a material source outage and recovery into one generic interval" do
    frame =
      source_health_frame([
        source_health_event(
          "health-unavailable-1",
          ~U[2026-08-06 04:00:00Z],
          :unavailable,
          :healthy,
          :source_unavailable
        ),
        source_health_event(
          "health-recovered-1",
          ~U[2026-08-06 04:00:02Z],
          :healthy,
          :unavailable,
          :source_recovered
        )
      ])

    assert [
             %Annotation{
               annotation_id: "cadence.source-health:outage:health-unavailable-1",
               provider_id: "cadence.source-health",
               layer_id: "source-status",
               kind: "source_health_outage",
               span: %AnnotationSpan{
                 kind: :interval,
                 starts_at: ~U[2026-08-06 04:00:00Z],
                 ends_at: ~U[2026-08-06 04:00:02Z]
               },
               severity: :error,
               style: %{primitive: :rail, color: "red", lane: "data-quality", glyph: "SOURCE"},
               link: %DataLink{
                 target: :source_health_event,
                 target_id: "health-unavailable-1",
                 source: :annotation
               },
               metadata: %{
                 active?: false,
                 duration_ms: 2_000,
                 recovery_event_id: "health-recovered-1"
               }
             } = annotation
           ] = Annotations.from_frames([frame])

    assert annotation.metadata.logical_source == "limits"
    assert annotation.metadata.data_source_id == "managed-limits"
    assert annotation.provenance.source_event_id == "health-unavailable-1"
    assert annotation.provenance.recovery_event_id == "health-recovered-1"
  end

  test "suppresses transient recovered probes but retains an active outage" do
    transient_frame =
      source_health_frame([
        source_health_event(
          "health-unavailable-transient",
          ~U[2026-08-06 04:00:00.000000Z],
          :unavailable,
          :healthy,
          :source_unavailable
        ),
        source_health_event(
          "health-recovered-transient",
          ~U[2026-08-06 04:00:00.046000Z],
          :healthy,
          :unavailable,
          :source_recovered
        )
      ])

    assert Annotations.from_frames([transient_frame]) == []

    active_frame =
      source_health_frame([
        source_health_event(
          "health-degraded-active",
          ~U[2026-08-06 04:01:00Z],
          :degraded,
          :healthy,
          :source_degraded
        )
      ])

    assert [
             %Annotation{
               annotation_id: "cadence.source-health:outage:health-degraded-active",
               span: %AnnotationSpan{kind: :interval, ends_at: nil},
               severity: :warning,
               metadata: %{active?: true, duration_ms: nil}
             }
           ] = Annotations.from_frames([active_frame])
  end

  test "normalizes inconsistent contact end times at the domain adapter boundary" do
    frame =
      contact_frame([
        %{
          contact_id: "contact-active",
          starts_at: ~U[2026-08-07 01:00:00Z],
          ends_at: ~U[2026-08-06 23:00:00Z],
          kind: :realized_contact,
          status: :active,
          label: "Active contact",
          source_event_id: "contact-event-active"
        },
        %{
          contact_id: "contact-completed",
          starts_at: ~U[2026-08-07 02:00:00Z],
          ends_at: ~U[2026-08-06 22:00:00Z],
          kind: :realized_contact,
          status: :completed,
          label: "Completed contact",
          source_event_id: "contact-event-completed"
        }
      ])

    assert [active, completed] = Annotations.from_frame(frame)

    assert %Annotation{
             span: %AnnotationSpan{kind: :interval, ends_at: nil},
             metadata: %{span_normalization: "active_contact_end_ignored"}
           } = active

    assert %Annotation{
             span: %AnnotationSpan{kind: :point, ends_at: nil},
             metadata: %{span_normalization: "ends_before_start"}
           } = completed

    assert Annotation.valid?(active)
    assert Annotation.valid?(completed)
  end

  defp source_health_frame(events) do
    %Frame{
      frame_id: "events-request:source-health",
      source: :events,
      shape: :events,
      time_axis: :occurred_at,
      scope: %{primary: %{kind: :spacecraft, mode: :one, ids: ["spacecraft-1"]}},
      fields: [
        field("occurred_at", :time, events, :observed_at),
        field("source_record_id", :string, events, :source_event_id),
        field("source_health", :enum, events, :source_health),
        field("previous_source_health", :enum, events, :previous_source_health),
        field("reason", :enum, events, :reason),
        field("logical_source", :enum, events, :logical_source),
        field("data_source_id", :string, events, :data_source_id),
        field("source_binding_id", :string, events, :source_binding_id),
        field("realm", :enum, events, :realm),
        field("dataset", :string, events, :dataset)
      ],
      meta: %{
        family: :source_health,
        product: :source_health_transitions,
        projection: :data_source_health_events,
        source_request_id: "events-request",
        links: Enum.map(events, &source_health_link/1)
      }
    }
  end

  defp contact_frame(contacts) do
    %Frame{
      frame_id: "events-request:contacts",
      source: :events,
      shape: :intervals,
      time_axis: :occurred_at,
      scope: %{primary: %{kind: :spacecraft, mode: :one, ids: ["spacecraft-1"]}},
      fields: [
        field("starts_at", :time, contacts, :starts_at),
        field("ends_at", :time, contacts, :ends_at),
        field("kind", :enum, contacts, :kind),
        field("status", :enum, contacts, :status),
        field("label", :string, contacts, :label),
        field("contact_id", :string, contacts, :contact_id),
        field("source_event_id", :string, contacts, :source_event_id)
      ],
      meta: %{
        product: :contact_intervals,
        projection: :contacts,
        source_request_id: "events-request",
        links: []
      }
    }
  end

  defp source_health_event(id, observed_at, source_health, previous_source_health, reason) do
    %{
      source_event_id: id,
      observed_at: observed_at,
      source_health: source_health,
      previous_source_health: previous_source_health,
      reason: reason,
      logical_source: :limits,
      data_source_id: "managed-limits",
      source_binding_id: "flight-limits",
      realm: :flight,
      dataset: "telemetry_latest_limit_states"
    }
  end

  defp field(name, kind, events, key) do
    %Field{name: name, kind: kind, values: Enum.map(events, &Map.fetch!(&1, key))}
  end

  defp source_health_link(event) do
    %DataLink{
      link_id: "source_health_event:#{event.source_event_id}:events-request",
      label: "Source health event",
      target: :source_health_event,
      target_id: event.source_event_id,
      source: :frame
    }
  end
end
