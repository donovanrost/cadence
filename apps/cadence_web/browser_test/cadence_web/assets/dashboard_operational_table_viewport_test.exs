# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardOperationalTableViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.DataBinding
  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.DataSources
  alias Cadence.Dashboards.Placement
  alias Cadence.Dashboards.SourceHealth
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live operational data table command queue evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "data-table-command-queue-viewport",
        display_name: "Data Table Command Queue Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    persist_command_queue_entry!(
      org,
      mission,
      "browser-data-table-command-queue-pending-1",
      "browser-data-table-command-endpoint-alpha"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-data-table-command-queue-pending-2",
      "browser-data-table-command-endpoint-beta"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-data-table-command-queue-released",
      "browser-data-table-command-endpoint-alpha",
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Command Queue Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Command Queue Table",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-data-table-command-queue",
                 "--expected-mission-id",
                 mission.mission_id,
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
  test "live source-endpoint scoped operational data table command queue passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-data-table-command-queue-viewport",
        display_name: "Source Endpoint Data Table Command Queue Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-data-table-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Data Table Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-data-table-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Data Table Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-data-table-command-queue-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-data-table-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-data-table-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Command Queue Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Command Queue Table",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-data-table-command-queue",
                 "--skip-operational-data-table-interactions",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
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
  test "live mixed operational data table flattens multiple product rows in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "mixed-operational-data-table-viewport",
        display_name: "Mixed Operational Data Table Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-mixed-operational-table-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Mixed Operational Table Endpoint Alpha",
        metadata: %{"ground_station_id" => "dss-mixed-operational-table-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-mixed-operational-table-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Mixed Operational Table Endpoint Beta",
        metadata: %{"ground_station_id" => "dss-mixed-operational-table-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-mixed-operational-table-command-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-mixed-operational-table-command-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-mixed-operational-table-command-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-mixed-operational-table-spacecraft-alpha",
        receipt_time: ~U[2026-07-01 12:00:00Z],
        packet_value: 51,
        sequence_count: 51
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-mixed-operational-table-spacecraft-beta",
        receipt_time: ~U[2026-07-01 12:00:01Z],
        packet_value: 52,
        sequence_count: 52
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Mixed Operational Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Mixed Operational Rows",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth", "ingress.processing_latency_ms"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mixed-operational-data-table",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
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
  test "live stale mixed operational data table preserves row actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "stale-mixed-operational-data-table-viewport",
        display_name: "Stale Mixed Operational Data Table Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-stale-mixed-operational-table-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Stale Mixed Operational Table Endpoint Alpha",
        metadata: %{"ground_station_id" => "dss-stale-mixed-operational-table-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-stale-mixed-operational-table-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Stale Mixed Operational Table Endpoint Beta",
        metadata: %{"ground_station_id" => "dss-stale-mixed-operational-table-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-stale-mixed-operational-table-command-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-stale-mixed-operational-table-command-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-stale-mixed-operational-table-command-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    stale_receipt_time =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:second)

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-stale-mixed-operational-table-spacecraft-alpha",
        receipt_time: stale_receipt_time,
        packet_value: 61,
        sequence_count: 61
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-stale-mixed-operational-table-spacecraft-beta",
        receipt_time: ~U[2026-07-01 12:00:01Z],
        packet_value: 62,
        sequence_count: 62
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Mixed Operational Data Table Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-mixed-operational-data-table",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              title: "Stale Mixed Operational Rows",
              binding: %{
                source: :operational_observables,
                observables: ["commanding.queue_depth", "ingress.processing_latency_ms"],
                scope_mode: :context,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{
                health: %{
                  freshness_policy: %{stale_after_ms: 1000}
                }
              }
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mixed-operational-data-table",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
                 "--expected-widget-lifecycle-state",
                 "stale",
                 "--expected-widget-warning-code",
                 "stale_data",
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
  test "live degraded mixed operational data table preserves source-health handoffs in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    reset_runtime_health!()

    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence,
      :dashboard_source_health_events,
      enabled?: true,
      freshness: [
        default_max_age_ms: 31_536_000_000,
        projection: [postgres_projection: 31_536_000_000]
      ]
    )

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous_source_execution
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)

      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "degraded-mixed-operational-data-table-viewport",
        display_name: "Degraded Mixed Operational Data Table Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-degraded-mixed-operational-table-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Degraded Mixed Operational Table Endpoint Alpha",
        metadata: %{"ground_station_id" => "dss-degraded-mixed-operational-table-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-degraded-mixed-operational-table-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Degraded Mixed Operational Table Endpoint Beta",
        metadata: %{"ground_station_id" => "dss-degraded-mixed-operational-table-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-degraded-mixed-operational-table-command-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-degraded-mixed-operational-table-command-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-degraded-mixed-operational-table-command-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-degraded-mixed-operational-table-spacecraft-alpha",
        receipt_time: ~U[2026-07-01 12:00:00Z],
        packet_value: 71,
        sequence_count: 71
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-degraded-mixed-operational-table-spacecraft-beta",
        receipt_time: ~U[2026-07-01 12:00:01Z],
        packet_value: 72,
        sequence_count: 72
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
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   probe_kind: "adapter",
                   probe_message: "Operational observables schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Operational observables adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Degraded Mixed Operational Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Degraded Mixed Operational Rows",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth", "ingress.processing_latency_ms"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "mixed-operational-data-table",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "1",
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(alpha_latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 alpha_latency_sample.source_event_id,
                 "--expected-widget-source-state",
                 "degraded",
                 "--expected-widget-source-warning-code",
                 "source_degraded",
                 "--expected-row-data-management-badge",
                 "degraded",
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
                 "--expected-command-supported-capability",
                 "operational_latest",
                 "--expected-ingress-supported-capability",
                 "operational_latest",
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
  test "live source-endpoint scoped empty operational data table command queue passes browser smoke",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-empty-data-table-command-queue-viewport",
        display_name: "Source Endpoint Empty Data Table Command Queue Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_operational_observables_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_operational_observables_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-empty-data-table-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Empty Data Table Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-empty-data-table-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Empty Data Table Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-empty-data-table-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-empty-data-table-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Empty Command Queue Data Table Browser",
        widgets: [
          %{
            type: :data_table,
            title: "Command Queue Table",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-data-table-command-queue",
                 "--skip-operational-data-table-interactions",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-command-queue-depth",
                 "0",
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
