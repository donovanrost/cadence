# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardOperationalResourcesViewportTest do
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
  alias Cadence.Management.DataSources
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live source-endpoint operational resource DataLink passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-operational-resource-viewport",
        display_name: "Source Endpoint Operational Resource Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{"ground_station_id" => "dss-63"}
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
          "ground_station_id" => "dss-14"
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
          "ground_station_id" => "dss-63"
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "source-endpoint-transport-connected",
      "comms.transport.connection_state",
      "link-alpha",
      :connected,
      ~U[2026-06-17 12:00:30Z],
      resource_id: alpha_transport.transport_id,
      scope_kind: :transport,
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Resource Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Connection State",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.connection_state"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-endpoint-operational-resource",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-operational-event-id",
                 "operational_event:connection_state_snapshot:source-endpoint-transport-connected",
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
  test "live ground-station operational resource DataLink passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ground-station-operational-resource-viewport",
        display_name: "Ground Station Operational Resource Viewport"
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
          "transport_id" => "browser-transport-alpha"
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
          "transport_id" => "browser-transport-beta"
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
        metadata: %{"ground_station_id" => dss_14.ground_station_id}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Madrid DSS-63",
        metadata: %{"ground_station_id" => dss_63.ground_station_id}
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
          "ground_station_id" => dss_14.ground_station_id
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
          "ground_station_id" => dss_63.ground_station_id
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ground Station Operational Resource Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Connection State",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "ground.station.connection_state"
              ]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: dss_14.ground_station_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "ground-station-operational-resource",
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
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
  test "live link operational resource DataLink passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "link-operational-resource-viewport",
        display_name: "Link Operational Resource Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Goldstone DSS-14",
        metadata: %{
          "ground_station_id" => "dss-14",
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
          "ground_station_id" => "dss-14",
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

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-transport-connected",
      "comms.transport.connection_state",
      "link-alpha",
      :connected,
      ~U[2026-06-17 12:00:25Z],
      resource_id: alpha_transport.transport_id,
      scope_kind: :transport,
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-rf-lock-locked",
      "link.rf_lock_state",
      "link-alpha",
      :locked,
      ~U[2026-06-17 12:00:30Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-beta-rf-lock-unlocked",
      "link.rf_lock_state",
      "link-beta",
      :unlocked,
      ~U[2026-06-17 12:00:32Z],
      transport_id: beta_transport.transport_id,
      source_endpoint_id: beta_endpoint.source_endpoint_id,
      ground_station_id: "dss-63"
    )

    persist_operational_observable_state_event!(
      org.organization_id,
      mission.mission_id,
      "link-frame-sync-synchronized",
      "link.frame_sync_state",
      "link-alpha",
      :synchronized,
      ~U[2026-06-17 12:00:35Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: "dss-14"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Link Operational Resource Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "RF State",
            binding: %{
              source: :operational_observables,
              observables: ["link.rf_lock_state", "link.frame_sync_state"]
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          },
          %{
            type: :data_table,
            title: "Operational State Rows",
            binding: %{
              source: :operational_observables,
              observables: [
                "comms.transport.connection_state",
                "link.rf_lock_state",
                "link.frame_sync_state"
              ]
            },
            layout: %{x: 0, y: 3, w: 8, h: 4}
          }
        ]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    scope_ids = "link-alpha,link-beta"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "link-operational-resource",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-scope-ids",
                 scope_ids,
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 "dss-14",
                 "--expected-connection-operational-event-id",
                 "operational_event:connection_state_snapshot:link-transport-connected",
                 "--expected-operational-event-id",
                 "operational_event:link_rf_lock_state_snapshot:link-rf-lock-locked",
                 "--expected-frame-sync-operational-event-id",
                 "operational_event:link_frame_sync_state_snapshot:link-frame-sync-synchronized",
                 "--expected-beta-link-id",
                 "link-beta",
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
                 "--expected-beta-operational-event-id",
                 "operational_event:link_rf_lock_state_snapshot:link-beta-rf-lock-unlocked",
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
