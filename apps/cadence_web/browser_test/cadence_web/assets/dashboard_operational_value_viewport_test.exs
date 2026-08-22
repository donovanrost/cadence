# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardOperationalValueViewportTest do
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

  alias Cadence.Comms.{GroundStationStore, TransportStore}

  alias Cadence.Comms.GroundStation
  alias Cadence.Comms.Transport
  alias Cadence.Management.DataSources
  alias Cadence.Dashboards.Placement
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live operational metric value tile DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-metric-value-tile-viewport",
        display_name: "Operational Metric Value Tile Viewport"
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

    for {sample_id, observable_id, value, observed_at} <- [
          {"bitrate-live", "comms.transport.downlink_bitrate", 64_000.0,
           ~U[2026-06-17 12:00:15Z]},
          {"uplink-bitrate-live", "comms.transport.uplink_bitrate", 4_800.0,
           ~U[2026-06-17 12:00:20Z]}
        ] do
      persist_operational_observable_metric_event!(
        org.organization_id,
        mission.mission_id,
        sample_id,
        observable_id,
        alpha_transport.transport_id,
        value,
        observed_at,
        []
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Metric Value Tile Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "Uplink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.uplink_bitrate"]
            },
            layout: %{x: 4, y: 0, w: 4, h: 2}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: alpha_transport.transport_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-value-tile",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-operational-event-id",
                 "operational_event:operational_observable_snapshot:bitrate-live",
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
  test "live unsupported operational observable scope value tile passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-unsupported-scope-value-tile-viewport",
        display_name: "Operational Unsupported Scope Value Tile Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Unsupported Operational Scope Browser",
        widgets: [
          %{
            placement_id: "placement-unsupported-bitrate",
            type: :value_tile,
            title: "Unsupported Mission Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-unsupported-scope-value-tile",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-placement-id",
                 "placement-unsupported-bitrate",
                 "--expected-observable-id",
                 "comms.transport.downlink_bitrate",
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
  test "live unsupported operational observable scope time-series passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-unsupported-scope-time-series-viewport",
        display_name: "Operational Unsupported Scope Time Series Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Unsupported Operational Scope Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-unsupported-bitrate-history",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Unsupported Mission Bitrate History",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.downlink_bitrate"],
                scope_mode: :context,
                sampling: :raw_series,
                overlays: []
              },
              options: %{legend: true}
            }
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-unsupported-scope-time-series",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-placement-id",
                 "placement-unsupported-bitrate-history",
                 "--expected-observable-id",
                 "comms.transport.downlink_bitrate",
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
  test "live operational RF metric value tile DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-rf-metric-value-tile-viewport",
        display_name: "Operational RF Metric Value Tile Viewport"
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

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

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

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-snr-value-1",
      "link.snr_db",
      "link-alpha",
      11.75,
      ~U[2026-06-17 12:00:00Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-ebn0-value-1",
      "link.eb_n0_db",
      "link-alpha",
      8.5,
      ~U[2026-06-17 12:00:15Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-symbol-rate-value-1",
      "link.symbol_rate_sps",
      "link-alpha",
      1_024_000.0,
      ~U[2026-06-17 12:00:30Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    persist_operational_observable_metric_event!(
      org.organization_id,
      mission.mission_id,
      "browser-rf-doppler-value-1",
      "link.doppler_hz",
      "link-alpha",
      -42.5,
      ~U[2026-06-17 12:00:45Z],
      transport_id: alpha_transport.transport_id,
      source_endpoint_id: alpha_endpoint.source_endpoint_id,
      ground_station_id: dss_14.ground_station_id,
      link_id: "link-alpha"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational RF Metric Value Tile Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "RF SNR",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "RF Eb/N0",
            binding: %{
              source: :operational_observables,
              observables: ["link.eb_n0_db"]
            },
            layout: %{x: 4, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "RF Symbol Rate",
            binding: %{
              source: :operational_observables,
              observables: ["link.symbol_rate_sps"]
            },
            layout: %{x: 8, y: 0, w: 4, h: 2}
          },
          %{
            type: :value_tile,
            title: "RF Doppler",
            binding: %{
              source: :operational_observables,
              observables: ["link.doppler_hz"]
            },
            layout: %{x: 0, y: 2, w: 4, h: 2}
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
                 "operational-rf-metric-value-tile",
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
  test "live operational metric missing snapshot value tile passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-metric-missing-snapshot-viewport",
        display_name: "Operational Metric Missing Snapshot Viewport"
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

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Metric Missing Snapshot Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Downlink Bitrate",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.downlink_bitrate"]
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: beta_transport.transport_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-missing-snapshot-value-tile",
                 "--expected-link-id",
                 "link-beta",
                 "--expected-source-endpoint-id",
                 beta_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 beta_transport.transport_id,
                 "--expected-ground-station-id",
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

  @tag :browser_smoke
  test "live authenticated dashboard route renders repeated placements through browser grid smoke",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "repeat-render-viewport",
        display_name: "Repeat Render Viewport"
      )

    spacecraft_alpha = TestFixtures.persist_spacecraft!(mission, display_name: "SC Repeat Alpha")
    spacecraft_beta = TestFixtures.persist_spacecraft!(mission, display_name: "SC Repeat Beta")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft_alpha.spacecraft_id, 31, 1_700_000_290)
    ingest!(mission, binding_set, spacecraft_beta.spacecraft_id, 41, 1_700_000_300)

    dashboard =
      persist_repeated_dashboard_document!(org, mission, [
        spacecraft_alpha.spacecraft_id,
        spacecraft_beta.spacecraft_id
      ])

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <> ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    expected_repeat_ids =
      [
        repeated_placement_id("placement-repeat", spacecraft_alpha.spacecraft_id),
        repeated_placement_id("placement-repeat", spacecraft_beta.spacecraft_id)
      ]
      |> Enum.sort()
      |> Enum.join(",")

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "repeat-render",
                 "--url",
                 dashboard_url,
                 "--login-url",
                 base_url <> ~p"/sign-in",
                 "--login-email",
                 user.email,
                 "--login-password",
                 TestFixtures.default_password(),
                 "--expected-repeat-ids",
                 expected_repeat_ids
               ],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end
end
