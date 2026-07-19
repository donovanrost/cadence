# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardRuntimeScopeViewportTest do
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
  alias Cadence.Contacts.LinkAssignment
  alias Cadence.Contacts.PathTemplate
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live source-endpoint runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-runtime-context-batch",
        display_name: "Source Endpoint Runtime Context Batch"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Context")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 31, 1_700_000_090)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 32, 1_700_000_100)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-source-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Context Alpha",
        source_ref: "browser-context-alpha",
        metadata: %{"ground_station_id" => "browser-context-dss-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-source-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Context Beta",
        source_ref: "browser-context-beta",
        metadata: %{"ground_station_id" => "browser-context-dss-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join([alpha_endpoint.source_endpoint_id, beta_endpoint.source_endpoint_id], ",")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-source-endpoint-batch",
                 "--context-search-query",
                 "browser-context",
                 "--expected-context-source-endpoint-ids",
                 scope_ids,
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
  test "live contact runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-runtime-context-batch",
        display_name: "Contact Runtime Context Batch"
      )

    _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Contact Context")

    alpha_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-context-contact-alpha",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-context-contact-source-alpha"],
        paths: contact_paths("browser-context-contact-source-alpha"),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z]
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-context-contact-beta",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-context-contact-source-beta"],
        paths: contact_paths("browser-context-contact-source-beta"),
        starts_at: ~U[2026-06-30 12:09:00Z],
        ends_at: ~U[2026-06-30 12:16:00Z]
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join([alpha_contact.scheduled_contact_id, beta_contact.scheduled_contact_id], ",")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-contact-batch",
                 "--context-search-query",
                 "browser-context-contact",
                 "--expected-context-contact-ids",
                 scope_ids,
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
  test "live ground-station runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ground-station-runtime-context-batch",
        display_name: "Ground Station Runtime Context Batch"
      )

    _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Ground Context")

    alpha_ground_station =
      GroundStation.new(%{
        ground_station_id: "browser-context-ground-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Context Ground Alpha",
        provider: "browser-ground-provider",
        region: "west"
      })

    beta_ground_station =
      GroundStation.new(%{
        ground_station_id: "browser-context-ground-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Context Ground Beta",
        provider: "browser-ground-provider",
        region: "east"
      })

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, alpha_ground_station)

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, beta_ground_station)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ground Station Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join(
        [
          alpha_ground_station.ground_station_id,
          beta_ground_station.ground_station_id
        ],
        ","
      )

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-ground-station-batch",
                 "--context-search-query",
                 "browser-context-ground",
                 "--expected-context-ground-station-ids",
                 scope_ids,
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
  test "live link runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "link-runtime-context-batch",
        display_name: "Link Runtime Context Batch"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Link Context")

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-link-source-alpha",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Browser Context Link Source Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-context-link-source-beta",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Browser Context Link Source Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_template =
      PathTemplate.new(%{
        path_template_id: "browser-context-link-template-alpha",
        mission_id: mission.mission_id,
        path_id: "browser-context-link-path-alpha",
        direction: :downlink,
        selection_role: :selected
      })

    beta_template =
      PathTemplate.new(%{
        path_template_id: "browser-context-link-template-beta",
        mission_id: mission.mission_id,
        path_id: "browser-context-link-path-beta",
        direction: :downlink,
        selection_role: :selected
      })

    assert {:ok, _path_template} =
             Cadence.persist_path_template(org.organization_id, alpha_template)

    assert {:ok, _path_template} =
             Cadence.persist_path_template(org.organization_id, beta_template)

    alpha_link =
      LinkAssignment.new(%{
        link_assignment_id: "browser-context-link-alpha",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: alpha_endpoint.source_endpoint_id,
        path_template_id: alpha_template.path_template_id,
        path_template_version: alpha_template.version,
        direction: alpha_template.direction,
        selection_role: alpha_template.selection_role,
        provider_path_ref: "browser-link-alpha"
      })

    beta_link =
      LinkAssignment.new(%{
        link_assignment_id: "browser-context-link-beta",
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: beta_endpoint.source_endpoint_id,
        path_template_id: beta_template.path_template_id,
        path_template_version: beta_template.version,
        direction: beta_template.direction,
        selection_role: beta_template.selection_role,
        provider_path_ref: "browser-link-beta"
      })

    assert {:ok, _link_assignment} =
             Cadence.persist_link_assignment(org.organization_id, alpha_link)

    assert {:ok, _link_assignment} =
             Cadence.persist_link_assignment(org.organization_id, beta_link)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Link Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids = Enum.join([alpha_link.link_assignment_id, beta_link.link_assignment_id], ",")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-link-batch",
                 "--context-search-query",
                 "browser-context-link",
                 "--expected-context-link-ids",
                 scope_ids,
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
  test "live spacecraft runtime context batch selection passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "spacecraft-runtime-context-batch",
        display_name: "Spacecraft Runtime Context Batch"
      )

    alpha_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-context-spacecraft-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Context Spacecraft Alpha"
      })

    beta_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-context-spacecraft-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Context Spacecraft Beta"
      })

    assert {:ok, alpha_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, alpha_spacecraft)

    assert {:ok, beta_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, beta_spacecraft)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Spacecraft Runtime Context Batch Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :context,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 8, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    scope_ids =
      Enum.join([alpha_spacecraft.spacecraft_id, beta_spacecraft.spacecraft_id], ",")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "runtime-context-spacecraft-batch",
                 "--context-search-query",
                 "Browser Context Spacecraft",
                 "--expected-context-spacecraft-ids",
                 scope_ids,
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
