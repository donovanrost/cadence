defmodule CadenceWeb.OpsDashboardShowLive.ChartAppendsTest do
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

  test "push sends typed limit and event marker buckets" do
    placement_frames = %PlacementFrames{
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
        limits: [
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
        ],
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
      }
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        dashboard_render_items: [
          %RenderItem{placement_id: "placement-1", widget: %RenderWidget{type: :time_series}}
        ],
        dashboard_engine_result: %DashboardResolveResult{
          frames_by_placement: %{"placement-1" => placement_frames}
        }
      }
    }

    assert %Phoenix.LiveView.Socket{
             private: %{
               live_temp: %{
                 push_events: [
                   [
                     "tlm:append",
                     %{
                       "series" => %{
                         "placement-1" => %{
                           version: 1,
                           series: [
                             %{id: "counter_value", points: [[1_781_697_600_000, 7, _metadata]]}
                           ]
                         }
                       },
                       "markers" => %{
                         "placement-1" => %{
                           limit_markers: [%{limit_event_id: "limit-event-red"}],
                           event_markers: [%{mission_event_id: "mission-event-1"}]
                         }
                       }
                     }
                   ]
                 ]
               }
             }
           } = ChartAppends.push(socket, %{})
  end

  test "push sends recomputed limit analysis marker metadata" do
    current_frames =
      chart_append_placement_frames(
        limits: recomputed_limit_frames(),
        events: []
      )

    widget = %RenderWidget{type: :time_series}

    assert %Phoenix.LiveView.Socket{
             private: %{
               live_temp: %{
                 push_events: [
                   [
                     "tlm:append",
                     %{
                       "markers" => %{
                         "placement-1" => %{
                           limit_markers: [
                             %{
                               marker_type: "limit_analysis",
                               semantics_mode: "recomputed",
                               analysis_basis: "recomputed_analysis",
                               synthetic_limit_analysis: true,
                               sample_id: "sample-1",
                               normalized_state: "yellow"
                             }
                           ]
                         }
                       }
                     }
                   ]
                 ]
               }
             }
           } =
             ChartAppends.push(
               chart_append_socket(current_frames, widget),
               %{"placement-1" => %{sample: %{sample_id: "sample-1"}}},
               %{}
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
        }
      }
    }
  end

  defp chart_append_placement_frames(opts) do
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

  defp recomputed_limit_frames do
    [
      %Frame{
        source: :limits,
        shape: :events,
        fields: [
          %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
          %Field{name: "sample_id", kind: :string, values: ["sample-1"]},
          %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
          %Field{name: "limit_state", kind: :enum, values: [:yellow_high]},
          %Field{name: "violation", kind: :boolean, values: [true]}
        ],
        meta: %{
          semantics_mode: :recomputed,
          analysis_basis: :recomputed_analysis,
          synthetic_limit_analysis?: true,
          links: [
            %{
              "link_id" => "sample-link-1",
              "target" => "telemetry_sample",
              "target_id" => "sample-1",
              "label" => "Telemetry sample"
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
