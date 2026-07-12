defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationStatusTableTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DataLink,
    Field,
    Frame,
    PlacementFrames,
    RenderWidget
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
end
