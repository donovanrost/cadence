# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardContactScopeViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.GroundStationStore

  alias Cadence.Comms.GroundStation
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.DataBinding
  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.DataSources
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live spacecraft contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-spacecraft-viewport",
        display_name: "Contact Phase Spacecraft Viewport"
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
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_id: "browser-contact-phase-spacecraft-alpha",
        display_name: "Contact Phase Alpha"
      )

    beta_spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_id: "browser-contact-phase-spacecraft-beta",
        display_name: "Contact Phase Beta"
      )

    alpha_contact_id = "browser-contact-phase-spacecraft-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-spacecraft-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-spacecraft-beta-contact"

    alpha_endpoint_ref = "browser-contact-phase-spacecraft-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-spacecraft-source-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: alpha_endpoint_ref,
        mission_id: mission.mission_id,
        spacecraft_id: alpha_spacecraft.spacecraft_id,
        display_name: "Contact Phase Spacecraft Source Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: beta_endpoint_ref,
        mission_id: mission.mission_id,
        spacecraft_id: beta_spacecraft.spacecraft_id,
        display_name: "Contact Phase Spacecraft Source Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               org.organization_id,
               alpha_scheduled_contact
             )

    assert {:ok, _realized_contact} =
             Cadence.Contacts.persist_realized_contact(
               org.organization_id,
               alpha_realized_contact
             )

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Spacecraft Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: alpha_spacecraft.spacecraft_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-spacecraft-timeline",
                 "--expected-spacecraft-id",
                 alpha_spacecraft.spacecraft_id,
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--expected-realized-contact-id",
                 alpha_realized_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
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
  test "live source-endpoint contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-source-endpoint-viewport",
        display_name: "Contact Phase Source Endpoint Viewport"
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

    alpha_contact_id = "browser-contact-phase-source-endpoint-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-source-endpoint-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-source-endpoint-beta-contact"

    alpha_endpoint_ref = "browser-contact-phase-source-endpoint-alpha"
    beta_endpoint_ref = "browser-contact-phase-source-endpoint-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: alpha_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Source Endpoint Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: beta_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Source Endpoint Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               org.organization_id,
               alpha_scheduled_contact
             )

    assert {:ok, _realized_contact} =
             Cadence.Contacts.persist_realized_contact(
               org.organization_id,
               alpha_realized_contact
             )

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Source Endpoint Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: alpha_endpoint_ref}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-source-endpoint-timeline",
                 "--expected-source-endpoint-id",
                 alpha_endpoint_ref,
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--expected-realized-contact-id",
                 alpha_realized_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
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
  test "live ground-station contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-ground-station-viewport",
        display_name: "Contact Phase Ground Station Viewport"
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

    alpha_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-ground-station-alpha",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Alpha",
        provider: "DSN",
        region: "Alpha"
      })

    beta_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-ground-station-beta",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Beta",
        provider: "DSN",
        region: "Beta"
      })

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(
               org.organization_id,
               alpha_station
             )

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(
               org.organization_id,
               beta_station
             )

    alpha_contact_id = "browser-contact-phase-ground-station-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-ground-station-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-ground-station-beta-contact"

    alpha_endpoint_ref = "browser-contact-phase-ground-station-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-ground-station-source-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: alpha_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Source Alpha",
        metadata: %{"ground_station_id" => alpha_station.ground_station_id}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: beta_endpoint_ref,
        mission_id: mission.mission_id,
        display_name: "Contact Phase Ground Station Source Beta",
        metadata: %{"ground_station_id" => beta_station.ground_station_id}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               org.organization_id,
               alpha_scheduled_contact
             )

    assert {:ok, _realized_contact} =
             Cadence.Contacts.persist_realized_contact(
               org.organization_id,
               alpha_realized_contact
             )

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Ground Station Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_id: alpha_station.ground_station_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-ground-station-timeline",
                 "--expected-ground-station-id",
                 alpha_station.ground_station_id,
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--expected-realized-contact-id",
                 alpha_realized_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
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
  test "live multi-source-endpoint contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-multi-source-endpoint-viewport",
        display_name: "Contact Phase Multi Source Endpoint Viewport"
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

    alpha_endpoint_ref = "browser-contact-phase-multi-source-endpoint-alpha"
    beta_endpoint_ref = "browser-contact-phase-multi-source-endpoint-beta"
    gamma_endpoint_ref = "browser-contact-phase-multi-source-endpoint-gamma"

    for {endpoint_ref, display_name} <- [
          {alpha_endpoint_ref, "Contact Phase Multi Source Endpoint Alpha"},
          {beta_endpoint_ref, "Contact Phase Multi Source Endpoint Beta"},
          {gamma_endpoint_ref, "Contact Phase Multi Source Endpoint Gamma"}
        ] do
      endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: endpoint_ref,
          mission_id: mission.mission_id,
          display_name: display_name
        })

      assert {:ok, _source_endpoint} =
               Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, endpoint)
    end

    alpha_contact_id = "browser-contact-phase-multi-source-endpoint-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-multi-source-endpoint-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-multi-source-endpoint-beta-contact"
    gamma_contact_id = "browser-contact-phase-multi-source-endpoint-gamma-contact"

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    gamma_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: gamma_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [gamma_endpoint_ref],
        paths: contact_paths(gamma_endpoint_ref),
        starts_at: ~U[2026-06-30 12:03:00Z],
        ends_at: ~U[2026-06-30 12:06:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               org.organization_id,
               alpha_scheduled_contact
             )

    assert {:ok, _realized_contact} =
             Cadence.Contacts.persist_realized_contact(
               org.organization_id,
               alpha_realized_contact
             )

    for contact <- [beta_contact, gamma_contact] do
      assert {:ok, _scheduled_contact} =
               Cadence.Contacts.persist_scheduled_contact(org.organization_id, contact)
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Multi Source Endpoint Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
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
    scope_ids = Enum.join([alpha_endpoint_ref, beta_endpoint_ref], ",")

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-multi-source-endpoint-timeline",
                 "--expected-contact-ids",
                 Enum.join([alpha_contact_id, beta_contact_id], ","),
                 "--excluded-contact-id",
                 gamma_contact_id,
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
  test "live multi-ground-station contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-multi-ground-station-viewport",
        display_name: "Contact Phase Multi Ground Station Viewport"
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

    alpha_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-multi-ground-station-alpha",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Multi Ground Station Alpha",
        provider: "DSN",
        region: "Alpha"
      })

    beta_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-multi-ground-station-beta",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Multi Ground Station Beta",
        provider: "DSN",
        region: "Beta"
      })

    gamma_station =
      GroundStation.new(%{
        ground_station_id: "browser-contact-phase-multi-ground-station-gamma",
        mission_id: mission.mission_id,
        display_name: "Contact Phase Multi Ground Station Gamma",
        provider: "DSN",
        region: "Gamma"
      })

    for station <- [alpha_station, beta_station, gamma_station] do
      assert {:ok, _ground_station} =
               GroundStationStore.persist_ground_station(
                 org.organization_id,
                 station
               )
    end

    alpha_endpoint_ref = "browser-contact-phase-multi-ground-station-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-multi-ground-station-source-beta"
    gamma_endpoint_ref = "browser-contact-phase-multi-ground-station-source-gamma"

    for {endpoint_ref, station, display_name} <- [
          {alpha_endpoint_ref, alpha_station, "Contact Phase Multi Ground Station Source Alpha"},
          {beta_endpoint_ref, beta_station, "Contact Phase Multi Ground Station Source Beta"},
          {gamma_endpoint_ref, gamma_station, "Contact Phase Multi Ground Station Source Gamma"}
        ] do
      endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: endpoint_ref,
          mission_id: mission.mission_id,
          display_name: display_name,
          metadata: %{"ground_station_id" => station.ground_station_id}
        })

      assert {:ok, _source_endpoint} =
               Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, endpoint)
    end

    alpha_contact_id = "browser-contact-phase-multi-ground-station-alpha-contact"
    alpha_realized_contact_id = "browser-contact-phase-multi-ground-station-alpha-contact-run"
    beta_contact_id = "browser-contact-phase-multi-ground-station-beta-contact"
    gamma_contact_id = "browser-contact-phase-multi-ground-station-gamma-contact"

    alpha_scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: alpha_realized_contact_id
      })

    alpha_realized_contact =
      RealizedContact.new(%{
        realized_contact_id: alpha_realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: alpha_contact_id,
        source_endpoint_refs: [alpha_endpoint_ref],
        paths: contact_paths(alpha_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint_ref],
        paths: contact_paths(beta_endpoint_ref),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    gamma_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: gamma_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [gamma_endpoint_ref],
        paths: contact_paths(gamma_endpoint_ref),
        starts_at: ~U[2026-06-30 12:03:00Z],
        ends_at: ~U[2026-06-30 12:06:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(
               org.organization_id,
               alpha_scheduled_contact
             )

    assert {:ok, _realized_contact} =
             Cadence.Contacts.persist_realized_contact(
               org.organization_id,
               alpha_realized_contact
             )

    for contact <- [beta_contact, gamma_contact] do
      assert {:ok, _scheduled_contact} =
               Cadence.Contacts.persist_scheduled_contact(org.organization_id, contact)
    end

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Multi Ground Station Browser",
        widgets: [
          %{
            type: :state_timeline,
            title: "Contact Phase Timeline",
            binding: %{
              source: :operational_observables,
              observables: ["contacts.phase"]
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
    scope_ids = Enum.join([alpha_station.ground_station_id, beta_station.ground_station_id], ",")

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "ground_station", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-multi-ground-station-timeline",
                 "--expected-contact-ids",
                 Enum.join([alpha_contact_id, beta_contact_id], ","),
                 "--excluded-contact-id",
                 gamma_contact_id,
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
  test "live source-endpoint no-data evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "source-endpoint-no-data-viewport",
        display_name: "Source Endpoint No Data Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Endpoint Empty")
    binding_set = persist_binding_set!(org, mission)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-runtime-empty-endpoint",
        mission_id: mission.mission_id,
        display_name: "Browser Empty Endpoint",
        metadata: %{"ground_station_id" => "dss-browser-empty"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
      source_endpoint_id: "source-endpoint-beta"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Endpoint Empty Browser",
        widgets: [
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 6, h: 3}
          },
          %{
            type: :data_table,
            title: "Counter Rows",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 6, y: 0, w: 6, h: 3}
          },
          %{
            type: :status_matrix,
            title: "Counter Matrix",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 3, w: 6, h: 3}
          },
          %{
            type: :state_timeline,
            title: "Counter Limit State",
            binding: %{
              mode: :fixed,
              source: :limits,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 6, y: 3, w: 6, h: 3}
          },
          %{
            type: :event_timeline,
            title: "Endpoint Events",
            binding: %{mode: :context, source: :events},
            layout: %{x: 0, y: 6, w: 12, h: 3}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: source_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-endpoint-no-data",
                 "--expected-source-endpoint-id",
                 source_endpoint.source_endpoint_id,
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
