# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardIngressLatencyViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.DataBinding
  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.DataSources
  alias Cadence.Dashboards.Placement
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live operational ingress latency evidence passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ingress-latency-viewport",
        display_name: "Ingress Latency Viewport"
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
        source_endpoint_id: "browser-ingress-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Alpha",
        metadata: %{"ground_station_id" => "dss-ingress-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Beta",
        metadata: %{"ground_station_id" => "dss-ingress-beta"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.Runtime.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:00:00Z],
        packet_value: 31,
        sequence_count: 1
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-spacecraft-beta",
        receipt_time: ~U[2026-06-30 12:00:01Z],
        packet_value: 32,
        sequence_count: 2
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ingress Latency Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
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
                 "operational-ingress-latency",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
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
  test "live contact-scoped operational ingress latency passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "contact-ingress-latency-viewport",
        display_name: "Contact Ingress Latency Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_contact_id = "browser-ingress-contact-alpha"
    beta_contact_id = "browser-ingress-contact-beta"

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-contact-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Contact Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-contact-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Contact Beta"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    alpha_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: alpha_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [alpha_endpoint.source_endpoint_id],
        paths: contact_paths(alpha_endpoint.source_endpoint_id),
        starts_at: ~U[2026-06-30 12:00:00Z],
        ends_at: ~U[2026-06-30 12:08:00Z],
        lifecycle_state: :scheduled
      })

    beta_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: beta_contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [beta_endpoint.source_endpoint_id],
        paths: contact_paths(beta_endpoint.source_endpoint_id),
        starts_at: ~U[2026-06-30 12:01:00Z],
        ends_at: ~U[2026-06-30 12:09:00Z],
        lifecycle_state: :scheduled
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, alpha_contact)

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, beta_contact)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.Runtime.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    alpha_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        contact_id: alpha_contact_id,
        spacecraft_id: "browser-ingress-contact-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:03:00Z],
        packet_value: 51,
        sequence_count: 1
      )

    _beta_latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        contact_id: beta_contact_id,
        spacecraft_id: "browser-ingress-contact-spacecraft-beta",
        receipt_time: ~U[2026-06-30 12:03:01Z],
        packet_value: 52,
        sequence_count: 2
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Contact Ingress Latency Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Contact Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "contact", scope_id: alpha_contact_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-contact",
                 "--expected-contact-id",
                 alpha_contact_id,
                 "--excluded-contact-id",
                 beta_contact_id,
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
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
  test "live multi-spacecraft operational ingress latency passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "multi-spacecraft-ingress-latency-viewport",
        display_name: "Multi Spacecraft Ingress Latency Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    alpha_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-ingress-scope-spacecraft-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Spacecraft Alpha"
      })

    beta_spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "browser-ingress-scope-spacecraft-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Spacecraft Beta"
      })

    assert {:ok, alpha_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, alpha_spacecraft)

    assert {:ok, beta_spacecraft} =
             Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, beta_spacecraft)

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-scope-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Alpha"
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-scope-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Beta"
      })

    gamma_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-scope-endpoint-gamma",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Scope Gamma"
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, gamma_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.Runtime.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    _alpha_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: alpha_spacecraft.spacecraft_id,
        receipt_time: ~U[2026-06-30 12:02:00Z],
        packet_value: 41,
        sequence_count: 1
      )

    _beta_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: beta_spacecraft.spacecraft_id,
        receipt_time: ~U[2026-06-30 12:02:01Z],
        packet_value: 42,
        sequence_count: 2
      )

    _gamma_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        gamma_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-scope-spacecraft-gamma",
        receipt_time: ~U[2026-06-30 12:02:02Z],
        packet_value: 43,
        sequence_count: 3
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Multi Spacecraft Ingress Latency Browser",
        widgets: [
          %{
            type: :status_matrix,
            title: "Ingress Latency",
            binding: %{
              source: :operational_observables,
              observables: ["ingress.processing_latency_ms"]
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

    source_endpoint_ids =
      "#{alpha_endpoint.source_endpoint_id},#{beta_endpoint.source_endpoint_id}"

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
                 "operational-ingress-latency-multi-spacecraft",
                 "--expected-source-endpoint-ids",
                 source_endpoint_ids,
                 "--excluded-source-endpoint-id",
                 gamma_endpoint.source_endpoint_id,
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
  test "live operational ingress latency time-series passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "ingress-latency-timeseries-viewport",
        display_name: "Ingress Latency Time-Series Viewport"
      )

    from_time = ~U[2026-06-30 12:00:00Z]
    to_time = ~U[2026-06-30 12:01:00Z]

    flight_operational_source = %DataSource{
      DataSources.default_operational_observables_data_source()
      | data_source_id: "managed_operational_observables_ingress_time_series",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        metadata: %{bootstrap_default?: false}
    }

    flight_operational_binding = %DataBinding{
      DataSources.default_flight_operational_observables_binding()
      | binding_id: "flight_operational_observables_ingress_time_series",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        data_source_id: flight_operational_source.data_source_id,
        metadata: %{bootstrap_default?: false}
    }

    assert {:ok, _source} = DataSources.persist_data_source(flight_operational_source)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(flight_operational_binding,
               occurred_at: from_time
             )

    alpha_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-timeseries-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Time-Series Alpha",
        metadata: %{"ground_station_id" => "dss-ingress-timeseries-alpha"}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-timeseries-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Time-Series Beta",
        metadata: %{"ground_station_id" => "dss-ingress-timeseries-beta"}
      })

    empty_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-ingress-timeseries-endpoint-empty",
        mission_id: mission.mission_id,
        display_name: "Browser Ingress Time-Series Empty",
        metadata: %{"ground_station_id" => "dss-ingress-timeseries-empty"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, empty_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.Runtime.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    _alpha_first_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-timeseries-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:00:05Z],
        packet_value: 51,
        sequence_count: 51
      )

    _alpha_second_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-timeseries-spacecraft-alpha",
        receipt_time: ~U[2026-06-30 12:00:25Z],
        packet_value: 52,
        sequence_count: 52
      )

    _beta_latency_ms =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        beta_endpoint.source_endpoint_id,
        spacecraft_id: "browser-ingress-timeseries-spacecraft-beta",
        receipt_time: ~U[2026-06-30 12:00:30Z],
        packet_value: 53,
        sequence_count: 53
      )

    ingress_evidence_binding_set =
      persist_application_binding_set!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        suffix: "ingress-timeseries-evidence"
      )

    assert {:ok, _activation} =
             Cadence.Activations.activate_binding_set(
               org.organization_id,
               mission.mission_id,
               ingress_evidence_binding_set.binding_set_id,
               ingress_evidence_binding_set.version,
               activated_at: from_time
             )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Ingress Latency Time-Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-ingress-latency-history",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            data_override: %{
              "realm" => "flight",
              "source_mode" => "specific",
              "source_contexts" => %{
                "operational_observables" => %{
                  "data_source_id" => flight_operational_source.data_source_id,
                  "source_binding_id" => flight_operational_binding.binding_id
                }
              }
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Ingress Latency History",
              binding: %{
                source: :operational_observables,
                observables: ["ingress.processing_latency_ms"],
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: Enum.join([alpha_endpoint.source_endpoint_id, beta_endpoint.source_endpoint_id], ","), time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-time-series",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-source-endpoint-ids",
                 Enum.join(
                   [alpha_endpoint.source_endpoint_id, beta_endpoint.source_endpoint_id],
                   ","
                 ),
                 "--expected-data-source-id",
                 flight_operational_source.data_source_id,
                 "--expected-source-binding-id",
                 flight_operational_binding.binding_id,
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

    partial_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_ids: Enum.join([alpha_endpoint.source_endpoint_id, empty_endpoint.source_endpoint_id], ","), time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {partial_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-time-series",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-source-endpoint-ids",
                 Enum.join(
                   [alpha_endpoint.source_endpoint_id, empty_endpoint.source_endpoint_id],
                   ","
                 ),
                 "--expected-returned-source-endpoint-ids",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-missing-source-endpoint-ids",
                 empty_endpoint.source_endpoint_id,
                 "--expected-chart-target-ids",
                 Enum.join(
                   [alpha_endpoint.source_endpoint_id, alpha_endpoint.source_endpoint_id],
                   ","
                 ),
                 "--expected-widget-lifecycle-state",
                 "partial",
                 "--expected-widget-source-state",
                 "partial",
                 "--expected-widget-source-data-state",
                 "ready",
                 "--expected-widget-warning-code",
                 "partial_data",
                 "--expected-data-source-id",
                 flight_operational_source.data_source_id,
                 "--expected-source-binding-id",
                 flight_operational_binding.binding_id,
                 "--url",
                 partial_dashboard_url,
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

    assert partial_output =~ "dashboard_viewport_smoke passed"
  end

  @tag :browser
  test "live stale operational data table ingress latency passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    reset_runtime_health!()

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "stale-data-table-ingress-latency-viewport",
        display_name: "Stale Data Table Ingress Latency Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               DataSources.default_flight_operational_observables_binding()
             )

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "browser-stale-ingress-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Browser Stale Ingress Alpha",
        metadata: %{"ground_station_id" => "dss-stale-ingress-alpha"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _activation} =
             Cadence.Runtime.activate_binding_set(
               mission.mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    stale_receipt_time =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:second)

    latency_sample =
      persist_ingress_latency_through_write_path!(
        org,
        mission,
        source_endpoint.source_endpoint_id,
        spacecraft_id: "browser-stale-ingress-spacecraft-alpha",
        receipt_time: stale_receipt_time,
        packet_value: 41,
        sequence_count: 41
      )

    Cadence.reset_runtime_health()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Ingress Latency Data Table Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-data-table-ingress-latency",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              title: "Stale Ingress Latency",
              binding: %{
                source: :operational_observables,
                observables: ["ingress.processing_latency_ms"],
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "source_endpoint", scope_id: source_endpoint.source_endpoint_id}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "stale-operational-data-table-ingress-latency",
                 "--expected-source-endpoint-id",
                 source_endpoint.source_endpoint_id,
                 "--expected-ingress-latency-ms",
                 :erlang.float_to_binary(latency_sample.value, decimals: 6),
                 "--expected-operational-event-id",
                 latency_sample.source_event_id,
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
