defmodule CadenceWeb.OpsDashboardShowLive.TimelineWidgetDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimelineWidgetData

  test "renders state timeline rows and lanes with lifecycle" do
    placement_frames = state_timeline_frames()

    assert %{
             kind: :state_timeline,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :ready,
             rows: [
               %{normalized_state: :green, ends_at: ~U[2026-06-17 12:05:00Z]},
               %{normalized_state: :red, ends_at: nil}
             ],
             lanes: [
               %{
                 lane_key: "limits:HK.battery_voltage",
                 rows: [%{normalized_state: :green}, %{normalized_state: :red}]
               }
             ]
           } = TimelineWidgetData.state_timeline(placement_frames)
  end

  test "renders event timeline rows with placement data management" do
    placement_frames = event_timeline_frames()

    assert %{
             kind: :event_timeline,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :ready,
             rows: [
               %{
                 category: :mission_timeline,
                 kind: :operator_note,
                 severity: :info,
                 title: "AOS confirmed",
                 source_record_id: "mission-event-1"
               }
             ]
           } = TimelineWidgetData.event_timeline(placement_frames)
  end

  test "event timeline aggregates row data-management workflow badges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :events,
          shape: :events,
          fields: [
            %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
            %Field{name: "category", kind: :enum, values: [:telemetry_backfill]},
            %Field{name: "kind", kind: :enum, values: [:backfill_started]},
            %Field{name: "severity", kind: :enum, values: [:info]},
            %Field{name: "title", kind: :string, values: ["HK.counter backfill started"]},
            %Field{name: "source_record_id", kind: :string, values: ["backfill-event-1"]}
          ],
          meta: %{family: :telemetry_backfill}
        }
      ]
    }

    assert %{
             data_management: %{
               badges: [
                 %{
                   kind: :historical_workflow,
                   value: "backfill_started",
                   code: "backfill_started"
                 }
               ]
             }
           } = TimelineWidgetData.event_timeline(placement_frames)
  end

  test "empty timeline widgets retain no-data lifecycle" do
    placement_frames = %PlacementFrames{primary: []}

    assert %{
             kind: :state_timeline,
             rows: [],
             lifecycle_state: :no_data,
             engine_backed?: true
           } = TimelineWidgetData.state_timeline(placement_frames)

    assert %{
             kind: :event_timeline,
             rows: [],
             lifecycle_state: :no_data,
             engine_backed?: true
           } = TimelineWidgetData.event_timeline(placement_frames)
  end

  defp state_timeline_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :limits,
          shape: :events,
          fields: [
            %Field{
              name: "time",
              kind: :time,
              values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:05:00Z]]
            },
            %Field{
              name: "limit_event_id",
              kind: :string,
              values: ["limit-event-1", "limit-event-2"]
            },
            %Field{name: "sample_id", kind: :string, values: ["sample-1", "sample-2"]},
            %Field{name: "normalized_state", kind: :enum, values: [:green, :red]},
            %Field{name: "limit_state", kind: :enum, values: [:green, :red_high]},
            %Field{name: "violation", kind: :boolean, values: [false, true]}
          ],
          meta: %{observable_id: "HK.battery_voltage"}
        }
      ]
    }
  end

  defp event_timeline_frames do
    %PlacementFrames{
      primary: [
        %Frame{
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
      ]
    }
  end
end
