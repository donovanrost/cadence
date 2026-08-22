defmodule CadenceWeb.OpsDashboardShowLive.PointWidgetDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames, ResolveWarning}
  alias CadenceWeb.OpsDashboardShowLive.PointWidgetData

  test "renders telemetry scalar point data with limit overlay context" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          scope: %{primary: %{ids: ["spacecraft-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "HK.battery_voltage",
              kind: :number,
              values: [27.4],
              metadata: %{sample_ids: ["sample-1"], quality_states: [:good]}
            }
          ],
          meta: %{
            observable_id: "HK.battery_voltage",
            sample_id: "sample-1",
            warning_codes: [],
            links: [
              %{
                "link_id" => "point:HK.battery_voltage",
                "target" => "telemetry_point",
                "target_id" => "HK.battery_voltage",
                "label" => "Telemetry point"
              }
            ]
          }
        }
      ],
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :scalar,
            fields: [
              %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
              %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
              %Field{name: "limit_state", kind: :enum, values: [:yellow_high]}
            ],
            meta: %{limit_event_id: "limit-event-1"}
          }
        ]
      }
    }

    assert %{
             kind: :point,
             spacecraft_id: "spacecraft-alpha",
             sample: %{
               sample_id: "sample-1",
               raw_value: 27.4,
               engineering_value: 27.4,
               receipt_time: ~U[2026-06-17 12:00:00Z],
               quality_state: :good
             },
             limit_event: %{
               normalized_state: :yellow,
               limit_state: :yellow_high,
               limit_event_id: "limit-event-1"
             },
             unresolved?: false,
             engine_backed?: true,
             lifecycle_state: :ready
           } = PointWidgetData.data(placement_frames)
  end

  test "renders empty telemetry scalar frame as no data with source context" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          scope: %{primary: %{kind: :spacecraft, ids: ["spacecraft-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: []},
            %Field{name: "HK.battery_voltage", kind: :number, values: []}
          ],
          meta: %{
            observable_id: "HK.battery_voltage",
            source_request_context: %{
              logical_source: :telemetry,
              data_source_id: "flight-questdb",
              source_binding_id: "flight-telemetry",
              realm: :flight,
              time_mode: :live,
              time_axis: :generation_time,
              scope_kind: :spacecraft,
              scope_ids: ["spacecraft-alpha"]
            },
            warning_codes: []
          }
        }
      ]
    }

    assert %{
             kind: :point,
             sample: nil,
             unresolved?: false,
             engine_backed?: true,
             lifecycle_state: :no_data,
             lifecycle: %{state: :no_data, severity: :info, warning_codes: []},
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               logical_sources: [:telemetry],
               data_source_ids: ["flight-questdb"],
               source_binding_ids: ["flight-telemetry"],
               realms: [:flight],
               time_modes: [:live],
               time_axes: [:generation_time],
               scope_kinds: [:spacecraft],
               scope_ids: ["spacecraft-alpha"],
               empty_reason: :scope_no_data
             }
           } = PointWidgetData.data(placement_frames)
  end

  test "context data remains unresolved without scoped identity" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "HK.counter", kind: :number, values: [41]}
          ],
          meta: %{observable_id: "HK.counter", warning_codes: []}
        }
      ]
    }

    assert %{
             kind: :point,
             sample: nil,
             unresolved?: true,
             lifecycle_state: :no_data
           } = PointWidgetData.context_data(placement_frames)
  end

  test "context data preserves source failure warnings without scoped frame identity" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :source_unavailable,
          severity: :error,
          message: "Source unavailable",
          details: %{
            source_request_id: "source-req-1",
            logical_source: :telemetry,
            data_source_id: "flight-questdb",
            source_binding_id: "flight-telemetry",
            realm: :flight,
            time_mode: :live,
            time_axis: :generation_time
          }
        }
      ]
    }

    assert %{
             kind: :point,
             sample: nil,
             unresolved?: false,
             engine_backed?: true,
             lifecycle_state: :error,
             lifecycle: %{warning_codes: [:source_unavailable]},
             source_status: %{
               state: :unavailable,
               warning_codes: [:source_unavailable],
               logical_sources: [:telemetry],
               data_source_ids: ["flight-questdb"],
               source_binding_ids: ["flight-telemetry"]
             }
           } = PointWidgetData.context_data(placement_frames)
  end

  test "context data resolves non-spacecraft telemetry scope" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          scope: %{primary: %{kind: :mission, ids: ["mission-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "mission.packet_rate",
              kind: :number,
              values: [12],
              metadata: %{sample_ids: ["sample-mission-1"]}
            }
          ],
          meta: %{observable_id: "mission.packet_rate", warning_codes: []}
        }
      ]
    }

    assert %{
             kind: :point,
             spacecraft_id: nil,
             sample: %{sample_id: "sample-mission-1", raw_value: 12},
             query_scope_kind: "mission",
             query_scope_id: "mission-alpha",
             query_scope_ids: ["mission-alpha"],
             unresolved?: false,
             lifecycle_state: :ready
           } = PointWidgetData.context_data(placement_frames)
  end

  test "renders operational metric point data with resource DataLink context" do
    link_context = %{
      logical_source: :operational_observables,
      observable_id: "comms.transport.downlink_bitrate",
      data: %{
        realm: :flight,
        data_source_id: "managed_operational_observables",
        source_binding_id: "default_flight_operational_observables",
        dataset: "operational_observables"
      },
      operational_resource: %{
        resource_id: "transport-alpha",
        scope_kind: :transport,
        transport_id: "transport-alpha",
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket
      }
    }

    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          scope: %{primary: %{kind: :source_endpoint, ids: ["endpoint-alpha"]}},
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
            %Field{name: "link_id", kind: :string, values: ["link-alpha"]},
            %Field{name: "adapter_key", kind: :enum, values: [:tcp_socket]},
            %Field{name: "value", kind: :number, values: [12_500.5]},
            %Field{name: "unit", kind: :string, values: ["bit/s"]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:04:00Z]]},
            %Field{name: "freshness_state", kind: :enum, values: [:fresh]},
            %Field{name: "age_ms", kind: :number, values: [2_000]}
          ],
          meta: %{
            observable_id: "comms.transport.downlink_bitrate",
            unit: "bit/s",
            warning_codes: [],
            links: [
              %DataLink{
                link_id: "link:link-alpha:ops-request-1",
                label: "Link",
                target: :link,
                target_id: "link-alpha",
                context: link_context,
                source: :frame
              },
              %DataLink{
                link_id: "transport:transport-alpha:ops-request-1",
                label: "Transport",
                target: :transport,
                target_id: "transport-alpha",
                context: link_context,
                source: :frame
              },
              %DataLink{
                link_id: "source-endpoint:endpoint-alpha:ops-request-1",
                label: "Source endpoint",
                target: :source_endpoint,
                target_id: "endpoint-alpha",
                context: link_context,
                source: :frame
              },
              %DataLink{
                link_id: "ground-station:dss-14:ops-request-1",
                label: "Ground station",
                target: :ground_station,
                target_id: "dss-14",
                context: link_context,
                source: :frame
              }
            ]
          }
        }
      ]
    }

    assert %{
             kind: :point,
             spacecraft_id: nil,
             label: "Lab TCP",
             unit: "bit/s",
             sample: %{
               sample_id: "transport-alpha",
               raw_value: 12_500.5,
               engineering_value: 12_500.5,
               receipt_time: ~U[2026-06-17 12:04:00Z],
               generation_time: ~U[2026-06-17 12:04:00Z],
               quality_state: :observed
             },
             links: [
               %{target: :link, target_id: "link-alpha", context: ^link_context},
               %{target: :transport, target_id: "transport-alpha", context: ^link_context},
               %{target: :source_endpoint, target_id: "endpoint-alpha", context: ^link_context},
               %{target: :ground_station, target_id: "dss-14", context: ^link_context}
             ],
             query_scope_kind: "source_endpoint",
             query_scope_id: "endpoint-alpha",
             query_scope_ids: ["endpoint-alpha"],
             unresolved?: false,
             engine_backed?: true,
             lifecycle_state: :ready
           } = PointWidgetData.data(placement_frames)
  end

  test "source failure data exposes unsupported point lifecycle" do
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
             lifecycle: %{state: :unsupported, severity: :error}
           } = PointWidgetData.source_failure_data(placement_frames)
  end

  test "source failure data exposes retention gap point lifecycle" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :retention_gap,
          severity: :warning,
          message: "Retention gap",
          details: %{
            source_request_id: "source-req-retention",
            logical_source: :telemetry,
            data_source_id: "flight-questdb",
            source_binding_id: "flight-telemetry",
            realm: :flight,
            time_mode: :archive,
            time_axis: :receipt_time
          }
        }
      ]
    }

    assert %{
             kind: :point,
             sample: nil,
             unresolved?: false,
             engine_backed?: true,
             lifecycle_state: :retention_gap,
             lifecycle: %{
               state: :retention_gap,
               severity: :error,
               warning_codes: [:retention_gap]
             },
             source_status: %{
               state: :retention_gap,
               severity: :error,
               warning_codes: [:retention_gap],
               logical_sources: [:telemetry],
               data_source_ids: ["flight-questdb"],
               source_binding_ids: ["flight-telemetry"],
               time_modes: [:archive],
               time_axes: [:receipt_time]
             }
           } = PointWidgetData.source_failure_data(placement_frames)
  end
end
