defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesContactIntervalMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesContactIntervalMarkers

  test "interval_markers projects contact interval frames" do
    frame = %Frame{
      source: :events,
      shape: :intervals,
      fields: [
        %Field{name: "starts_at", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
        %Field{name: "ends_at", kind: :time, values: [~U[2026-06-17 12:10:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:scheduled]},
        %Field{name: "status", kind: :enum, values: [:active]},
        %Field{name: "label", kind: :string, values: ["DSS-14 contact"]},
        %Field{name: "contact_id", kind: :string, values: ["contact-1"]}
      ],
      meta: %{
        family: :contacts,
        links: [
          %DataLink{
            link_id: "contact:contact-1",
            target: :contact,
            target_id: "contact-1",
            label: "Contact"
          }
        ]
      }
    }

    assert TimeSeriesContactIntervalMarkers.event_frame?(frame)

    assert [
             %{
               marker_type: "contact_interval",
               starts_at_ms: 1_781_697_600_000,
               ends_at_ms: 1_781_698_200_000,
               link_id: "contact:contact-1",
               target: "contact",
               target_id: "contact-1",
               contact_id: "contact-1",
               contact_kind: "scheduled",
               status: "active",
               label: "DSS-14 contact"
             }
           ] = TimeSeriesContactIntervalMarkers.interval_markers(frame)
  end

  test "interval_markers falls back to link label and target contact id" do
    frame = %Frame{
      source: :events,
      shape: :intervals,
      fields: [
        %Field{name: "starts_at", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
        %Field{name: "kind", kind: :enum, values: [:realized]},
        %Field{name: "status", kind: :enum, values: [:active]}
      ],
      meta: %{
        links: [
          %{
            "link_id" => "contact:realized-contact-1",
            "target" => "contact",
            "target_id" => "realized-contact-1",
            "label" => "Realized contact"
          }
        ]
      }
    }

    assert [
             %{
               target_id: "realized-contact-1",
               contact_id: "realized-contact-1",
               contact_kind: "realized",
               status: "active",
               label: "Realized contact"
             }
           ] = TimeSeriesContactIntervalMarkers.interval_markers(frame)
  end

  test "interval_markers ignores incomplete or unrelated frames" do
    unrelated_frame = %Frame{source: :events, shape: :events, fields: [], meta: %{}}

    incomplete_frame = %Frame{
      source: :events,
      shape: :intervals,
      fields: [
        %Field{name: "starts_at", kind: :string, values: ["2026-06-17T12:00:00Z"]}
      ],
      meta: %{links: [%{"target" => "contact", "target_id" => "contact-1"}]}
    }

    refute TimeSeriesContactIntervalMarkers.event_frame?(unrelated_frame)
    assert TimeSeriesContactIntervalMarkers.interval_markers(incomplete_frame) == []
    assert TimeSeriesContactIntervalMarkers.interval_markers(nil) == []
  end
end
