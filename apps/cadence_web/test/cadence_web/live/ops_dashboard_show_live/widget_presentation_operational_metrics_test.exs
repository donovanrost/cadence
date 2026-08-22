defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationOperationalMetricsTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

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
end
