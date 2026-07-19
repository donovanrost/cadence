defmodule Cadence.Dashboards.Sources.OperationalObservablesRFHistoryTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures

  alias Cadence.Dashboards.{Field, Frame, SourceResult}
  alias Cadence.Dashboards.Sources.OperationalObservables

  test "resolves RF SNR metric history into link-scoped wide frames" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              snr_db: 10.5,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              snr_db: 7.5,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              snr_db: 15.0,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.snr_db"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "dB"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.snr_db",
               kind: :number,
               values: [10.5, 12.75],
               metadata: %{
                 observable_id: "link.snr_db",
                 label: "RF SNR / link-alpha",
                 unit: "dB",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:rf_metric_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:rf_metric_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves RF Eb/N0 metric history through generic RF metric samples" do
    result =
      source_request()
      |> Map.put(:observables, ["link.eb_n0_db"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              value: 8.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              value: 9.25,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              value: 6.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.eb_n0_db"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "dB"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.eb_n0_db",
               kind: :number,
               values: [8.5, 9.25],
               metadata: %{
                 observable_id: "link.eb_n0_db",
                 label: "RF Eb/N0 / link-alpha",
                 unit: "dB",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:eb_n0_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:eb_n0_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves RF symbol-rate metric history through generic RF metric samples" do
    result =
      source_request()
      |> Map.put(:observables, ["link.symbol_rate_sps"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.symbol_rate_sps",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              symbol_rate_sps: 1_024_000.0,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "link.symbol_rate_sps",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              symbols_per_second: 2_048_000.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.symbol_rate_sps",
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              value: 512_000.0,
              unit: "sym/s",
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.symbol_rate_sps"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "sym/s"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.symbol_rate_sps",
               kind: :number,
               values: [1_024_000.0, 2_048_000.0],
               metadata: %{
                 observable_id: "link.symbol_rate_sps",
                 label: "RF Symbol Rate / link-alpha",
                 unit: "sym/s",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:symbol_rate_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:symbol_rate_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves RF Doppler metric history through generic RF metric samples" do
    result =
      source_request()
      |> Map.put(:observables, ["link.doppler_hz"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.doppler_hz",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frequency_offset_hz: -42.5,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "link.doppler_hz",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              carrier_frequency_offset_hz: -38.25,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.doppler_hz",
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              doppler_hz: 71.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.doppler_hz"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "Hz"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.doppler_hz",
               kind: :number,
               values: [-42.5, -38.25],
               metadata: %{
                 observable_id: "link.doppler_hz",
                 label: "RF Doppler / link-alpha",
                 unit: "Hz",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:doppler_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:doppler_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves empty RF SNR metric history as a chartable zero-point frame" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_rf_metric_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_rf_metric_history_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    refute result.meta.degraded?
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.snr_db"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.scope_kind == :link
    assert frame.meta.transport_id == "transport-alpha"
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.ground_station_id == "dss-14"
    assert frame.meta.link_id == "link-alpha"
    assert frame.meta.unit == "dB"
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "time", values: []},
             %Field{
               name: "link.snr_db",
               values: [],
               metadata: %{
                 observable_id: "link.snr_db",
                 label: "RF SNR / link-alpha",
                 unit: "dB",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket
               }
             }
           ] = frame.fields

    assert_received {:empty_rf_metric_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:empty_rf_metric_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF lock event history from timestamped snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :acquiring,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              lock_state: :unlocked,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :degraded,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :link_rf_lock_state_history
    assert frame.meta.supported_capability == :link_rf_lock_state_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]},
             %Field{name: "observable_id", values: ["link.rf_lock_state", "link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "lane_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "label", values: ["RF lock / link-alpha", "RF lock / link-alpha"]},
             %Field{name: "scope_kind", values: [:link, :link]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "state", values: [:acquiring, :locked]},
             %Field{name: "normalized_state", values: [:blue, :green]}
           ] = frame.fields
  end

  test "resolves frame sync event history from timestamped snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :acquiring,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :link_rf_frame_sync_state_history
    assert frame.meta.supported_capability == :link_rf_frame_sync_state_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :frame_sync_state
    assert frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]},
             %Field{
               name: "observable_id",
               values: ["link.frame_sync_state", "link.frame_sync_state"]
             },
             %Field{name: "resource_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "lane_id", values: ["link-alpha", "link-alpha"]},
             %Field{
               name: "label",
               values: ["Frame sync / link-alpha", "Frame sync / link-alpha"]
             },
             %Field{name: "scope_kind", values: [:link, :link]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "state", values: [:acquiring, :synchronized]},
             %Field{name: "normalized_state", values: [:blue, :green]}
           ] = frame.fields
  end

  test "resolves mixed operational state event history into product frames" do
    result =
      source_request()
      |> Map.put(:observables, [
        "contacts.phase",
        "comms.transport.connection_state",
        "link.rf_lock_state",
        "link.frame_sync_state"
      ])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [scheduled_contact("contact-1", :scheduled)]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [realized_contact("contact-1-run", :active, scheduled_contact_id: "contact-1")]
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14"
            )
          ]
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:02:30Z]
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:45Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [contact_frame, connection_frame, rf_lock_frame, frame_sync_frame],
             warnings: []
           } = result

    assert result.meta.supported_capability == :operational_state_history
    assert result.meta.returned_frame_count == 4

    assert contact_frame.shape == :events
    assert contact_frame.meta.supported_capability == :contacts_phase_history
    assert contact_frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:00:01Z]]},
             %Field{name: "observable_id", values: ["contacts.phase", "contacts.phase"]} | _rest
           ] = contact_frame.fields

    assert connection_frame.shape == :events
    assert connection_frame.meta.supported_capability == :connection_state_history
    assert connection_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = connection_frame.fields

    assert rf_lock_frame.shape == :events
    assert rf_lock_frame.meta.supported_capability == :link_rf_lock_state_history
    assert rf_lock_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:30Z]]},
             %Field{name: "observable_id", values: ["link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = rf_lock_frame.fields

    assert frame_sync_frame.shape == :events
    assert frame_sync_frame.meta.supported_capability == :link_rf_frame_sync_state_history
    assert frame_sync_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:45Z]]},
             %Field{name: "observable_id", values: ["link.frame_sync_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = frame_sync_frame.fields
  end

  test "preserves replay context in connection and RF state history reader options" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:03:00Z]

    result =
      source_request()
      |> Map.put(:observables, [
        "comms.transport.connection_state",
        "link.rf_lock_state",
        "link.frame_sync_state"
      ])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{
        realm: :replay,
        replay_run_id: "replay-run-1",
        source_contexts: %{
          operational_observables: %{
            data_source_id: "managed_operational_observables_replay",
            source_binding_id: "replay-operational-observables",
            dataset: "operational_observables_replay"
          }
        }
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_state_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_state_source_endpoints, organization_id, mission_id, opts})
          []
        end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_connection_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        link_rf_lock_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_rf_lock_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:02:30Z]
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_frame_sync_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:45Z]
            }
          ]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{
             frames: [connection_frame, rf_lock_frame, frame_sync_frame],
             warnings: []
           } = result

    assert result.meta.supported_capability == :operational_state_history

    for frame <- [connection_frame, rf_lock_frame, frame_sync_frame] do
      assert frame.meta.realm == :replay
      assert frame.meta.data_source_id == "managed_operational_observables_replay"
      assert frame.meta.source_binding_id == "replay-operational-observables"
      assert frame.meta.dataset == "operational_observables_replay"
      assert frame.meta.replay_run_id == "replay-run-1"
    end

    assert connection_frame.meta.supported_capability == :connection_state_history
    assert rf_lock_frame.meta.supported_capability == :link_rf_lock_state_history
    assert frame_sync_frame.meta.supported_capability == :link_rf_frame_sync_state_history

    for message <- [
          :replay_state_transports,
          :replay_state_source_endpoints,
          :replay_connection_snapshots,
          :replay_rf_lock_snapshots,
          :replay_frame_sync_snapshots
        ] do
      assert_received {^message, "org-1", "mission-1", opts}
      assert_replay_operational_observable_opts(opts, from_time, to_time)
    end
  end
end
