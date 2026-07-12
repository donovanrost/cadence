defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationTimelineTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "event timeline presenter renders event and interval frames" do
    placement_frames = %PlacementFrames{
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
        },
        %Frame{
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
      ]
    }

    assert %{
             kind: :event_timeline,
             engine_backed?: true,
             rows: [
               %{
                 category: :contacts,
                 title: "DSS-14 contact",
                 occurred_at: ~U[2026-06-17 12:00:00Z],
                 starts_at: ~U[2026-06-17 12:00:00Z],
                 ends_at: ~U[2026-06-17 12:10:00Z],
                 source_record_id: "contact-1",
                 links: [%{target: :contact, target_id: "contact-1"}]
               },
               %{
                 category: :mission_timeline,
                 kind: :operator_note,
                 severity: :info,
                 title: "AOS confirmed",
                 occurred_at: ~U[2026-06-17 12:05:00Z],
                 source_record_id: "mission-event-1",
                 links: [%{target: :mission_event, target_id: "mission-event-1"}]
               }
             ]
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :event_timeline,
               binding: %{source: :events, mode: :context, point_id: nil, point_ids: []}
             })
  end

  test "state timeline presenter renders limit event-history frames as state segments" do
    placement_frames = %PlacementFrames{
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
            %Field{
              name: "limit_definition_id",
              kind: :string,
              values: ["limit-def-1", "limit-def-1"]
            },
            %Field{name: "limit_definition_version", kind: :number, values: [1, 1]},
            %Field{name: "normalized_state", kind: :enum, values: [:green, :red]},
            %Field{name: "limit_state", kind: :enum, values: [:green, :red_high]},
            %Field{name: "violation", kind: :boolean, values: [false, true]}
          ],
          meta: %{
            observable_id: "HK.battery_voltage",
            point_id: "HK.battery_voltage",
            links: [
              %DataLink{
                link_id: "point:HK.battery_voltage",
                target: :telemetry_point,
                target_id: "HK.battery_voltage",
                label: "Telemetry point"
              },
              %DataLink{
                link_id: "limit-event:limit-event-1",
                target: :limit_event,
                target_id: "limit-event-1",
                label: "Limit event"
              },
              %DataLink{
                link_id: "sample:sample-1",
                target: :telemetry_sample,
                target_id: "sample-1",
                label: "Telemetry sample"
              },
              %DataLink{
                link_id: "limit-event:limit-event-2",
                target: :limit_event,
                target_id: "limit-event-2",
                label: "Limit event"
              },
              %DataLink{
                link_id: "sample:sample-2",
                target: :telemetry_sample,
                target_id: "sample-2",
                label: "Telemetry sample"
              },
              %DataLink{
                link_id: "limit-definition:limit-def-1",
                target: :limit_definition,
                target_id: "limit-def-1",
                label: "Limit definition"
              }
            ]
          }
        }
      ]
    }

    assert %{
             kind: :state_timeline,
             engine_backed?: true,
             rows: [
               %{
                 observable_id: "HK.battery_voltage",
                 source: :limits,
                 normalized_state: :green,
                 limit_state: :green,
                 starts_at: ~U[2026-06-17 12:00:00Z],
                 ends_at: ~U[2026-06-17 12:05:00Z],
                 limit_event_id: "limit-event-1",
                 sample_id: "sample-1",
                 limit_definition_id: "limit-def-1",
                 links: [
                   %{target: :limit_event, target_id: "limit-event-1"},
                   %{target: :limit_definition, target_id: "limit-def-1"},
                   %{target: :telemetry_sample, target_id: "sample-1"},
                   %{target: :telemetry_point, target_id: "HK.battery_voltage"}
                 ]
               },
               %{
                 normalized_state: :red,
                 limit_state: :red_high,
                 starts_at: ~U[2026-06-17 12:05:00Z],
                 ends_at: nil,
                 violation?: true,
                 limit_event_id: "limit-event-2",
                 sample_id: "sample-2"
               }
             ]
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :state_timeline,
               binding: %{
                 source: :limits,
                 mode: :context,
                 point_id: "HK.battery_voltage",
                 point_ids: ["HK.battery_voltage"]
               }
             })
  end

  test "state timeline presenter renders operational observable event frames as state segments" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :events,
          fields: [
            %Field{
              name: "time",
              kind: :time,
              values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:04:00Z]]
            },
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["contacts.phase", "contacts.phase"]
            },
            %Field{name: "resource_id", kind: :string, values: ["contact-1", "contact-1-run"]},
            %Field{name: "lane_id", kind: :string, values: ["contact-1", "contact-1"]},
            %Field{
              name: "label",
              kind: :string,
              values: ["scheduled / contact-1", "realized / contact-1-run"]
            },
            %Field{name: "scope_kind", kind: :enum, values: [:contact, :contact]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1", "contact-1-run"]},
            %Field{name: "contact_kind", kind: :enum, values: [:scheduled, :realized]},
            %Field{name: "phase", kind: :enum, values: [:scheduled, :active]},
            %Field{name: "normalized_state", kind: :enum, values: [:scheduled, :active]}
          ],
          meta: %{
            observable_id: "contacts.phase",
            links: [
              %DataLink{
                link_id: "contact:contact-1",
                target: :contact,
                target_id: "contact-1",
                label: "Contact"
              },
              %DataLink{
                link_id: "contact:contact-1-run",
                target: :contact,
                target_id: "contact-1-run",
                label: "Contact"
              }
            ]
          }
        }
      ]
    }

    assert %{
             kind: :state_timeline,
             engine_backed?: true,
             lanes: [
               %{
                 lane_key: "operational_observables:contacts.phase:contact-1",
                 label: "contact-1",
                 source: :operational_observables,
                 observable_id: "contacts.phase",
                 rows: [
                   %{normalized_state: :scheduled},
                   %{normalized_state: :active}
                 ]
               }
             ],
             rows: [
               %{
                 observable_id: "contacts.phase",
                 label: "scheduled / contact-1",
                 source: :operational_observables,
                 status_policy: :contact_phase,
                 lane_key: "operational_observables:contacts.phase:contact-1",
                 lane_label: "contact-1",
                 normalized_state: :scheduled,
                 starts_at: ~U[2026-06-17 12:00:00Z],
                 ends_at: ~U[2026-06-17 12:04:00Z],
                 resource_id: "contact-1",
                 contact_id: "contact-1",
                 sample_id: "contact-1",
                 links: [%{target: :contact, target_id: "contact-1"}]
               },
               %{
                 label: "realized / contact-1-run",
                 lane_key: "operational_observables:contacts.phase:contact-1",
                 normalized_state: :active,
                 starts_at: ~U[2026-06-17 12:04:00Z],
                 ends_at: nil,
                 contact_id: "contact-1-run",
                 links: [%{target: :contact, target_id: "contact-1-run"}]
               }
             ]
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :state_timeline,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "contacts.phase",
                 point_ids: ["contacts.phase"]
               }
             })
  end

  test "state timeline presenter closes segments independently per lane" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :events,
          fields: [
            %Field{
              name: "time",
              kind: :time,
              values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:02:00Z]]
            },
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["contacts.phase", "contacts.phase"]
            },
            %Field{name: "resource_id", kind: :string, values: ["contact-1", "contact-2"]},
            %Field{name: "lane_id", kind: :string, values: ["contact-1", "contact-2"]},
            %Field{name: "label", kind: :string, values: ["contact-1", "contact-2"]},
            %Field{name: "scope_kind", kind: :enum, values: [:contact, :contact]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1", "contact-2"]},
            %Field{name: "phase", kind: :enum, values: [:scheduled, :active]},
            %Field{name: "normalized_state", kind: :enum, values: [:scheduled, :active]}
          ],
          meta: %{observable_id: "contacts.phase", links: []}
        }
      ]
    }

    assert %{
             lanes: [
               %{lane_key: "operational_observables:contacts.phase:contact-1", rows: [first]},
               %{lane_key: "operational_observables:contacts.phase:contact-2", rows: [second]}
             ],
             rows: [%{ends_at: nil}, %{ends_at: nil}]
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :state_timeline,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "contacts.phase",
                 point_ids: ["contacts.phase"]
               }
             })

    assert first.ends_at == nil
    assert second.ends_at == nil
  end
end
