# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardTransportExecutionViewportTest do
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
  alias Cadence.Dashboards.DataSources
  alias Cadence.Dashboards.SourceHealth
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  defp persist_replay_transport_execution_browser_fixture!(sandbox_owner) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-transport-execution-timeline-viewport",
        display_name: "Replay Operational Transport Execution Timeline Viewport"
      )

    replay_run_id = "browser-transport-execution-replay-run"
    other_replay_run_id = "browser-transport-execution-other-replay-run"

    transport_execution_source_event_id =
      "transport-capability-record:transport-execution-replay-alpha-1:#{replay_run_id}"

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution)

    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    on_exit(fn ->
      case previous_source_execution do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_source_execution)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_source_execution, value)
      end

      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)
    end)

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
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

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    for {record_id, transport_id, event_kind, recorded_at, opts} <- [
          {"transport-execution-live-alpha", alpha_transport.transport_id, :initialized,
           ~U[2026-06-17 12:00:05Z], []},
          {"transport-execution-replay-alpha-1", alpha_transport.transport_id, :initialized,
           ~U[2026-06-17 12:00:10Z], [replay_run_id: replay_run_id]},
          {"transport-execution-replay-beta", beta_transport.transport_id, :timer_handled,
           ~U[2026-06-17 12:00:45Z],
           [
             replay_run_id: replay_run_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: "dss-63",
             link_id: "link-beta",
             contact_id: "browser-contact-beta",
             path_id: "browser-uplink-beta"
           ]},
          {"transport-execution-other-replay-alpha", alpha_transport.transport_id, :timer_handled,
           ~U[2026-06-17 12:01:00Z], [replay_run_id: other_replay_run_id]},
          {"transport-execution-replay-alpha-2", alpha_transport.transport_id,
           :transport_event_handled, ~U[2026-06-17 12:01:30Z], [replay_run_id: replay_run_id]}
        ] do
      persist_transport_capability_event!(
        org.organization_id,
        mission.mission_id,
        record_id,
        transport_id,
        event_kind,
        recorded_at,
        Keyword.merge(
          [
            source_endpoint_id: alpha_endpoint.source_endpoint_id,
            ground_station_id: dss_14.ground_station_id,
            link_id: "link-alpha",
            contact_id: "browser-contact-alpha",
            path_id: "browser-uplink-alpha"
          ],
          opts
        )
      )
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Operational Transport Execution Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Transport Execution Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.execution_state"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "transport", scope_id: alpha_transport.transport_id, time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    %{
      alpha_transport: alpha_transport,
      app_root: app_root,
      base_url: base_url,
      dashboard_url: dashboard_url,
      mission: mission,
      org: org,
      previous_source_execution: previous_source_execution,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      script: Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs"),
      transport_execution_source_event_id: transport_execution_source_event_id,
      user: user
    }
  end

  defp persist_live_transport_execution_browser_fixture!(sandbox_owner) do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution)

    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_transport_execution_state_timeline_source_execution_opts()
    )

    on_exit(fn ->
      case previous_source_execution do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_source_execution)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_source_execution, value)
      end

      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-transport-execution-timeline-viewport",
        display_name: "Operational Transport Execution Timeline Viewport"
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

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-source-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Canberra DSS-43",
        metadata: %{
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, gamma_endpoint)

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
          "ground_station_id" => dss_14.ground_station_id,
          "link_assignment_id" => "link-gamma"
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, gamma_transport)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Operational Transport Execution Timeline Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Transport Execution Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["comms.transport.execution_state"]
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

    %{
      alpha_transport: alpha_transport,
      app_root: app_root,
      base_url: base_url,
      beta_transport: beta_transport,
      dashboard: dashboard,
      dashboard_url:
        base_url <>
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: "link-alpha,link-beta"}}",
      gamma_transport: gamma_transport,
      mission: mission,
      org: org,
      script: Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs"),
      user: user
    }
  end

  @tag :browser
  test "live operational transport execution state timeline DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    fixture = persist_live_transport_execution_browser_fixture!(sandbox_owner)

    %{
      alpha_transport: alpha_transport,
      app_root: app_root,
      base_url: base_url,
      beta_transport: beta_transport,
      dashboard: dashboard,
      dashboard_url: dashboard_url,
      gamma_transport: gamma_transport,
      mission: mission,
      org: org,
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
                 "operational-transport-execution-state-timeline",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-scope-ids",
                 "link-alpha,link-beta",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-beta-link-id",
                 "link-beta",
                 "--expected-beta-transport-id",
                 beta_transport.transport_id,
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

    no_data_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-gamma"}}"

    assert {no_data_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-no-data",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-gamma",
                 "--expected-link-id",
                 "link-gamma",
                 "--expected-transport-id",
                 gamma_transport.transport_id,
                 "--url",
                 no_data_dashboard_url,
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

    assert no_data_output =~ "dashboard_viewport_smoke passed"

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_transport_execution_state_timeline_source_unavailable_opts()
    )

    unavailable_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha"}}"

    assert {unavailable_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-source-unavailable",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--url",
                 unavailable_dashboard_url,
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

    assert unavailable_output =~ "dashboard_viewport_smoke passed"

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 3_000_000_000,
        projection: [postgres_projection: 3_000_000_000]
      ]
    )

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      operational_transport_execution_state_timeline_source_execution_opts()
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
    )

    assert {:ok, source_health_event, _source_health_status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: "managed_operational_observables",
                 source_binding_id: "default_flight_operational_observables",
                 realm: :flight,
                 dataset: "operational_observables",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: ~U[2026-06-17 12:00:45Z],
                 payload: %{
                   probe_kind: "adapter",
                   probe_message:
                     "Transport execution state schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Transport execution state adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    Cadence.reset_runtime_health()

    assert {degraded_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-source-degraded",
                 "--expected-scope-kind",
                 "link",
                 "--expected-scope-id",
                 "link-alpha",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
                 "--url",
                 unavailable_dashboard_url,
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

    assert degraded_output =~ "dashboard_viewport_smoke passed"
  end

  @tag :browser
  test "live replay operational transport execution state timeline DataLinks pass browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    fixture = persist_replay_transport_execution_browser_fixture!(sandbox_owner)

    %{
      alpha_transport: alpha_transport,
      app_root: app_root,
      base_url: base_url,
      dashboard_url: dashboard_url,
      mission: mission,
      org: org,
      previous_source_execution: previous_source_execution,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      script: script,
      transport_execution_source_event_id: transport_execution_source_event_id,
      user: user
    } = fixture

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 transport_execution_source_event_id,
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

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 3_000_000_000,
        projection: [postgres_projection: 3_000_000_000]
      ]
    )

    assert {:ok, source_health_event, _source_health_status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: replay_sources.operational_data_source_id,
                 source_binding_id: replay_sources.operational_binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: ~U[2026-06-17 12:00:45Z],
                 payload: %{
                   probe_kind: "adapter",
                   probe_message:
                     "Replay transport execution state schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Replay transport execution state adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      (previous_source_execution || [])
      |> Keyword.put(:runtime_cache, false)
      |> Keyword.put(:source_result_cache?, false)
      |> Keyword.put(:frame_cache?, false)
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
    )

    Cadence.reset_runtime_health()

    assert {degraded_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-transport-execution-state-timeline",
                 "--expect-source-degraded",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-operational-event-id",
                 transport_execution_source_event_id,
                 "--expected-data-source-id",
                 replay_sources.operational_data_source_id,
                 "--expected-source-binding-id",
                 replay_sources.operational_binding_id,
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
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

    assert degraded_output =~ "dashboard_viewport_smoke passed"
  end
end
