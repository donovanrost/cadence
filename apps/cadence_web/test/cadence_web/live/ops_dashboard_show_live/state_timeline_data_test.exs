defmodule CadenceWeb.OpsDashboardShowLive.StateTimelineDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.StateTimelineData

  test "rows renders limit event-history frames as closed state segments" do
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
            data_view: :canonical,
            links: [
              %DataLink{
                link_id: "point:HK.battery_voltage",
                target: :telemetry_point,
                target_id: "HK.battery_voltage"
              },
              %DataLink{
                link_id: "limit-event:limit-event-1",
                target: :limit_event,
                target_id: "limit-event-1"
              },
              %DataLink{
                link_id: "sample:sample-1",
                target: :telemetry_sample,
                target_id: "sample-1"
              },
              %DataLink{
                link_id: "limit-definition:limit-def-1",
                target: :limit_definition,
                target_id: "limit-def-1"
              }
            ]
          }
        }
      ]
    }

    assert [
             %{
               observable_id: "HK.battery_voltage",
               source: :limits,
               normalized_state: :green,
               limit_state: :green,
               starts_at: ~U[2026-06-17 12:00:00Z],
               ends_at: ~U[2026-06-17 12:05:00Z],
               limit_event_id: "limit-event-1",
               sample_id: "sample-1",
               links: [
                 %{target: :limit_event, target_id: "limit-event-1"},
                 %{target: :limit_definition, target_id: "limit-def-1"},
                 %{target: :telemetry_sample, target_id: "sample-1"},
                 %{target: :telemetry_point, target_id: "HK.battery_voltage"}
               ],
               data_management: %{data_view: "canonical"}
             },
             %{
               normalized_state: :red,
               limit_state: :red_high,
               starts_at: ~U[2026-06-17 12:05:00Z],
               ends_at: nil,
               violation?: true,
               limit_event_id: "limit-event-2"
             }
           ] =
             StateTimelineData.rows(placement_frames)
  end

  test "lanes groups operational observable rows by lane key" do
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
              %DataLink{link_id: "contact:contact-1", target: :contact, target_id: "contact-1"},
              %DataLink{
                link_id: "contact:contact-1-run",
                target: :contact,
                target_id: "contact-1-run"
              }
            ]
          }
        }
      ]
    }

    rows = StateTimelineData.rows(placement_frames)

    assert [
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
           ] = StateTimelineData.lanes(rows)
  end

  test "rows attach operational resource links to connection state timeline rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :events,
          scope: %{primary: %{kind: :transport, ids: ["transport-alpha", "transport-beta"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.connection_state"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "lane_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "link_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{
              name: "source_event_id",
              kind: :string,
              values: ["operational-event-connection-alpha"]
            },
            %Field{name: "connection_state", kind: :enum, values: [:connected]},
            %Field{name: "normalized_state", kind: :enum, values: [:connected]}
          ],
          meta: %{
            observable_id: "comms.transport.connection_state",
            links: [
              %DataLink{
                link_id: "transport:transport-alpha:ops-history-1",
                target: :transport,
                target_id: "transport-alpha"
              },
              %DataLink{
                link_id: "source_endpoint:endpoint-alpha:ops-history-1",
                target: :source_endpoint,
                target_id: "endpoint-alpha"
              },
              %DataLink{
                link_id: "ground_station:dss-14:ops-history-1",
                target: :ground_station,
                target_id: "dss-14"
              },
              %DataLink{
                link_id: "operational_event:operational-event-connection-alpha:ops-history-1",
                target: :operational_event,
                target_id: "operational-event-connection-alpha"
              },
              %DataLink{
                link_id: "transport:transport-beta:ops-history-1",
                target: :transport,
                target_id: "transport-beta"
              }
            ]
          }
        }
      ]
    }

    assert [
             %{
               observable_id: "comms.transport.connection_state",
               source: :operational_observables,
               status_policy: :connection_state,
               normalized_state: :connected,
               resource_id: "transport-alpha",
               link_id: "link-alpha",
               transport_id: "transport-alpha",
               source_endpoint_id: "endpoint-alpha",
               ground_station_id: "dss-14",
               source_event_id: "operational-event-connection-alpha",
               query_scope_kind: "transport",
               query_scope_id: "transport-alpha",
               query_scope_ids: ["transport-alpha", "transport-beta"],
               links: [
                 %{target: :operational_event, target_id: "operational-event-connection-alpha"},
                 %{target: :transport, target_id: "transport-alpha"},
                 %{target: :source_endpoint, target_id: "endpoint-alpha"},
                 %{target: :ground_station, target_id: "dss-14"}
               ]
             }
           ] = StateTimelineData.rows(placement_frames)
  end

  test "rows render generic operational state timeline rows from state fields" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :events,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "ends_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
            %Field{name: "observable_id", kind: :string, values: ["link.rf_lock_state"]},
            %Field{name: "resource_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "lane_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "label", kind: :string, values: ["RF lock / link-alpha"]},
            %Field{name: "scope_kind", kind: :enum, values: [:link]},
            %Field{name: "link_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:rf_adapter]},
            %Field{name: "state", kind: :enum, values: [:locked]}
          ],
          meta: %{
            observable_id: "link.rf_lock_state",
            links: [
              %DataLink{
                link_id: "transport:transport-alpha:ops-history-2",
                target: :transport,
                target_id: "transport-alpha"
              },
              %DataLink{
                link_id: "source_endpoint:endpoint-alpha:ops-history-2",
                target: :source_endpoint,
                target_id: "endpoint-alpha"
              },
              %DataLink{
                link_id: "ground_station:dss-14:ops-history-2",
                target: :ground_station,
                target_id: "dss-14"
              }
            ]
          }
        }
      ]
    }

    assert [
             %{
               observable_id: "link.rf_lock_state",
               source: :operational_observables,
               status_policy: :operational_state,
               normalized_state: :locked,
               ends_at: ~U[2026-06-17 12:05:00Z],
               lane_key: "operational_observables:link.rf_lock_state:link-alpha",
               resource_id: "link-alpha",
               link_id: "link-alpha",
               links: [
                 %{target: :transport, target_id: "transport-alpha"},
                 %{target: :source_endpoint, target_id: "endpoint-alpha"},
                 %{target: :ground_station, target_id: "dss-14"}
               ]
             }
           ] = StateTimelineData.rows(placement_frames)
  end
end
