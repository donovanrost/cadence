defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DataLink,
    Field,
    Frame,
    PlacementFrames,
    RenderWidget,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "status matrix presenter renders operational observable matrix rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "observable_id", kind: :string, values: ["contacts.phase"]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1"]},
            %Field{name: "contact_kind", kind: :enum, values: [:scheduled]},
            %Field{name: "phase", kind: :enum, values: [:active]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [300_000]}
          ],
          meta: %{
            observable_id: "contacts.phase",
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
             kind: :status_matrix,
             engine_backed?: true,
             rows: [
               %{
                 observable_id: "contacts.phase:contact-1",
                 label: "contacts.phase / scheduled / contact-1",
                 source: :operational_observables,
                 status_policy: :contact_phase,
                 contact_id: "contact-1",
                 contact_kind: :scheduled,
                 phase: :active,
                 value: :active,
                 sample_id: "contact-1",
                 quality_state: :scheduled,
                 normalized_state: :active,
                 links: [%{target: :contact, target_id: "contact-1"}]
               }
             ]
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :status_matrix,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "contacts.phase",
                 point_ids: ["contacts.phase"]
               }
             })
  end

  test "status matrix presenter renders mixed operational observable frames" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "observable_id", kind: :string, values: ["contacts.phase"]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1"]},
            %Field{name: "contact_kind", kind: :enum, values: [:scheduled]},
            %Field{name: "phase", kind: :enum, values: [:active]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [300_000]}
          ],
          meta: %{
            observable_id: "contacts.phase",
            supported_capability: :contacts_phase,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
            links: []
          }
        },
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.connection_state"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{name: "connection_state", kind: :enum, values: [:connected]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:03:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [2_000]}
          ],
          meta: %{
            observable_ids: ["comms.transport.connection_state"],
            supported_capability: :connection_state,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
            links: []
          }
        },
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["ingress.processing_latency_ms"]
            },
            %Field{name: "resource_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "label", kind: :string, values: ["Ingress latency / endpoint-alpha"]},
            %Field{name: "scope_kind", kind: :enum, values: [:source_endpoint]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "spacecraft_id", kind: :string, values: ["spacecraft-alpha"]},
            %Field{name: "value", kind: :number, values: [4.5]},
            %Field{name: "unit", kind: :string, values: ["ms"]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:06:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [2_000]},
            %Field{name: "error", kind: :boolean, values: [false]}
          ],
          meta: %{
            observable_ids: ["ingress.processing_latency_ms"],
            observable_id: "ingress.processing_latency_ms",
            supported_capability: :ingress_processing_latency,
            product_family: :runtime_ingress,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
            links: []
          }
        },
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.downlink_bitrate"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{name: "value", kind: :number, values: [12_500.5]},
            %Field{name: "unit", kind: :string, values: ["bit/s"]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:04:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [2_000]}
          ],
          meta: %{
            observable_ids: ["comms.transport.downlink_bitrate"],
            supported_capability: :transport_bitrate,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
            links: []
          }
        },
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "observable_id", kind: :string, values: ["commanding.queue_depth"]},
            %Field{name: "resource_id", kind: :string, values: ["mission-alpha"]},
            %Field{name: "label", kind: :string, values: ["Pending commands"]},
            %Field{name: "scope_kind", kind: :enum, values: [:mission]},
            %Field{name: "source_endpoint_id", kind: :string, values: [nil]},
            %Field{name: "value", kind: :number, values: [2]},
            %Field{name: "unit", kind: :string, values: ["commands"]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:05:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [2_000]}
          ],
          meta: %{
            observable_ids: ["commanding.queue_depth"],
            observable_id: "commanding.queue_depth",
            supported_capability: :command_queue_depth,
            product_family: :commanding,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
            links: []
          }
        }
      ]
    }

    assert %{kind: :status_matrix, engine_backed?: true, rows: rows} =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :status_matrix,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_ids: [
                   "contacts.phase",
                   "comms.transport.connection_state",
                   "comms.transport.downlink_bitrate",
                   "ingress.processing_latency_ms",
                   "commanding.queue_depth"
                 ]
               }
             })

    assert Enum.map(rows, & &1.observable_id) == [
             "contacts.phase:contact-1",
             "comms.transport.connection_state:transport-alpha",
             "ingress.processing_latency_ms:endpoint-alpha",
             "comms.transport.downlink_bitrate:transport-alpha",
             "commanding.queue_depth:mission-alpha"
           ]

    assert Enum.map(rows, & &1.status_policy) == [
             :contact_phase,
             :connection_state,
             :metric_value,
             :metric_value,
             :metric_value
           ]

    assert Enum.map(rows, & &1.frame_observable_id) == [
             "contacts.phase",
             "comms.transport.connection_state",
             "ingress.processing_latency_ms",
             "comms.transport.downlink_bitrate",
             "commanding.queue_depth"
           ]

    assert Enum.map(rows, & &1.product_family) == [
             :contacts_phase,
             :connection_state,
             :runtime_ingress,
             :transport_bitrate,
             :commanding
           ]

    assert Enum.map(rows, & &1.supported_capability) == [
             :contacts_phase,
             :connection_state,
             :ingress_processing_latency,
             :transport_bitrate,
             :command_queue_depth
           ]

    assert Enum.all?(rows, &(&1.source_request_id == "ops-latest-1"))
    assert Enum.all?(rows, &(&1.logical_source == :operational_observables))
    assert Enum.all?(rows, &(&1.realm == :flight))
    assert Enum.all?(rows, &(&1.data_source_id == "managed_operational_observables"))
    assert Enum.all?(rows, &(&1.source_binding_id == "default_flight_operational_observables"))
    assert Enum.all?(rows, &(&1.dataset == "operational_observables"))

    assert %{freshness_state: :fresh, age_ms: 2_000, stale?: false} =
             Enum.find(rows, &(&1.frame_observable_id == "ingress.processing_latency_ms"))

    assert %{freshness_state: :fresh, age_ms: 300_000, stale?: false} =
             Enum.find(rows, &(&1.frame_observable_id == "contacts.phase"))

    assert %{freshness_state: :fresh, age_ms: 2_000, stale?: false} =
             Enum.find(rows, &(&1.frame_observable_id == "comms.transport.connection_state"))

    assert %{freshness_state: :fresh, age_ms: 2_000, stale?: false} =
             Enum.find(rows, &(&1.frame_observable_id == "comms.transport.downlink_bitrate"))

    assert %{freshness_state: :fresh, age_ms: 2_000, stale?: false} =
             Enum.find(rows, &(&1.frame_observable_id == "commanding.queue_depth"))
  end

  test "data table presenter renders operational observable matrix rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "observable_id", kind: :string, values: ["contacts.phase"]},
            %Field{name: "contact_id", kind: :string, values: ["contact-1"]},
            %Field{name: "contact_kind", kind: :enum, values: [:scheduled]},
            %Field{name: "phase", kind: :enum, values: [:active]}
          ],
          meta: %{
            observable_id: "contacts.phase",
            supported_capability: :contacts_phase,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
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
             kind: :data_table,
             engine_backed?: true,
             rows: [
               %{
                 observable_id: "contacts.phase:contact-1",
                 frame_observable_id: "contacts.phase",
                 label: "contacts.phase / scheduled / contact-1",
                 source: :operational_observables,
                 status_policy: :contact_phase,
                 product_family: :contacts_phase,
                 supported_capability: :contacts_phase,
                 source_request_id: "ops-latest-1",
                 logical_source: :operational_observables,
                 realm: :flight,
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 dataset: "operational_observables",
                 value: :active,
                 sample_id: "contact-1",
                 quality_state: :scheduled,
                 normalized_state: :active,
                 links: [%{target: :contact, target_id: "contact-1"}]
               }
             ]
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :data_table,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "contacts.phase",
                 point_ids: ["contacts.phase"]
               }
             })
  end

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

  test "status matrix presenter renders connection state operational observable rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.connection_state"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{name: "connection_state", kind: :enum, values: [:connected]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:03:00Z]]}
          ],
          meta: %{observable_ids: ["comms.transport.connection_state"], links: []}
        }
      ]
    }

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             rows: [
               %{
                 observable_id: "comms.transport.connection_state:transport-alpha",
                 label: "Lab TCP",
                 source: :operational_observables,
                 status_policy: :connection_state,
                 resource_id: "transport-alpha",
                 scope_kind: :transport,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 connection_state: :connected,
                 adapter_key: :tcp_socket,
                 value: :connected,
                 sample_id: "transport-alpha",
                 receipt_time: ~U[2026-06-17 12:03:00Z],
                 quality_state: :tcp_socket,
                 normalized_state: :connected,
                 links: []
               }
             ]
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :status_matrix,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "comms.transport.connection_state",
                 point_ids: ["comms.transport.connection_state"]
               }
             })
  end

  test "value tile presenter renders operational metric rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.downlink_bitrate"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{name: "value", kind: :number, values: [12_500.5]},
            %Field{name: "unit", kind: :string, values: ["bit/s"]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:04:00Z]]}
          ],
          meta: %{
            observable_id: "comms.transport.downlink_bitrate",
            unit: "bit/s",
            links: []
          }
        }
      ]
    }

    assert %{
             kind: :point,
             engine_backed?: true,
             unit: "bit/s",
             label: "Lab TCP",
             lifecycle_state: :ready,
             lifecycle: %{state: :ready, severity: :ok},
             sample: %{
               sample_id: "transport-alpha",
               raw_value: 12_500.5,
               engineering_value: 12_500.5,
               receipt_time: ~U[2026-06-17 12:04:00Z],
               generation_time: ~U[2026-06-17 12:04:00Z],
               quality_state: :observed
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "comms.transport.downlink_bitrate",
                 point_ids: ["comms.transport.downlink_bitrate"]
               }
             })
  end

  test "status matrix presenter preserves no-data operational metric rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.downlink_bitrate"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{name: "value", kind: :number, values: [nil]},
            %Field{name: "unit", kind: :string, values: ["bit/s"]},
            %Field{name: "observed_at", kind: :time, values: [nil]}
          ],
          meta: %{observable_ids: ["comms.transport.downlink_bitrate"], links: []}
        }
      ]
    }

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             rows: [
               %{
                 observable_id: "comms.transport.downlink_bitrate:transport-alpha",
                 label: "Lab TCP",
                 source: :operational_observables,
                 status_policy: :metric_value,
                 resource_id: "transport-alpha",
                 scope_kind: :transport,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 unit: "bit/s",
                 value: nil,
                 sample_id: "transport-alpha",
                 receipt_time: nil,
                 quality_state: :no_data,
                 normalized_state: :no_data,
                 links: []
               }
             ],
             lifecycle_state: :no_data,
             lifecycle: %{state: :no_data, severity: :info, reason_codes: [:no_data]}
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :status_matrix,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "comms.transport.downlink_bitrate",
                 point_ids: ["comms.transport.downlink_bitrate"]
               }
             })
  end

  test "status matrix presenter marks stale operational runtime metric rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["ingress.processing_latency_ms"]
            },
            %Field{name: "resource_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "label", kind: :string, values: ["Ingress latency / endpoint-alpha"]},
            %Field{name: "scope_kind", kind: :enum, values: [:source_endpoint]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "value", kind: :number, values: [4.5]},
            %Field{name: "unit", kind: :string, values: ["ms"]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:06:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:stale]},
            %Field{name: "age_ms", kind: :number, values: [2_000]}
          ],
          meta: %{
            observable_ids: ["ingress.processing_latency_ms"],
            observable_id: "ingress.processing_latency_ms",
            supported_capability: :ingress_processing_latency,
            product_family: :runtime_ingress,
            warning_codes: [:stale_data],
            links: []
          }
        }
      ]
    }

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             rows: [
               %{
                 observable_id: "ingress.processing_latency_ms:endpoint-alpha",
                 frame_observable_id: "ingress.processing_latency_ms",
                 product_family: :runtime_ingress,
                 freshness_state: :stale,
                 age_ms: 2_000,
                 stale?: true
               }
             ],
             lifecycle_state: :stale,
             lifecycle: %{state: :stale, severity: :warning}
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :status_matrix,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "ingress.processing_latency_ms",
                 point_ids: ["ingress.processing_latency_ms"]
               }
             })
  end

  test "status matrix presenter marks stale operational connection rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.connection_state"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{name: "connection_state", kind: :enum, values: [:connected]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:03:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:stale]},
            %Field{name: "age_ms", kind: :number, values: [7_000]}
          ],
          meta: %{
            observable_ids: ["comms.transport.connection_state"],
            supported_capability: :connection_state,
            warning_codes: [:stale_data],
            links: []
          }
        }
      ]
    }

    assert %{
             kind: :status_matrix,
             engine_backed?: true,
             rows: [
               %{
                 observable_id: "comms.transport.connection_state:transport-alpha",
                 frame_observable_id: "comms.transport.connection_state",
                 freshness_state: :stale,
                 age_ms: 7_000,
                 stale?: true
               }
             ],
             lifecycle_state: :stale,
             lifecycle: %{state: :stale, severity: :warning}
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :status_matrix,
               binding: %{
                 source: :operational_observables,
                 mode: :context,
                 point_id: "comms.transport.connection_state",
                 point_ids: ["comms.transport.connection_state"]
               }
             })
  end

  test "widget presenter marks partial data from frame warning codes" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "source-request-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "HK.counter", kind: :number, values: [41]}
          ],
          meta: %{observable_id: "HK.counter", warning_codes: [:partial_data]}
        }
      ]
    }

    assert %{
             lifecycle_state: :partial,
             lifecycle: %{
               state: :partial,
               severity: :warning,
               reason_codes: [:partial, :partial_data]
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })
  end

  test "widget presenter returns unsupported lifecycle when source cannot satisfy the request" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :unsupported_source_capability,
          severity: :error,
          message: "Unsupported"
        }
      ]
    }

    assert %{
             kind: :point,
             sample: nil,
             lifecycle_state: :unsupported,
             lifecycle: %{
               state: :unsupported,
               severity: :error,
               reason_codes: [:unsupported, :no_data, :unsupported_source_capability]
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })
  end

  test "widget data carries data-management view and revision badges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "source-request-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "HK.counter",
              kind: :number,
              values: [41],
              metadata: %{sample_ids: ["sample-1"], quality_states: [:good]}
            }
          ],
          meta: %{
            logical_source: :telemetry,
            observable_id: "HK.counter",
            data_view: :all_revisions,
            realm: :simulation,
            warning_codes: [:all_revisions_view, :corrected_range, :late_arrival]
          }
        }
      ]
    }

    assert %{
             data_management: %{
               data_view: "all_revisions",
               warning_codes: ["all_revisions_view", "corrected_range", "late_arrival"],
               badges: badges
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })

    assert Enum.map(badges, & &1.value) == [
             "all_revisions",
             "simulation",
             "corrected",
             "late"
           ]

    assert Enum.any?(badges, &match?(%{label: "Corrected", code: "corrected_range"}, &1))
  end

  test "widget data carries active historical workflow badges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "source-request-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "HK.counter",
              kind: :number,
              values: [41],
              metadata: %{sample_ids: ["sample-1"], quality_states: [:good]}
            }
          ],
          meta: %{
            logical_source: :telemetry,
            observable_id: "HK.counter",
            warning_codes: [],
            historical_workflows: [
              %{category: :telemetry_backfill, kind: :backfill_started}
            ],
            active_historical_workflows: [
              %{category: :telemetry_revision, kind: :mark_conflict}
            ]
          }
        }
      ]
    }

    assert %{
             data_management: %{
               badges: badges
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })

    assert Enum.any?(
             badges,
             &match?(%{kind: :historical_workflow, value: "backfill_started"}, &1)
           )

    assert Enum.any?(
             badges,
             &match?(%{kind: :historical_workflow, value: "correction_conflict"}, &1)
           )
  end

  test "time-series limit markers include definition intervals" do
    placement_frames = %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :intervals,
            fields: [
              %Field{name: "active_from", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
              %Field{name: "active_to", kind: :time, values: [~U[2026-06-17 12:10:00Z]]},
              %Field{name: "limit_definition_id", kind: :string, values: ["counter-limits"]},
              %Field{name: "limit_definition_version", kind: :number, values: [2]},
              %Field{name: "limit_set_name", kind: :string, values: ["ops"]},
              %Field{name: "red_low", kind: :number, values: [0]},
              %Field{name: "yellow_low", kind: :number, values: [5]},
              %Field{name: "yellow_high", kind: :number, values: [10]},
              %Field{name: "red_high", kind: :number, values: [20]}
            ],
            meta: %{
              links: [
                %{
                  "link_id" => "limit_definition:counter-limits:req-1",
                  "target" => "limit_definition",
                  "target_id" => "counter-limits",
                  "label" => "Limit definition",
                  "presentation" => "side_panel",
                  "source" => "frame"
                }
              ]
            }
          }
        ]
      }
    }

    widget = %RenderWidget{type: :time_series}

    assert [
             %{
               marker_type: "limit_definition_interval",
               starts_at_ms: 1_781_697_600_000,
               ends_at_ms: 1_781_698_200_000,
               link_id: "limit_definition:counter-limits:req-1",
               target: "limit_definition",
               target_id: "counter-limits",
               limit_definition_id: "counter-limits",
               limit_definition_version: 2,
               limit_set_name: "ops",
               red_low: 0,
               yellow_low: 5,
               yellow_high: 10,
               red_high: 20
             }
           ] = WidgetPresentation.limit_markers(placement_frames, widget)
  end

  test "time-series source markers carry replay request provenance" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-replay",
          source: :telemetry,
          shape: :wide,
          meta: %{
            source_request_id: "req-replay",
            logical_source: :telemetry,
            source_binding_id: "binding-replay",
            data_source_id: "questdb-replay",
            realm: :replay,
            dataset: "replay-dataset",
            source_request_time_context: %{
              mode: :replay_run,
              axis: :receipt_time,
              from: ~U[2026-06-17 10:00:00Z],
              to: ~U[2026-06-17 12:00:00Z],
              replay_run_id: "replay-run-1"
            },
            source_request_context: %{
              source_request_id: "req-replay",
              logical_source: :telemetry,
              time_mode: :replay_run,
              time_axis: :receipt_time,
              replay_run_id: "replay-run-1",
              requested_realm: :replay,
              requested_data_source_id: "questdb-replay",
              requested_source_binding_id: "binding-replay",
              requested_dataset: "replay-dataset"
            },
            source_binding_interval: %{
              source_binding_id: "binding-replay",
              data_binding_event_id: "binding-event-1",
              data_source_id: "questdb-replay",
              dataset: "replay-dataset",
              realm: :replay,
              logical_source: :telemetry,
              started_at: ~U[2026-06-17 10:00:00Z],
              ended_at: ~U[2026-06-17 12:00:00Z],
              event_type: :activated,
              status: :active
            },
            source_watermarks: [
              %{
                logical_source: :telemetry,
                request_id: "req-replay",
                source_binding_id: "binding-replay",
                data_source_id: "questdb-replay",
                dataset: "replay-dataset",
                realm: :replay,
                freshness_state: :retention_gap,
                confidence: :authoritative,
                retention_starts_at: ~U[2026-06-17 11:00:00Z]
              }
            ]
          }
        }
      ]
    }

    widget = %RenderWidget{type: :time_series}
    markers = WidgetPresentation.event_markers(placement_frames, widget)

    source_binding_marker =
      Enum.find(markers, &(&1.marker_type == "source_binding_interval"))

    assert source_binding_marker.replay_run_id == "replay-run-1"
    assert source_binding_marker.time_mode == "replay_run"
    assert source_binding_marker.time_axis == "receipt_time"
    assert source_binding_marker.requested_realm == "replay"
    assert source_binding_marker.requested_data_source_id == "questdb-replay"
    assert source_binding_marker.requested_source_binding_id == "binding-replay"
    assert source_binding_marker.requested_dataset == "replay-dataset"

    retention_marker = Enum.find(markers, &(&1.marker_type == "retention_gap"))

    assert retention_marker.replay_run_id == "replay-run-1"
    assert retention_marker.time_mode == "replay_run"
    assert retention_marker.time_axis == "receipt_time"
    assert retention_marker.requested_realm == "replay"
    assert retention_marker.requested_data_source_id == "questdb-replay"
    assert retention_marker.requested_source_binding_id == "binding-replay"
    assert retention_marker.requested_dataset == "replay-dataset"
  end

  test "time-series event markers include source-health transitions" do
    placement_frames = %PlacementFrames{
      overlays: %{
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-21 12:02:00Z]]},
              %Field{name: "category", kind: :enum, values: [:source_health]},
              %Field{name: "kind", kind: :enum, values: [:degraded]},
              %Field{name: "severity", kind: :enum, values: [:warning]},
              %Field{name: "title", kind: :string, values: ["telemetry source degraded"]},
              %Field{name: "source_record_id", kind: :string, values: ["source-health-1"]},
              %Field{name: "source_health", kind: :enum, values: [:degraded]},
              %Field{name: "previous_source_health", kind: :enum, values: [:healthy]},
              %Field{name: "reason", kind: :enum, values: [:source_probe_failed]},
              %Field{name: "logical_source", kind: :enum, values: [:telemetry]},
              %Field{name: "data_source_id", kind: :string, values: ["flight-questdb"]},
              %Field{name: "source_binding_id", kind: :string, values: ["flight-telemetry"]}
            ],
            meta: %{
              family: :source_health,
              source_request_id: "events-request-1",
              logical_source: :events,
              source_binding_id: "events-binding",
              data_source_id: "events-projection",
              realm: :replay,
              dataset: "mission_events",
              replay_run_id: "replay-run-1",
              source_request_context: %{
                source_request_id: "events-request-1",
                logical_source: :events,
                time_mode: :replay_run,
                time_axis: :occurred_at,
                replay_run_id: "replay-run-1",
                requested_realm: :replay,
                requested_data_view: :all_revisions,
                requested_data_source_id: "events-projection",
                requested_source_binding_id: "events-binding",
                requested_dataset: "mission_events"
              },
              links: [
                %DataLink{
                  link_id: "source_health_event:source-health-1:events-request-1",
                  label: "Source health event",
                  target: :source_health_event,
                  target_id: "source-health-1",
                  source: :frame
                }
              ]
            }
          }
        ]
      }
    }

    widget = %RenderWidget{type: :time_series}

    assert [
             %{
               marker_type: "source_health_transition",
               timestamp_ms: 1_782_043_320_000,
               link_id: "source_health_event:source-health-1:events-request-1",
               target: "source_health_event",
               target_id: "source-health-1",
               source_health_event_id: "source-health-1",
               event_kind: "degraded",
               severity: "warning",
               title: "telemetry source degraded",
               source_record_id: "source-health-1",
               source_health: "degraded",
               previous_source_health: "healthy",
               reason: "source_probe_failed",
               source_request_id: "events-request-1",
               logical_source: "telemetry",
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry",
               dataset: "mission_events",
               realm: "replay",
               time_mode: "replay_run",
               time_axis: "occurred_at",
               replay_run_id: "replay-run-1",
               requested_realm: "replay",
               requested_data_view: "all_revisions",
               requested_data_source_id: "events-projection",
               requested_source_binding_id: "events-binding",
               requested_dataset: "mission_events"
             }
           ] = WidgetPresentation.event_markers(placement_frames, widget)
  end

  test "time-series event markers include source-watermark events" do
    placement_frames = %PlacementFrames{
      overlays: %{
        events: [
          %Frame{
            source: :events,
            shape: :events,
            fields: [
              %Field{name: "occurred_at", kind: :time, values: [~U[2026-06-21 12:06:00Z]]},
              %Field{name: "category", kind: :enum, values: [:source_watermark]},
              %Field{name: "kind", kind: :enum, values: [:advanced]},
              %Field{name: "severity", kind: :enum, values: [:info]},
              %Field{name: "title", kind: :string, values: ["telemetry watermark advanced"]},
              %Field{name: "source_record_id", kind: :string, values: ["watermark-event-1"]},
              %Field{name: "logical_source", kind: :enum, values: [:telemetry]},
              %Field{name: "data_source_id", kind: :string, values: ["flight-questdb"]},
              %Field{name: "source_binding_id", kind: :string, values: ["flight-telemetry"]},
              %Field{name: "realm", kind: :enum, values: [:flight]},
              %Field{name: "dataset", kind: :string, values: ["flight"]},
              %Field{name: "complete_through", kind: :time, values: [~U[2026-06-21 12:05:00Z]]},
              %Field{
                name: "previous_complete_through",
                kind: :time,
                values: [~U[2026-06-21 12:01:00Z]]
              },
              %Field{
                name: "latest_receipt_time",
                kind: :time,
                values: [~U[2026-06-21 12:05:30Z]]
              },
              %Field{
                name: "previous_latest_receipt_time",
                kind: :time,
                values: [~U[2026-06-21 12:01:30Z]]
              },
              %Field{
                name: "retention_starts_at",
                kind: :time,
                values: [~U[2026-06-20 00:00:00Z]]
              },
              %Field{name: "confidence", kind: :enum, values: [:authoritative]},
              %Field{name: "reason", kind: :enum, values: [:source_watermark_observed]}
            ],
            meta: %{
              family: :source_watermark,
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
                  link_id: "source_watermark_event:watermark-event-1:events-request-1",
                  label: "Source watermark event",
                  target: :source_watermark_event,
                  target_id: "watermark-event-1",
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

    assert marker.marker_type == "source_watermark_event"
    assert marker.marker_id == "source-watermark-event:watermark-event-1:1782043500000"
    assert marker.timestamp_ms == 1_782_043_500_000
    assert marker.observed_at_ms == 1_782_043_560_000
    assert marker.link_id == "source_watermark_event:watermark-event-1:events-request-1"
    assert marker.data_link_target == "source_watermark_event"
    assert marker.data_link_target_id == "watermark-event-1"
    assert marker.target == "source_watermark"
    assert marker.target_id == "watermark-event-1"
    assert marker.source_watermark_event_id == "watermark-event-1"
    assert marker.source_request_id == "events-request-1"
    assert marker.logical_source == "telemetry"
    assert marker.data_source_id == "flight-questdb"
    assert marker.source_binding_id == "flight-telemetry"
    assert marker.dataset == "flight"
    assert marker.realm == "flight"
    assert marker.time_mode == "archive"
    assert marker.time_axis == "occurred_at"
    assert marker.requested_realm == "flight"
    assert marker.requested_data_view == "canonical"
    assert marker.requested_data_source_id == "events-projection"
    assert marker.requested_source_binding_id == "events-binding"
    assert marker.requested_dataset == "mission_events"
    assert marker.event_kind == "advanced"
    assert marker.severity == "info"
    assert marker.title == "telemetry watermark advanced"
    assert marker.reason == "source_watermark_observed"
    assert marker.confidence == "authoritative"
    assert marker.complete_through_ms == 1_782_043_500_000
    assert marker.previous_complete_through_ms == 1_782_043_260_000
    assert marker.latest_receipt_time_ms == 1_782_043_530_000
    assert marker.previous_latest_receipt_time_ms == 1_782_043_290_000
    assert marker.retention_starts_at_ms == 1_781_913_600_000
    assert marker.label == "Watermark advanced / flight-telemetry / flight-questdb"
  end

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
