defmodule CadenceWeb.OpsDashboardShowLive.StatusMatrixDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.StatusMatrixData

  test "rows renders telemetry scalar rows with limit overlays" do
    telemetry_frame = %Frame{
      source: :telemetry,
      shape: :scalar,
      scope: %{primary: %{ids: ["spacecraft-alpha"]}},
      fields: [
        %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
        %Field{
          name: "HK.battery_voltage",
          kind: :number,
          values: [27.5],
          metadata: %{sample_ids: ["sample-1"], quality_states: [:good]}
        }
      ],
      meta: %{
        observable_id: "HK.battery_voltage",
        supported_capability: :latest_value,
        source_request_id: "telemetry-latest-1",
        logical_source: :telemetry,
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        source_binding_id: "default_flight_telemetry",
        dataset: "telemetry_latest",
        warning_codes: [:partial_data],
        links: [
          %DataLink{
            link_id: "point:HK.battery_voltage",
            target: :telemetry_point,
            target_id: "HK.battery_voltage"
          }
        ]
      }
    }

    limit_frame = %Frame{
      source: :limits,
      shape: :scalar,
      fields: [
        %Field{name: "normalized_state", kind: :enum, values: [:red]},
        %Field{name: "limit_state", kind: :enum, values: [:red_high]},
        %Field{name: "violation", kind: :boolean, values: [true]}
      ],
      meta: %{
        observable_id: "HK.battery_voltage",
        limit_event_id: "limit-event-1",
        links: [
          %DataLink{
            link_id: "limit-event:limit-event-1",
            target: :limit_event,
            target_id: "limit-event-1"
          }
        ]
      }
    }

    assert [
             %{
               observable_id: "HK.battery_voltage",
               frame_observable_id: "HK.battery_voltage",
               source: :telemetry,
               status_policy: :limit_state,
               product_family: :latest_value,
               supported_capability: :latest_value,
               source_request_id: "telemetry-latest-1",
               logical_source: :telemetry,
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry",
               dataset: "telemetry_latest",
               query_scope_id: "spacecraft-alpha",
               spacecraft_id: "spacecraft-alpha",
               value: 27.5,
               sample_id: "sample-1",
               normalized_state: :red,
               limit_state: :red_high,
               violation?: true,
               links: [
                 %{target: :telemetry_point, target_id: "HK.battery_voltage"},
                 %{target: :limit_event, target_id: "limit-event-1"}
               ],
               data_management: %{warning_codes: ["partial_data"]},
               stale?: false
             }
           ] =
             StatusMatrixData.rows(%PlacementFrames{
               primary: [telemetry_frame],
               overlays: %{limits: [limit_frame]}
             })
  end

  test "rows renders operational matrix connection and metric rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          scope: %{primary: %{kind: :transport, ids: ["transport-alpha", "transport-beta"]}},
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.connection_state"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "link_id", kind: :string, values: ["link-alpha"]},
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
            supported_capability: :connection_state,
            source_request_id: "ops-latest-1",
            logical_source: :operational_observables,
            realm: :flight,
            data_source_id: "managed_operational_observables",
            source_binding_id: "default_flight_operational_observables",
            dataset: "operational_observables",
            links: [
              %DataLink{
                link_id: "transport:transport-alpha:ops-latest-1",
                target: :transport,
                target_id: "transport-alpha"
              },
              %DataLink{
                link_id: "source_endpoint:endpoint-alpha:ops-latest-1",
                target: :source_endpoint,
                target_id: "endpoint-alpha"
              },
              %DataLink{
                link_id: "ground_station:dss-14:ops-latest-1",
                target: :ground_station,
                target_id: "dss-14"
              }
            ]
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
            %Field{name: "link_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "value", kind: :number, values: [4.5]},
            %Field{name: "unit", kind: :string, values: ["ms"]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:06:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:stale]},
            %Field{name: "age_ms", kind: :number, values: [2_000]}
          ],
          meta: %{
            supported_capability: :ingress_processing_latency,
            product_family: :runtime_ingress,
            warning_codes: [:stale_data],
            links: [
              %DataLink{
                link_id: "source_endpoint:endpoint-alpha:ops-latest-2",
                target: :source_endpoint,
                target_id: "endpoint-alpha"
              }
            ]
          }
        }
      ]
    }

    assert [
             %{
               observable_id: "comms.transport.connection_state:transport-alpha",
               frame_observable_id: "comms.transport.connection_state",
               label: "Lab TCP",
               source: :operational_observables,
               status_policy: :connection_state,
               link_id: "link-alpha",
               product_family: :connection_state,
               query_scope_kind: "transport",
               query_scope_id: "transport-alpha",
               query_scope_ids: ["transport-alpha", "transport-beta"],
               value: :connected,
               links: [
                 %{target: :transport, target_id: "transport-alpha"},
                 %{target: :source_endpoint, target_id: "endpoint-alpha"},
                 %{target: :ground_station, target_id: "dss-14"}
               ],
               stale?: false
             },
             %{
               observable_id: "ingress.processing_latency_ms:endpoint-alpha",
               frame_observable_id: "ingress.processing_latency_ms",
               label: "Ingress latency / endpoint-alpha",
               source: :operational_observables,
               status_policy: :metric_value,
               link_id: "link-alpha",
               product_family: :runtime_ingress,
               value: 4.5,
               unit: "ms",
               links: [%{target: :source_endpoint, target_id: "endpoint-alpha"}],
               freshness_state: :stale,
               stale?: true
             }
           ] = StatusMatrixData.rows(placement_frames)
  end

  test "rows renders generic operational state matrix rows" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{name: "observable_id", kind: :string, values: ["link.rf_lock_state"]},
            %Field{name: "resource_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "label", kind: :string, values: ["RF lock / link-alpha"]},
            %Field{name: "scope_kind", kind: :enum, values: [:link]},
            %Field{name: "link_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "adapter_key", kind: :enum, values: [:rf_adapter]},
            %Field{name: "state", kind: :enum, values: [:locked]},
            %Field{name: "normalized_state", kind: :enum, values: [:green]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:07:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:stale]},
            %Field{name: "age_ms", kind: :number, values: [6_000]}
          ],
          meta: %{
            supported_capability: :rf_lock_state,
            product_family: :link_rf,
            state_color_policy: :lock_state,
            links: [
              %DataLink{
                link_id: "link:link-alpha:ops-latest-3",
                target: :link,
                target_id: "link-alpha"
              },
              %DataLink{
                link_id: "transport:transport-alpha:ops-latest-3",
                target: :transport,
                target_id: "transport-alpha"
              },
              %DataLink{
                link_id: "source_endpoint:endpoint-alpha:ops-latest-3",
                target: :source_endpoint,
                target_id: "endpoint-alpha"
              },
              %DataLink{
                link_id: "ground_station:dss-14:ops-latest-3",
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
               observable_id: "link.rf_lock_state:link-alpha",
               frame_observable_id: "link.rf_lock_state",
               label: "RF lock / link-alpha",
               source: :operational_observables,
               status_policy: :lock_state,
               product_family: :link_rf,
               resource_id: "link-alpha",
               scope_kind: :link,
               link_id: "link-alpha",
               value: :locked,
               normalized_state: :green,
               quality_state: :rf_adapter,
               freshness_state: :stale,
               links: [
                 %{target: :link, target_id: "link-alpha"},
                 %{target: :transport, target_id: "transport-alpha"},
                 %{target: :source_endpoint, target_id: "endpoint-alpha"},
                 %{target: :ground_station, target_id: "dss-14"}
               ],
               stale?: true
             }
           ] = StatusMatrixData.rows(placement_frames)

    assert [
             %{target: :link, target_id: "link-alpha"},
             %{target: :transport, target_id: "transport-alpha"},
             %{target: :source_endpoint, target_id: "endpoint-alpha"},
             %{target: :ground_station, target_id: "dss-14"}
           ] = List.first(StatusMatrixData.rows(placement_frames)).links
  end
end
