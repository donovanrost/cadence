defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesMissionEventMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesMissionEventMarkers

  test "event_markers projects mission event frames" do
    frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
        %Field{name: "category", kind: :enum, values: [:mission_timeline]},
        %Field{name: "kind", kind: :enum, values: [:operator_note]},
        %Field{name: "severity", kind: :enum, values: [:info]},
        %Field{name: "title", kind: :string, values: ["AOS confirmed"]},
        %Field{name: "source_record_id", kind: :string, values: ["mission-event-1"]}
      ],
      meta: %{
        family: :mission_timeline,
        links: [
          %DataLink{
            link_id: "mission-event:mission-event-1",
            target: :mission_event,
            target_id: "mission-event-1",
            label: "Mission event"
          }
        ]
      }
    }

    assert [
             %{
               marker_type: "mission_event",
               timestamp_ms: 1_781_697_900_000,
               link_id: "mission-event:mission-event-1",
               target: "mission_event",
               target_id: "mission-event-1",
               mission_event_id: "mission-event-1",
               category: "mission_timeline",
               event_kind: "operator_note",
               severity: "info",
               title: "AOS confirmed",
               source_record_id: "mission-event-1"
             }
           ] = TimeSeriesMissionEventMarkers.event_markers(frame)
  end

  test "event_markers falls back to link label" do
    frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:limit_violation]}
      ],
      meta: %{
        links: [
          %{
            "link_id" => "mission-event:mission-event-2",
            "target" => "mission_event",
            "target_id" => "mission-event-2",
            "label" => "Battery limit violation"
          }
        ]
      }
    }

    assert [
             %{
               target_id: "mission-event-2",
               mission_event_id: "mission-event-2",
               event_kind: "limit_violation",
               title: "Battery limit violation"
             }
           ] = TimeSeriesMissionEventMarkers.event_markers(frame)
  end

  test "event_markers ignores incomplete or unrelated frames" do
    interval_frame = %Frame{source: :events, shape: :intervals, fields: [], meta: %{}}

    incomplete_frame = %Frame{
      source: :events,
      shape: :events,
      fields: [
        %Field{name: "occurred_at", kind: :string, values: ["2026-06-17T12:05:00Z"]}
      ],
      meta: %{links: [%{"target" => "mission_event", "target_id" => "mission-event-1"}]}
    }

    assert TimeSeriesMissionEventMarkers.event_markers(interval_frame) == []
    assert TimeSeriesMissionEventMarkers.event_markers(incomplete_frame) == []
    assert TimeSeriesMissionEventMarkers.event_markers(nil) == []
  end
end
