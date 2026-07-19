# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardContactPhaseViewportTest do
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

  alias Cadence.Contacts.RealizedContact
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.DataBinding
  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.DataSources
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live contact no-data evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-no-data-viewport",
        display_name: "Contact No Data Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Contact Empty")
    binding_set = persist_binding_set!(org, mission)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-runtime-empty-contact",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["source-endpoint-alpha"],
        paths: contact_paths("source-endpoint-alpha"),
        starts_at: DateTime.from_unix!(1_700_000_080, :second),
        ends_at: DateTime.from_unix!(1_700_000_220, :second)
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100,
      source_endpoint_id: "source-endpoint-beta"
    )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Empty Browser",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: scheduled_contact.scheduled_contact_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "contact-no-data",
                 "--expected-contact-id",
                 scheduled_contact.scheduled_contact_id,
                 "--expected-source-endpoint-id",
                 "source-endpoint-alpha",
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
  test "live contact phase state timeline DataLinks pass browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-timeline-viewport",
        display_name: "Contact Phase Timeline Viewport"
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

    contact_id = "browser-contact-phase-alpha"
    realized_contact_id = "browser-contact-phase-alpha-run"
    source_endpoint_ref = "browser-contact-phase-source-endpoint-alpha"

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: realized_contact_id
      })

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: contact_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-contact-phase-beta",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-contact-phase-source-endpoint-beta"],
        paths: contact_paths("browser-contact-phase-source-endpoint-beta"),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, realized_contact)

    assert {:ok, _beta_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Timeline Browser",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: contact_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-timeline",
                 "--expected-contact-id",
                 contact_id,
                 "--expected-realized-contact-id",
                 realized_contact_id,
                 "--expected-source-endpoint-id",
                 source_endpoint_ref,
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
  test "live replay contact phase state timeline preserves replay context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-replay-timeline-viewport",
        display_name: "Contact Phase Replay Timeline Viewport"
      )

    replay_run_id = "browser-contact-phase-replay-run"
    from_time = ~U[2026-06-30 12:00:00Z]
    to_time = ~U[2026-06-30 12:10:00Z]

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)

    contact_id = "browser-contact-phase-replay-alpha"
    realized_contact_id = "browser-contact-phase-replay-alpha-run"
    source_endpoint_ref = "browser-contact-phase-replay-source-alpha"

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :realized,
        realized_contact_id: realized_contact_id
      })

    realized_contact =
      RealizedContact.new(%{
        realized_contact_id: realized_contact_id,
        mission_id: mission.mission_id,
        scheduled_contact_id: contact_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        initial_time: ~U[2026-06-30 12:01:30Z],
        realized_at: ~U[2026-06-30 12:01:30Z],
        lifecycle_state: :active
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "browser-contact-phase-replay-beta",
        mission_id: mission.mission_id,
        source_endpoint_refs: ["browser-contact-phase-replay-source-beta"],
        paths: contact_paths("browser-contact-phase-replay-source-beta"),
        starts_at: ~U[2026-06-30 12:02:00Z],
        ends_at: ~U[2026-06-30 12:05:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, realized_contact)

    assert {:ok, _beta_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Contact Phase Timeline Browser",
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

    dashboard =
      persist_dashboard_defaults!(org, mission, dashboard, %{
        "data" => %{
          "realm" => "replay",
          "source_mode" => "specific",
          "source_contexts" => %{
            "operational_observables" => %{
              "data_source_id" => replay_sources.operational_data_source_id,
              "source_binding_id" => replay_sources.operational_binding_id,
              "dataset" => "operational_observables_replay"
            }
          }
        }
      })

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: contact_id, time_mode: "replay_run", replay_run_id: replay_run_id, realm: "replay", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-replay-timeline",
                 "--expected-contact-id",
                 contact_id,
                 "--expected-realized-contact-id",
                 realized_contact_id,
                 "--expected-source-endpoint-id",
                 source_endpoint_ref,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-data-source-id",
                 replay_sources.operational_data_source_id,
                 "--expected-source-binding-id",
                 replay_sources.operational_binding_id,
                 "--expected-dataset",
                 "operational_observables_replay",
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
  test "live multi-contact contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-multi-contact-viewport",
        display_name: "Contact Phase Multi Contact Viewport"
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

    alpha_contact_id = "browser-contact-phase-multi-alpha"
    alpha_realized_contact_id = "browser-contact-phase-multi-alpha-run"
    beta_contact_id = "browser-contact-phase-multi-beta"
    gamma_contact_id = "browser-contact-phase-multi-gamma"

    alpha_endpoint_ref = "browser-contact-phase-multi-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-multi-source-beta"
    gamma_endpoint_ref = "browser-contact-phase-multi-source-gamma"

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
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, gamma_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Multi Contact Browser",
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
    scope_ids = Enum.join([alpha_contact_id, beta_contact_id], ",")

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_ids: scope_ids}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-contact-phase-multi-contact-timeline",
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
  test "live mission contact phase state timeline passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-mission-viewport",
        display_name: "Contact Phase Mission Viewport"
      )

    other_mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-phase-other-mission-viewport",
        display_name: "Contact Phase Other Mission Viewport"
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

    alpha_contact_id = "browser-contact-phase-mission-alpha"
    alpha_realized_contact_id = "browser-contact-phase-mission-alpha-run"
    beta_contact_id = "browser-contact-phase-mission-beta"
    gamma_contact_id = "browser-contact-phase-mission-gamma"
    other_contact_id = "browser-contact-phase-mission-other"

    alpha_endpoint_ref = "browser-contact-phase-mission-source-alpha"
    beta_endpoint_ref = "browser-contact-phase-mission-source-beta"
    gamma_endpoint_ref = "browser-contact-phase-mission-source-gamma"
    other_endpoint_ref = "browser-contact-phase-mission-source-other"

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

    other_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: other_contact_id,
        mission_id: other_mission.mission_id,
        source_endpoint_refs: [other_endpoint_ref],
        paths: contact_paths(other_endpoint_ref),
        starts_at: ~U[2026-06-30 12:04:00Z],
        ends_at: ~U[2026-06-30 12:07:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, alpha_scheduled_contact)

    assert {:ok, _realized_contact} =
             Cadence.persist_realized_contact(org.organization_id, alpha_realized_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, beta_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, gamma_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(org.organization_id, other_contact)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Phase Mission Browser",
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
    contact_ids = Enum.join([alpha_contact_id, beta_contact_id, gamma_contact_id], ",")

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
                 "operational-contact-phase-mission-timeline",
                 "--expected-contact-ids",
                 contact_ids,
                 "--excluded-contact-id",
                 other_contact_id,
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
