# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardConnectionAggregationViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
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

  defp persist_multi_source_endpoint_connection_browser_fixture!(sandbox_owner) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-source-endpoint-operational-connection-state-timeline-viewport",
        display_name: "Multi Source Endpoint Operational Connection State Timeline Viewport"
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

    dss_43 =
      GroundStation.new(%{
        ground_station_id: "dss-43",
        mission_id: mission.mission_id,
        display_name: "Canberra DSS-43",
        provider: "DSN",
        region: "Canberra",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-gamma",
          "transport_id" => "browser-transport-gamma",
          "link_assignment_id" => "link-gamma"
        }
      })

    for station <- [dss_14, dss_63, dss_43] do
      assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, station)
    end

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

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Canberra DSS-43",
        metadata: %{
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for endpoint <- [alpha_endpoint, beta_endpoint, gamma_endpoint] do
      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, endpoint)
    end

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

    gamma_transport =
      Transport.new(%{
        transport_id: "browser-transport-gamma",
        mission_id: mission.mission_id,
        display_name: "Gamma TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "gamma.ground.example",
          "port" => "5002",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => gamma_endpoint.source_endpoint_id,
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for transport <- [alpha_transport, beta_transport, gamma_transport] do
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)
    end

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"multi-source-endpoint-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"multi-source-endpoint-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"multi-source-endpoint-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"multi-source-endpoint-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"multi-source-endpoint-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-source-endpoint-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: nil,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-source-endpoint-gamma-connected", "comms.transport.connection_state",
           gamma_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:02:00Z],
           [
             link_id: "link-gamma",
             transport_id: gamma_transport.transport_id,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
           ]},
          {"multi-source-endpoint-ground-gamma-connected", "ground.station.connection_state",
           dss_43.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:02:15Z],
           [
             link_id: "link-gamma",
             transport_id: nil,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
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
        name: "Multi Source Endpoint Operational Connection State Timeline Browser",
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
    scope_ids = "#{alpha_endpoint.source_endpoint_id},#{beta_endpoint.source_endpoint_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: scope_ids, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    %{
      alpha_endpoint: alpha_endpoint,
      alpha_transport: alpha_transport,
      app_root: app_root,
      base_url: base_url,
      beta_transport: beta_transport,
      dashboard_url: dashboard_url,
      dss_14: dss_14,
      dss_43: dss_43,
      dss_63: dss_63,
      gamma_transport: gamma_transport,
      scope_ids: scope_ids,
      script: script,
      user: user
    }
  end

  @tag :browser
  test "live multi-source-endpoint operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    fixture = persist_multi_source_endpoint_connection_browser_fixture!(sandbox_owner)

    %{
      alpha_endpoint: alpha_endpoint,
      alpha_transport: alpha_transport,
      app_root: app_root,
      base_url: base_url,
      beta_transport: beta_transport,
      dashboard_url: dashboard_url,
      dss_14: dss_14,
      dss_43: dss_43,
      dss_63: dss_63,
      gamma_transport: gamma_transport,
      scope_ids: scope_ids,
      script: script,
      user: user
    } = fixture

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
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
                 "--excluded-transport-id",
                 gamma_transport.transport_id,
                 "--excluded-ground-station-id",
                 dss_43.ground_station_id,
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
  test "live link scoped operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "link-operational-connection-state-timeline-viewport",
        display_name: "Link Operational Connection State Timeline Viewport"
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
          {"link-scope-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"link-scope-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"link-scope-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"link-scope-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"link-scope-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"link-scope-ground-beta-connected", "ground.station.connection_state",
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
        name: "Link Operational Connection State Timeline Browser",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

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
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
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
  test "live multi-transport operational connection state timeline interval evidence passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-transport-operational-connection-state-timeline-viewport",
        display_name: "Multi Transport Operational Connection State Timeline Viewport"
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

    dss_43 =
      GroundStation.new(%{
        ground_station_id: "dss-43",
        mission_id: mission.mission_id,
        display_name: "Canberra DSS-43",
        provider: "DSN",
        region: "Canberra",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-gamma",
          "transport_id" => "browser-transport-gamma",
          "link_assignment_id" => "link-gamma"
        }
      })

    for station <- [dss_14, dss_63, dss_43] do
      assert {:ok, _ground_station} = Cadence.persist_ground_station(org.organization_id, station)
    end

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

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Canberra DSS-43",
        metadata: %{
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for endpoint <- [alpha_endpoint, beta_endpoint, gamma_endpoint] do
      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, endpoint)
    end

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

    gamma_transport =
      Transport.new(%{
        transport_id: "browser-transport-gamma",
        mission_id: mission.mission_id,
        display_name: "Gamma TCP",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "gamma.ground.example",
          "port" => "5002",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => gamma_endpoint.source_endpoint_id,
          "ground_station_id" => dss_43.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    for transport <- [alpha_transport, beta_transport, gamma_transport] do
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)
    end

    for {snapshot_id, observable_id, resource_id, scope_kind, state, observed_at, opts} <- [
          {"multi-transport-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"multi-transport-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"multi-transport-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           []},
          {"multi-transport-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z], []},
          {"multi-transport-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-transport-ground-beta-connected", "ground.station.connection_state",
           dss_63.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:15Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"multi-transport-gamma-connected", "comms.transport.connection_state",
           gamma_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:02:00Z],
           [
             link_id: "link-gamma",
             transport_id: gamma_transport.transport_id,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
           ]},
          {"multi-transport-ground-gamma-connected", "ground.station.connection_state",
           dss_43.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:02:15Z],
           [
             link_id: "link-gamma",
             transport_id: gamma_transport.transport_id,
             source_endpoint_id: gamma_endpoint.source_endpoint_id,
             ground_station_id: dss_43.ground_station_id
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
        name: "Multi Transport Operational Connection State Timeline Browser",
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
            title: "Connection State Rows",
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
    scope_ids = "#{alpha_transport.transport_id},#{beta_transport.transport_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_ids: scope_ids, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

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
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-operational-event-id",
                 "operational_event:connection_state_snapshot:multi-transport-beta-connected",
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
                 "--excluded-transport-id",
                 gamma_transport.transport_id,
                 "--excluded-ground-station-id",
                 dss_43.ground_station_id,
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
  test "live mission aggregate operational connection state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "mission-operational-connection-state-timeline-viewport",
        display_name: "Mission Operational Connection State Timeline Viewport"
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
          {"mission-transport-alpha-connecting", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connecting, ~U[2026-06-17 12:00:30Z], []},
          {"mission-transport-alpha-connected", "comms.transport.connection_state",
           alpha_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:30Z], []},
          {"mission-ground-alpha-disconnected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :disconnected, ~U[2026-06-17 12:00:45Z],
           [transport_id: nil]},
          {"mission-ground-alpha-connected", "ground.station.connection_state",
           dss_14.ground_station_id, :ground_station, :connected, ~U[2026-06-17 12:01:45Z],
           [transport_id: nil]},
          {"mission-transport-beta-connected", "comms.transport.connection_state",
           beta_transport.transport_id, :transport, :connected, ~U[2026-06-17 12:01:00Z],
           [
             link_id: "link-beta",
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"mission-ground-beta-connected", "ground.station.connection_state",
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
        name: "Mission Operational Connection State Timeline Browser",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id, time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mission-operational-connection-state-timeline",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-ground-station-id",
                 dss_63.ground_station_id,
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
