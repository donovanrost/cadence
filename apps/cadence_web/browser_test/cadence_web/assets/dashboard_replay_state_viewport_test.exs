# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardReplayStateViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{GroundStationStore, TransportStore}

  alias Cadence.Comms.GroundStation
  alias Cadence.Comms.Transport
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live replay operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-connection-state-timeline-viewport",
        display_name: "Replay Operational Connection State Timeline Viewport"
      )

    replay_run_id = "browser-connection-state-replay-run"
    other_replay_run_id = "browser-connection-state-other-replay-run"

    transport_connection_source_event_id =
      "operational_event:connection_state_snapshot:#{replay_run_id}:transport-replay-connected"

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    _replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(org.organization_id, dss_14)

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"transport-live-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:00:10Z], []},
          {"transport-replay-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z],
           [replay_run_id: replay_run_id]},
          {"transport-beta-replay-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:00:45Z],
           [
             link_id: "link-beta",
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"transport-other-replay-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [replay_run_id: other_replay_run_id]},
          {"transport-replay-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z],
           [replay_run_id: replay_run_id]},
          {"ground-live-connected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:00:15Z], [transport_id: nil]},
          {"ground-replay-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]},
          {"ground-beta-replay-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             replay_run_id: replay_run_id,
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"ground-other-replay-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [replay_run_id: other_replay_run_id, transport_id: nil]},
          {"ground-replay-connected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        Keyword.get(opts, :link_id, "link-alpha"),
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: resource_id,
            scope_kind: scope_kind,
            transport_id: alpha_transport.transport_id,
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Operational Connection State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Connection State Timeline",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          },
          %{
            type: :data_table,
            title: "Replay Connection State Rows",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 4, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "#{dss_14.ground_station_id},#{dss_63.ground_station_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_ids: scope_ids, time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-scope-kind",
                 "ground_station",
                 "--expected-scope-id",
                 dss_14.ground_station_id,
                 "--expected-scope-ids",
                 scope_ids,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 transport_connection_source_event_id,
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-operational-event-id",
                 "operational_event:connection_state_snapshot:#{replay_run_id}:transport-beta-replay-connected",
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
                 "--excluded-transport-id",
                 "browser-transport-excluded",
                 "--excluded-ground-station-id",
                 "dss-excluded",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  @tag :browser
  test "live replay operational RF state timeline uses default event-backed reader in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-rf-state-timeline-viewport",
        display_name: "Replay Operational RF State Timeline Viewport"
      )

    replay_run_id = "browser-rf-state-replay-run"
    other_replay_run_id = "browser-rf-state-other-replay-run"

    rf_lock_source_event_id =
      "operational_event:link_rf_lock_state_snapshot:#{replay_run_id}:rf-lock-replay-acquiring"

    rf_lock_table_source_event_id =
      "operational_event:link_rf_lock_state_snapshot:#{replay_run_id}:rf-lock-replay-acquiring"

    frame_sync_table_source_event_id =
      "operational_event:link_frame_sync_state_snapshot:#{replay_run_id}:frame-sync-replay-acquiring"

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    _replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)

    dss_14 =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-alpha",
          "transport_id" => "browser-transport-alpha",
          "link_assignment_id" => "link-alpha"
        }
      })

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(org.organization_id, dss_14)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_transport =
      Transport.new(%{
        transport_id: "browser-transport-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "alpha.ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-alpha"
        }
      })

    beta_transport =
      Transport.new(%{
        transport_id: "browser-transport-beta",
        mission_id: mission.mission_id,
        display_name: "Beta TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "beta.ground.example",
          "port" => "5001",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => beta_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-63",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, link_id, state, observed_at, opts} <- [
          {"rf-lock-live", "link.rf_lock_state", "link-alpha", :locked, ~U[2026-06-17 12:00:10Z],
           []},
          {"rf-lock-replay-acquiring", "link.rf_lock_state", "link-alpha", :acquiring,
           ~U[2026-06-17 12:00:30Z], [replay_run_id: replay_run_id]},
          {"rf-lock-beta-replay", "link.rf_lock_state", "link-beta", :unlocked,
           ~U[2026-06-17 12:00:45Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: "dss-63"
           ]},
          {"rf-lock-other-replay", "link.rf_lock_state", "link-alpha", :degraded,
           ~U[2026-06-17 12:01:00Z], [replay_run_id: other_replay_run_id]},
          {"rf-lock-replay-locked", "link.rf_lock_state", "link-alpha", :locked,
           ~U[2026-06-17 12:01:30Z], [replay_run_id: replay_run_id]},
          {"frame-sync-live", "link.frame_sync_state", "link-alpha", :synchronized,
           ~U[2026-06-17 12:00:15Z], []},
          {"frame-sync-replay-acquiring", "link.frame_sync_state", "link-alpha", :acquiring,
           ~U[2026-06-17 12:00:45Z], [replay_run_id: replay_run_id]},
          {"frame-sync-beta-replay", "link.frame_sync_state", "link-beta", :lost,
           ~U[2026-06-17 12:01:00Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: "dss-63"
           ]},
          {"frame-sync-other-replay", "link.frame_sync_state", "link-alpha", :lost,
           ~U[2026-06-17 12:01:15Z], [replay_run_id: other_replay_run_id]},
          {"frame-sync-replay-synchronized", "link.frame_sync_state", "link-alpha", :synchronized,
           ~U[2026-06-17 12:01:45Z], [replay_run_id: replay_run_id]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        observable_id,
        link_id,
        state,
        observed_at,
        opts
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Operational RF State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "RF State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
          },
          %{
            type: :data_table,
            title: "Replay RF State Rows",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 4, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-rf-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 rf_lock_source_event_id,
                 "--expected-rf-lock-table-operational-event-id",
                 rf_lock_table_source_event_id,
                 "--expected-rf-lock-table-state",
                 "Acquiring",
                 "--expected-frame-sync-table-operational-event-id",
                 frame_sync_table_source_event_id,
                 "--expected-frame-sync-table-state",
                 "Acquiring",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password()
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end
end
