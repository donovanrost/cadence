defmodule Cadence.Dashboards.Sources.OperationalObservablesConnectionTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures

  alias Cadence.Dashboards.{Field, Frame, ResolveWarning, SourceResult}
  alias Cadence.Dashboards.Sources.OperationalObservables
  alias Cadence.OperationalEvents.EffectiveInterval

  test "resolves connection state observables from configured operational resources and snapshots" do
    transports_fun = fn organization_id, mission_id, opts ->
      send(self(), {:transports, organization_id, mission_id, opts})

      [
        transport("transport-alpha", "Lab TCP",
          source_endpoint_id: "endpoint-alpha",
          ground_station_id: "dss-14"
        ),
        transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
      ]
    end

    source_endpoints_fun = fn organization_id, mission_id, opts ->
      send(self(), {:source_endpoints, organization_id, mission_id, opts})

      [
        source_endpoint("endpoint-alpha", "Goldstone DSS-14", ground_station_id: "dss-14"),
        source_endpoint("endpoint-beta", "Backup Antenna")
      ]
    end

    connection_snapshots_fun = fn organization_id, mission_id, opts ->
      send(self(), {:connection_snapshots, organization_id, mission_id, opts})

      [
        %{
          transport_id: "transport-alpha",
          source_endpoint_id: "endpoint-alpha",
          adapter_key: :tcp_socket,
          connection_state: :connected,
          observed_at: ~U[2026-06-17 12:03:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, [
        "comms.transport.connection_state",
        "ground.station.connection_state"
      ])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
        transports_fun: transports_fun,
        source_endpoints_fun: source_endpoints_fun,
        connection_snapshots_fun: connection_snapshots_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :connection_state
    assert frame.meta.supported_capability == :connection_state
    assert frame.meta.returned_points == 2

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"}
           ]

    assert [
             %Field{
               name: "observable_id",
               values: [
                 "comms.transport.connection_state",
                 "ground.station.connection_state"
               ]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "dss-14"]},
             %Field{name: "label", values: ["Lab TCP", "Goldstone DSS-14"]},
             %Field{name: "scope_kind", values: [:transport, :ground_station]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "connection_state", values: [:connected, :connected]},
             %Field{
               name: "observed_at",
               values: [~U[2026-06-17 12:03:00Z], ~U[2026-06-17 12:03:00Z]]
             },
             %Field{name: "freshness_state", values: [:fresh, :fresh]},
             %Field{name: "age_ms", values: [2_000, 2_000]}
           ] = frame.fields

    assert_received {:transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:source_endpoints, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"

    assert_received {:connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "marks configured ground-station connection rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["ground.station.connection_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_ground_station_transports, organization_id, mission_id, opts})
          []
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_ground_station_source_endpoints, organization_id, mission_id, opts}
          )

          [
            source_endpoint("endpoint-alpha", "Goldstone DSS-14", ground_station_id: "dss-14")
          ]
        end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_ground_station_connection_snapshots, organization_id, mission_id, opts}
          )

          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :connection_state
    assert warning.details.frame_ids == ["ops-request-1:connection_state"]
    assert warning.details.observable_ids == ["ground.station.connection_state"]
    assert frame.meta.supported_capability == :connection_state
    assert frame.meta.observable_ids == ["ground.station.connection_state"]
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:03:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"}
           ]

    assert [
             %Field{name: "observable_id", values: ["ground.station.connection_state"]},
             %Field{name: "resource_id", values: ["dss-14"]},
             %Field{name: "label", values: ["Goldstone DSS-14"]},
             %Field{name: "scope_kind", values: [:ground_station]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "connection_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_ground_station_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_ground_station_source_endpoints, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"

    assert_received {:missing_ground_station_connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "marks configured transport connection rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_transport_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_transport_source_endpoints, organization_id, mission_id, opts}
          )

          []
        end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_transport_connection_snapshots, organization_id, mission_id, opts}
          )

          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :connection_state
    assert warning.details.frame_ids == ["ops-request-1:connection_state"]
    assert warning.details.observable_ids == ["comms.transport.connection_state"]
    assert frame.meta.supported_capability == :connection_state
    assert frame.meta.observable_ids == ["comms.transport.connection_state"]
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:03:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "connection_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_transport_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_transport_source_endpoints, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"

    assert_received {:missing_transport_connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "filters connection state latest rows to link scope" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
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
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              link_assignment_id: "link-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:03:00Z],
              interval_id: "effective_interval:transport_connection_state:conn-event-alpha",
              source_event_id: "conn-event-alpha",
              interval: %{
                kind: :transport_connection_state,
                interval_id: "effective_interval:transport_connection_state:conn-event-alpha",
                source_event_id: "conn-event-alpha",
                starts_at: ~U[2026-06-17 12:03:00Z]
              }
            },
            %{
              transport_id: "transport-beta",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta",
              connection_state: :disconnected,
              observed_at: ~U[2026-06-17 12:03:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "connection_state", values: [:connected]} | _rest
           ] = frame.fields

    assert field_values(frame, "interval_id") == [
             "effective_interval:transport_connection_state:conn-event-alpha"
           ]

    assert field_values(frame, "source_event_id") == ["conn-event-alpha"]
    assert "conn-event-alpha" in operational_event_link_ids(frame)

    assert {
             :transport_connection_state_interval,
             "effective_interval:transport_connection_state:conn-event-alpha"
           } in evidence_identities(frame)

    assert {:operational_interval, "conn-event-alpha"} in evidence_identities(frame)
  end

  test "latest RF state frames preserve selected interval evidence from canonical intervals" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state", "link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:10:02Z],
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:10:00Z],
              interval_id: "effective_interval:link_rf_lock_state:rf-lock-event-alpha",
              source_event_id: "rf-lock-event-alpha",
              interval: %{
                kind: :link_rf_lock_state,
                interval_id: "effective_interval:link_rf_lock_state:rf-lock-event-alpha",
                source_event_id: "rf-lock-event-alpha",
                starts_at: ~U[2026-06-17 12:10:00Z]
              }
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:10:01Z],
              interval_id: "effective_interval:link_frame_sync_state:frame-sync-event-alpha",
              source_event_id: "frame-sync-event-alpha",
              interval: %{
                kind: :link_frame_sync_state,
                interval_id: "effective_interval:link_frame_sync_state:frame-sync-event-alpha",
                source_event_id: "frame-sync-event-alpha",
                starts_at: ~U[2026-06-17 12:10:01Z]
              }
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: frames, warnings: []} = result

    lock_frame =
      Enum.find(frames, &(&1.meta.supported_capability == :link_rf_lock_state))

    sync_frame =
      Enum.find(frames, &(&1.meta.supported_capability == :link_rf_frame_sync_state))

    assert field_values(lock_frame, "interval_id") == [
             "effective_interval:link_rf_lock_state:rf-lock-event-alpha"
           ]

    assert field_values(lock_frame, "source_event_id") == ["rf-lock-event-alpha"]
    assert "rf-lock-event-alpha" in operational_event_link_ids(lock_frame)

    assert {
             :link_rf_lock_state_interval,
             "effective_interval:link_rf_lock_state:rf-lock-event-alpha"
           } in evidence_identities(lock_frame)

    assert {:operational_interval, "rf-lock-event-alpha"} in evidence_identities(lock_frame)

    assert field_values(sync_frame, "interval_id") == [
             "effective_interval:link_frame_sync_state:frame-sync-event-alpha"
           ]

    assert field_values(sync_frame, "source_event_id") == ["frame-sync-event-alpha"]
    assert "frame-sync-event-alpha" in operational_event_link_ids(sync_frame)

    assert {
             :link_frame_sync_state_interval,
             "effective_interval:link_frame_sync_state:frame-sync-event-alpha"
           } in evidence_identities(sync_frame)

    assert {:operational_interval, "frame-sync-event-alpha"} in evidence_identities(sync_frame)
  end

  test "latest antenna pointing state preserves ground-station interval evidence" do
    result =
      source_request()
      |> Map.put(:observables, ["ground.station.antenna_pointing_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:10:02Z],
        source_endpoints_fun: fn _organization_id, _mission_id, _opts ->
          [
            source_endpoint("endpoint-alpha", "DSS-14 endpoint",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        antenna_pointing_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :antenna_adapter,
              acquisition_state: :tracking,
              observed_at: ~U[2026-06-17 12:10:00Z],
              interval_id:
                "effective_interval:operational_observable_state:antenna-pointing-event-alpha",
              source_event_id: "antenna-pointing-event-alpha",
              interval: %EffectiveInterval{
                kind: :operational_observable_state,
                interval_id:
                  "effective_interval:operational_observable_state:antenna-pointing-event-alpha",
                source_event_id: "antenna-pointing-event-alpha",
                starts_at: ~U[2026-06-17 12:10:00Z],
                payload: %{
                  "observable_id" => "ground.station.antenna_pointing_state",
                  "resource_id" => "dss-14"
                }
              }
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert result.meta.supported_capability == :ground_station_antenna_pointing_state
    assert frame.meta.supported_capability == :ground_station_antenna_pointing_state
    assert frame.meta.product_family == :ground_station
    assert frame.meta.state_color_policy == :antenna_pointing_state
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["ground.station.antenna_pointing_state"]},
             %Field{name: "resource_id", values: ["dss-14"]},
             %Field{name: "label", values: ["Antenna pointing / DSS-14 endpoint"]},
             %Field{name: "scope_kind", values: [:ground_station]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:antenna_adapter]},
             %Field{name: "state", values: [:tracking]},
             %Field{name: "normalized_state", values: [:green]} | _rest
           ] = frame.fields

    assert field_values(frame, "interval_id") == [
             "effective_interval:operational_observable_state:antenna-pointing-event-alpha"
           ]

    assert field_values(frame, "source_event_id") == ["antenna-pointing-event-alpha"]
    assert "antenna-pointing-event-alpha" in operational_event_link_ids(frame)

    assert {
             :ground_station_antenna_pointing_state_interval,
             "effective_interval:operational_observable_state:antenna-pointing-event-alpha"
           } in evidence_identities(frame)

    assert {:operational_interval, "antenna-pointing-event-alpha"} in evidence_identities(frame)
  end

  test "resolves connection state event history from runtime snapshots" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:03:00Z]

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{from: from_time, to: to_time})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14"
            ),
            transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
          ]
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:history_connection_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ground.station.connection_state",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              adapter_key: :tcp_socket,
              connection_state: :disconnected,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              observable_id: "comms.transport.connection_state",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connecting,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "comms.transport.connection_state",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-alpha",
              connection_state: :disconnected,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :connection_state_history
    assert frame.meta.supported_capability == :connection_state_history
    assert frame.meta.sampling == :event_history
    assert frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]},
             %Field{
               name: "observable_id",
               values: ["comms.transport.connection_state", "comms.transport.connection_state"]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP", "Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport, :transport]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "connection_state", values: [:connecting, :connected]},
             %Field{name: "normalized_state", values: [:connecting, :connected]}
           ] = frame.fields

    assert_received {:history_transports, "org-1", "mission-1", opts}
    assert opts[:from] == from_time
    assert opts[:to] == to_time

    assert_received {:history_connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves antenna pointing state event history filtered to ground-station scope" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    result =
      source_request()
      |> Map.put(:observables, ["ground.station.antenna_pointing_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{from: from_time, to: to_time})
      |> Map.put(:scope_context, %{
        primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}
      })
      |> OperationalObservables.resolve(
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:antenna_history_source_endpoints, organization_id, mission_id, opts})

          [
            source_endpoint("endpoint-alpha", "DSS-14 endpoint",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            source_endpoint("endpoint-beta", "DSS-63 endpoint", ground_station_id: "dss-63")
          ]
        end,
        antenna_pointing_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:antenna_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              adapter_key: :antenna_adapter,
              pointing_state: :slewing,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              adapter_key: :antenna_adapter,
              pointing_state: :tracking,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-beta",
              ground_station_id: "dss-63",
              adapter_key: :antenna_adapter,
              pointing_state: :tracking,
              observed_at: ~U[2026-06-17 12:03:30Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert result.meta.supported_capability == :ground_station_antenna_pointing_state_history
    assert frame.meta.supported_capability == :ground_station_antenna_pointing_state_history
    assert frame.meta.sampling == :event_history
    assert frame.meta.product_family == :ground_station
    assert frame.meta.state_color_policy == :antenna_pointing_state
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:30Z], ~U[2026-06-17 12:02:30Z]]
             },
             %Field{
               name: "observable_id",
               values: [
                 "ground.station.antenna_pointing_state",
                 "ground.station.antenna_pointing_state"
               ]
             },
             %Field{name: "resource_id", values: ["dss-14", "dss-14"]},
             %Field{name: "lane_id", values: ["dss-14", "dss-14"]},
             %Field{
               name: "label",
               values: [
                 "Antenna pointing / DSS-14 endpoint",
                 "Antenna pointing / DSS-14 endpoint"
               ]
             },
             %Field{name: "scope_kind", values: [:ground_station, :ground_station]},
             %Field{name: "transport_id", values: [nil, nil]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "adapter_key", values: [:antenna_adapter, :antenna_adapter]},
             %Field{name: "state", values: [:slewing, :tracking]},
             %Field{name: "normalized_state", values: [:blue, :green]}
           ] = frame.fields

    assert_received {:antenna_history_source_endpoints, "org-1", "mission-1", opts}
    assert opts[:from] == from_time
    assert opts[:to] == to_time

    assert_received {:antenna_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "filters connection state history rows to link scope" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
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
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              connection_state: :connecting,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z]]},
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "connection_state", values: [:connecting]} | _rest
           ] = frame.fields
  end

  test "resolves transport execution event history from operational intervals" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    transport_execution_intervals_fun = fn organization_id, mission_id, opts ->
      send(self(), {:transport_execution_intervals, organization_id, mission_id, opts})

      [
        transport_execution_interval(
          "interval-1",
          "transport-alpha",
          :initialized,
          ~U[2026-06-17 12:00:30Z],
          ~U[2026-06-17 12:02:00Z]
        ),
        transport_execution_interval(
          "interval-2",
          "transport-alpha",
          :control_input_handled,
          ~U[2026-06-17 12:02:00Z],
          ~U[2026-06-17 12:05:00Z],
          contact_id: "contact-alpha",
          path_id: "uplink-alpha",
          transport_record_id: "record-alpha-2",
          source_event_id: "event-alpha-2"
        ),
        transport_execution_interval(
          "interval-3",
          "transport-beta",
          :timer_handled,
          ~U[2026-06-17 12:02:30Z],
          ~U[2026-06-17 12:03:00Z]
        )
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.execution_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{from: from_time, to: to_time})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transport_execution_intervals_fun: transport_execution_intervals_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.product_family == :comms_transport
    assert frame.meta.state_color_policy == :transport_execution_state
    assert frame.meta.observable_id == "comms.transport.execution_state"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:00:30Z], ~U[2026-06-17 12:02:00Z]]
             },
             %Field{
               name: "ends_at",
               values: [~U[2026-06-17 12:02:00Z], ~U[2026-06-17 12:05:00Z]]
             },
             %Field{
               name: "observable_id",
               values: [
                 "comms.transport.execution_state",
                 "comms.transport.execution_state"
               ]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "lane_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{
               name: "label",
               values: [
                 "Transport execution / transport-alpha",
                 "Transport execution / transport-alpha"
               ]
             },
             %Field{name: "scope_kind", values: [:transport, :transport]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "contact_id", values: ["contact-alpha", "contact-alpha"]},
             %Field{name: "path_id", values: ["uplink-alpha", "uplink-alpha"]},
             %Field{name: "transport_record_id", values: ["record-interval-1", "record-alpha-2"]},
             %Field{name: "interval_id", values: ["interval-1", "interval-2"]},
             %Field{name: "source_event_id", values: ["event-interval-1", "event-alpha-2"]},
             %Field{name: "state", values: [:initialized, :control_input_handled]},
             %Field{name: "normalized_state", values: [:initialized, :control_input_handled]}
           ] = frame.fields

    assert [
             %{
               kind: :transport_execution_interval,
               id: "interval-1",
               source: :events,
               confidence: :projected
             },
             %{kind: :operational_interval, id: "event-interval-1", confidence: :direct},
             %{kind: :transport_execution_interval, id: "interval-2", confidence: :projected},
             %{kind: :operational_interval, id: "event-alpha-2", confidence: :direct}
           ] = frame.meta.evidence_refs

    assert_received {:transport_execution_intervals, "org-1", "mission-1", opts}
    assert opts[:from] == from_time
    assert opts[:to] == to_time
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "preserves replay context in transport execution interval reader options" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    transport_execution_intervals_fun = fn organization_id, mission_id, opts ->
      send(self(), {:replay_transport_execution_intervals, organization_id, mission_id, opts})

      [
        transport_execution_interval(
          "replay-interval-1",
          "transport-alpha",
          :initialized,
          ~U[2026-06-17 12:01:30Z],
          ~U[2026-06-17 12:02:30Z]
        )
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.execution_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        transport_execution_intervals_fun: transport_execution_intervals_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.realm == :replay
    assert frame.meta.data_source_id == "managed_operational_observables_replay"
    assert frame.meta.source_binding_id == "replay-operational-observables"
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"

    assert_received {:replay_transport_execution_intervals, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end
end
