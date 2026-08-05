defmodule CadenceWeb.OpsDashboardShowLive.ChartAppendsMarkerSnapshotsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveResult,
    DataLink,
    Field,
    Frame,
    PlacementFrames,
    RenderItem,
    RenderWidget
  }

  alias CadenceWeb.OpsDashboardShowLive.ChartAppends

  test "push sends marker-only payload when markers change without a new sample" do
    previous_frames = chart_append_placement_frames(events: [])

    current_frames =
      chart_append_placement_frames(
        events: [
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
      )

    widget = %RenderWidget{type: :time_series}

    previous_marker_snapshots =
      ChartAppends.marker_snapshots(%{
        dashboard_render_items: [%RenderItem{placement_id: "placement-1", widget: widget}],
        dashboard_engine_frames_by_placement: %{"placement-1" => previous_frames}
      })

    socket =
      chart_append_socket(current_frames, widget)

    assert %Phoenix.LiveView.Socket{
             private: %{
               live_temp: %{
                 push_events: [
                   [
                     "tlm:append",
                     %{
                       "series" => %{},
                       "markers" => %{
                         "placement-1" => %{
                           event_markers: [%{mission_event_id: "mission-event-1"}]
                         }
                       }
                     }
                   ]
                 ]
               }
             }
           } =
             ChartAppends.push(
               socket,
               %{"placement-1" => %{sample: %{sample_id: "sample-1"}}},
               previous_marker_snapshots
             )
  end

  test "push sends a live window heartbeat when samples and markers are unchanged" do
    current_frames = chart_append_placement_frames()
    widget = %RenderWidget{type: :time_series}

    previous_marker_snapshots =
      ChartAppends.marker_snapshots(%{
        dashboard_render_items: [%RenderItem{placement_id: "placement-1", widget: widget}],
        dashboard_engine_frames_by_placement: %{"placement-1" => current_frames}
      })

    assert %Phoenix.LiveView.Socket{
             private: %{
               live_temp: %{
                 push_events: [
                   [
                     "tlm:append",
                     %{
                       "series" => %{},
                       "window_end_ms" => window_end_ms,
                       "refresh_interval_ms" => 2_500
                     }
                   ]
                 ]
               }
             }
           } =
             ChartAppends.push(
               chart_append_socket(current_frames, widget),
               %{"placement-1" => %{sample: %{sample_id: "sample-1"}}},
               previous_marker_snapshots
             )

    assert is_integer(window_end_ms)
  end

  test "push does not send a heartbeat without time-series widgets" do
    current_frames = chart_append_placement_frames()
    widget = %RenderWidget{type: :value_tile}

    assert %Phoenix.LiveView.Socket{private: %{live_temp: %{}}} =
             ChartAppends.push(
               chart_append_socket(current_frames, widget),
               %{"placement-1" => %{sample: %{sample_id: "sample-1"}}}
             )
  end

  defp chart_append_socket(placement_frames, widget) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        dashboard_render_items: [
          %RenderItem{placement_id: "placement-1", widget: widget}
        ],
        dashboard_engine_result: %DashboardResolveResult{
          frames_by_placement: %{"placement-1" => placement_frames}
        },
        dashboard_live_refresh_ms: 2_500
      }
    }
  end

  defp chart_append_placement_frames(opts \\ []) do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "counter_value",
              kind: :number,
              values: [7],
              metadata: %{sample_ids: ["sample-1"]}
            }
          ]
        }
      ],
      overlays: %{
        limits: Keyword.get(opts, :limits, chart_append_limit_frames()),
        events: Keyword.get(opts, :events, chart_append_event_frames())
      }
    }
  end

  defp chart_append_limit_frames do
    [
      %Frame{
        source: :limits,
        shape: :events,
        fields: [
          %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
          %Field{name: "sample_id", kind: :string, values: ["sample-1"]},
          %Field{name: "normalized_state", kind: :enum, values: [:red]},
          %Field{name: "limit_state", kind: :enum, values: [:high_red]},
          %Field{name: "violation", kind: :boolean, values: [true]}
        ],
        meta: %{
          links: [
            %{
              "link_id" => "limit-link-red",
              "target" => "limit_event",
              "target_id" => "limit-event-red",
              "label" => "Limit event"
            }
          ]
        }
      }
    ]
  end

  defp chart_append_event_frames do
    [
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
  end
end
