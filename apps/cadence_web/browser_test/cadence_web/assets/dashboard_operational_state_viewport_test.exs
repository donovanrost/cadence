# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardOperationalStateViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportOperationalFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.GroundStation
  alias Cadence.Comms.Transport
  alias Cadence.Dashboards.DataSources
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live operational RF state timeline DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution)

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_rf_state_timeline_source_execution_opts()
    )

    on_exit(fn ->
      case previous_source_execution do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_source_execution)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_source_execution, value)
      end
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-rf-state-timeline-viewport",
        display_name: "Operational RF State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

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

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)

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
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

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

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational RF State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "RF State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha"}}"

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
  test "live operational connection state timeline interval evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-connection-state-timeline-viewport",
        display_name: "Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

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

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

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
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

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

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"transport-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"transport-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"ground-disconnected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z], [transport_id: nil]},
          {"ground-connected", "ground.station.connection_state", dss_14.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:01:45Z], [transport_id: nil]},
          {"transport-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"ground-beta-connected", "ground.station.connection_state", dss_63.ground_station_id,
           :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
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
        name: "Operational Connection State Timeline Browser",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-connection-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
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
  test "live antenna pointing state timeline interval evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "antenna-pointing-state-timeline-viewport",
        display_name: "Antenna Pointing State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

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

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "transport_id" => "browser-transport-alpha",
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
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    for {snapshot_id, ground_station_id, source_endpoint_id, link_id, state, observed_at} <- [
          {"antenna-pointing-slewing", dss_14.ground_station_id,
           alpha_endpoint.source_endpoint_id, "link-alpha", :slewing, ~U[2026-06-17 12:00:30Z]},
          {"antenna-pointing-tracking", dss_14.ground_station_id,
           alpha_endpoint.source_endpoint_id, "link-alpha", :tracking, ~U[2026-06-17 12:01:30Z]},
          {"antenna-pointing-beta-tracking", dss_63.ground_station_id,
           beta_endpoint.source_endpoint_id, "link-beta", :tracking, ~U[2026-06-17 12:01:00Z]}
        ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        "ground.station.antenna_pointing_state",
        link_id,
        state,
        observed_at,
        resource_id: ground_station_id,
        scope_kind: :ground_station,
        transport_id: nil,
        source_endpoint_id: source_endpoint_id,
        ground_station_id: ground_station_id
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Antenna Pointing State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Antenna Pointing State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.antenna_pointing_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-antenna-pointing-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-operational-event-id",
                 "operational_event:operational_observable_snapshot:antenna-pointing-tracking",
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
  test "live replay antenna pointing state timeline interval evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-antenna-pointing-state-timeline-viewport",
        display_name: "Replay Antenna Pointing State Timeline Viewport"
      )

    replay_run_id = "browser-antenna-pointing-replay-run"
    other_replay_run_id = "browser-antenna-pointing-other-replay-run"

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

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "transport_id" => "browser-transport-alpha",
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
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    for {snapshot_id, ground_station_id, source_endpoint_id, link_id, state, observed_at, opts} <-
          [
            {"antenna-pointing-live-tracking", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :tracking, ~U[2026-06-17 12:00:10Z],
             []},
            {"antenna-pointing-replay-slewing", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :slewing, ~U[2026-06-17 12:00:30Z],
             [replay_run_id: replay_run_id]},
            {"antenna-pointing-beta-replay-tracking", dss_63.ground_station_id,
             beta_endpoint.source_endpoint_id, "link-beta", :tracking, ~U[2026-06-17 12:01:00Z],
             [replay_run_id: replay_run_id]},
            {"antenna-pointing-other-replay-stowed", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :stowed, ~U[2026-06-17 12:01:15Z],
             [replay_run_id: other_replay_run_id]},
            {"antenna-pointing-replay-tracking", dss_14.ground_station_id,
             alpha_endpoint.source_endpoint_id, "link-alpha", :tracking, ~U[2026-06-17 12:01:30Z],
             [replay_run_id: replay_run_id]}
          ] do
      persist_operational_observable_state_event!(
        org.organization_id,
        mission.mission_id,
        snapshot_id,
        "ground.station.antenna_pointing_state",
        link_id,
        state,
        observed_at,
        Keyword.merge(
          [
            resource_id: ground_station_id,
            scope_kind: :ground_station,
            transport_id: nil,
            source_endpoint_id: source_endpoint_id,
            ground_station_id: ground_station_id
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Antenna Pointing State Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Antenna Pointing State Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["ground.station.antenna_pointing_state"]
            },
            layout: %{x: 0, y: 0, w: 8, h: 4}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id, time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-antenna-pointing-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 "operational_event:operational_observable_snapshot:#{replay_run_id}:antenna-pointing-replay-tracking",
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
  test "live transport scoped operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "transport-operational-connection-state-timeline-viewport",
        display_name: "Transport Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

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

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

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
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

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

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"transport-scope-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"transport-scope-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"transport-scope-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           []},
          {"transport-scope-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z], []},
          {"transport-scope-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"transport-scope-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
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
        name: "Transport Operational Connection State Timeline Browser",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: alpha_transport.transport_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

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
                 "transport",
                 "--expected-scope-id",
                 alpha_transport.transport_id,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
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
  test "live source-endpoint scoped operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-operational-connection-state-timeline-viewport",
        display_name: "Source Endpoint Operational Connection State Timeline Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding(),
               occurred_at: DateTime.add(from_time, -60, :second)
             )

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

    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_14)
    assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, dss_63)

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
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

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

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"source-endpoint-scope-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"source-endpoint-scope-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"source-endpoint-scope-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"source-endpoint-scope-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"source-endpoint-scope-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"source-endpoint-scope-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]}
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
        name: "Source Endpoint Operational Connection State Timeline Browser",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

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
                 "source_endpoint",
                 "--expected-scope-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
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
