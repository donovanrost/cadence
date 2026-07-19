# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardOperationalQueueViewportTest do
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
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live operational command queue depth evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "command-queue-depth-viewport",
        display_name: "Command Queue Depth Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-command-queue-pending-1",
      "browser-command-endpoint-alpha"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-command-queue-pending-2",
      "browser-command-endpoint-beta"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-command-queue-released",
      "browser-command-endpoint-alpha",
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Command Queue Depth Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "mission", scope_id: mission.mission_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-command-queue-depth",
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
  test "live source-endpoint scoped operational command queue depth passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-command-queue-depth-viewport",
        display_name: "Source Endpoint Command Queue Depth Viewport"
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
        source_endpoint_id: "browser-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-command-queue-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-scoped-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Command Queue Depth Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
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
                 "operational-command-queue-depth",
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
  test "live multi-spacecraft operational command queue depth passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-spacecraft-command-queue-depth-viewport",
        display_name: "Multi Spacecraft Command Queue Depth Viewport"
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

    alpha_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-command-spacecraft-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Command Spacecraft Alpha"
      })

    beta_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-command-spacecraft-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Command Spacecraft Beta"
      })

    assert {:ok, alpha_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, alpha_spacecraft)

    assert {:ok, beta_spacecraft} =
             Cadence.persist_spacecraft(org.organization_id, beta_spacecraft)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-pending-alpha",
      "browser-spacecraft-command-endpoint-alpha",
      :pending,
      spacecraft_id: alpha_spacecraft.spacecraft_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-pending-beta",
      "browser-spacecraft-command-endpoint-beta",
      :pending,
      spacecraft_id: beta_spacecraft.spacecraft_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-pending-gamma",
      "browser-spacecraft-command-endpoint-gamma",
      :pending,
      spacecraft_id: "browser-command-spacecraft-gamma"
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-spacecraft-command-queue-released-alpha",
      "browser-spacecraft-command-endpoint-alpha",
      :released,
      spacecraft_id: alpha_spacecraft.spacecraft_id
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Multi Spacecraft Command Queue Depth Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
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
    scope_ids = "#{alpha_spacecraft.spacecraft_id},#{beta_spacecraft.spacecraft_id}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-command-queue-depth",
                 "--expected-mission-id",
                 mission.mission_id,
                 "--expected-command-queue-depth",
                 "2",
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
  test "live source-endpoint scoped operational command queue value tile passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-command-queue-value-tile-viewport",
        display_name: "Source Endpoint Command Queue Value Tile Viewport"
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
        source_endpoint_id: "browser-value-tile-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Value Tile Command Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-value-tile-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Value Tile Command Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    persist_command_queue_entry!(
      org,
      mission,
      "browser-value-tile-command-queue-pending-alpha",
      alpha_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-value-tile-command-queue-pending-beta",
      beta_endpoint.source_endpoint_id
    )

    persist_command_queue_entry!(
      org,
      mission,
      "browser-value-tile-command-queue-released-alpha",
      alpha_endpoint.source_endpoint_id,
      :released
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Command Queue Value Tile Browser",
        widgets: [
          %{
            type: :value_tile,
            title: "Command Queue Depth",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-command-queue-value-tile",
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
end
