# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardSourceReadinessViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import Phoenix.LiveViewTest
  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportOperationalFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Dashboards.DataBinding
  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.DataSources
  alias Cadence.Dashboards.Document
  alias Cadence.Dashboards.Placement
  alias Cadence.Dashboards.SourceCredentials
  alias Cadence.Dashboards.SourceHealth
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.OperationalEvents
  alias Cadence.Persistence.Schemas.ReplayRunRow
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live BYO source readiness inventory passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "byo-source-readiness-viewport",
        display_name: "BYO Source Readiness Viewport"
      )

    credentials_ref = "cred-browser-byo-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               data_source_id: "byo-browser-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{
                 endpoint_ref: "endpoint://browser/customer-questdb",
                 http_endpoint: "http://browser-customer-questdb:9000"
               }
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "byo-browser-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :customer_owned,
               credentials_ref: credentials_ref,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://browser/customer-questdb"
               }
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "byo-browser-flight",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "byo-browser-questdb",
               dataset: "flight",
               priority: 0
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: "byo-browser-questdb",
                 source_binding_id: "byo-browser-flight",
                 realm: :flight,
                 dataset: "flight",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   probe_kind: "adapter",
                   probe_message: "QuestDB schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Adapter connection test succeeded.",
                   probe_metadata: %{
                     adapter: "telemetry",
                     storage: "questdb",
                     connection_profile?: true,
                     source_connection_profile: %{
                       credentials_ref: credentials_ref,
                       credential_provider: "questdb",
                       credential_kind: "byo_tsdb_connection",
                       credential_owner: "customer",
                       credential_version: 1,
                       credential_status: "active",
                       data_source_id: "byo-browser-questdb",
                       data_source_kind: "byo_tsdb",
                       data_source_owner: "customer",
                       isolation_level: "customer_owned",
                       endpoint_ref: "endpoint://browser/customer-questdb",
                       http_endpoint: "http://browser-customer-questdb:9000",
                       secret_material?: true,
                       secret_material_fields: ["bearer_token", "headers"]
                     }
                   }
                 }
               },
               invalidate_runtime_cache?: false
             )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"
    data_sources_url = base_url <> ~p"/missions/#{mission.mission_id}/ops/data-sources"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-data-sources",
                 "--interaction-mode",
                 "byo-source-readiness",
                 "--url",
                 data_sources_url,
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
  test "live operational source product publish blocker passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-source-product-readiness-viewport",
        display_name: "Operational Source Product Readiness Viewport"
      )

    for {data_source_id, products} <- [
          {"browser-operational-bitrate-source", [:transport_bitrate_history]},
          {"browser-operational-bitrate-history", [:transport_bitrate_history]},
          {"browser-operational-rf-history", [:link_rf_metric_history]}
        ] do
      assert {:ok, _source} =
               DataSources.persist_data_source(%DataSource{
                 data_source_id: data_source_id,
                 owner: :cadence,
                 kind: :managed_tsdb,
                 adapter: Cadence.Dashboards.Sources.OperationalObservables,
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 isolation_level: :mission_isolated,
                 capabilities: %{
                   latest?: true,
                   range_scan?: true,
                   supported_products: products
                 },
                 metadata: %{storage: :postgres_projection}
               })
    end

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "browser-operational-flight",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :operational_observables,
               data_source_id: "browser-operational-bitrate-source",
               dataset: "operational_observables",
               priority: 0
             })

    document = %Document{
      dashboard_id: "dashboard-operational-source-product-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Operational Source Product Readiness Browser",
      placements: [
        %Placement{
          placement_id: "placement-browser-rf-product-mismatch",
          layout: %{x: 0, y: 0, w: 6, h: 3},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF SNR History",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: []
            },
            options: %{legend: true}
          }
        }
      ]
    }

    assert {:ok, dashboard} = Cadence.Dashboards.persist_document(org.organization_id, document)

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: "link-alpha,link-beta"}}"

    source_inventory_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "browser-operational-bitrate-source", source_binding_id: "browser-operational-flight", logical_source: "operational_observables", realm: "flight", source_dashboard_id: dashboard.dashboard_id, source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "raw_series", supported_sampling: "latest,event_history,raw_series", requested_products: "link_rf", requested_source_products: "link_rf_metric_history", supported_products: "transport_bitrate_history", requested_product_families: "link_rf", supported_product_families: "transport_bitrate"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-source-product-readiness",
                 "--source-inventory-url",
                 source_inventory_url,
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
    assert output =~ "\"operationalSourceProductReadiness\""
  end

  @tag :browser
  test "live operational source product runtime posture passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "operational-source-product-runtime-viewport",
        display_name: "Operational Source Product Runtime Viewport"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "browser-operational-rf-runtime-source",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.OperationalObservables,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest?: true,
                 range_scan?: true,
                 supported_products: [:operational_metric_history]
               },
               metadata: %{storage: :postgres_projection}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "browser-operational-rf-runtime-flight",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :operational_observables,
               data_source_id: "browser-operational-rf-runtime-source",
               dataset: "operational_observables",
               priority: 0
             })

    document = %Document{
      dashboard_id: "dashboard-operational-source-runtime-#{System.unique_integer([:positive])}",
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      name: "Operational Source Product Runtime Browser",
      placements: [
        %Placement{
          placement_id: "placement-browser-rf-product-runtime",
          layout: %{x: 0, y: 0, w: 6, h: 3},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.time_series",
            widget_type_version: 1,
            title: "RF SNR Runtime History",
            binding: %{
              source: :operational_observables,
              observables: ["link.snr_db"],
              scope_mode: :context,
              sampling: :raw_series,
              overlays: []
            },
            options: %{legend: true}
          }
        }
      ]
    }

    assert {:ok, dashboard} = Cadence.Dashboards.persist_document(org.organization_id, document)

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_ids: "link-alpha,link-beta"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-source-product-runtime",
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
    assert output =~ "\"operationalSourceProductRuntime\""
  end

  @tag :browser
  test "live authenticated replay controls preserve replay limit context in browser",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-controls-viewport",
        display_name: "Replay Controls Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay")
    binding_set = persist_binding_set!(org, mission)
    seed_limit_definition!(mission)

    base_unix = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.to_unix(:second)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 25, base_unix)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 26, base_unix + 10)

    [older_sample, latest_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    replay_run_id = "browser-smoke-replay-run"
    persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)

    replay_run =
      Run.new(%{
        replay_run_id: replay_run_id,
        mission_id: mission.mission_id,
        binding_set_id: binding_set.binding_set_id,
        binding_set_version: binding_set.version,
        status: :completed,
        replayed_evidence_count: 2,
        replayed_packet_count: 2,
        replayed_sample_count: 2,
        started_at: DateTime.add(older_sample.receipt_time, -60, :second),
        completed_at: DateTime.add(older_sample.receipt_time, 60, :second)
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))
    insert_replay_telemetry_samples!([older_sample, latest_sample], replay_run_id)
    insert_replay_limit_events!(mission, spacecraft, [older_sample, latest_sample], replay_run_id)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Controls Power",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 0, y: 0, w: 4, h: 2}
          },
          %{
            type: :time_series,
            title: "Counter Trend",
            binding: %{
              mode: :fixed,
              spacecraft_id: spacecraft.spacecraft_id,
              point_id: "HK.counter"
            },
            layout: %{x: 4, y: 0, w: 6, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    trend_widget = render_item_by_title(document, "Counter Trend").widget

    replay_query = %{
      panel: "data_link",
      selected_target: "telemetry_sample",
      selected_id: older_sample.sample_id,
      selected_placement: trend_widget.widget_id,
      selected_time: DateTime.to_unix(older_sample.receipt_time, :millisecond),
      time_mode: "replay_run",
      replay_run_id: replay_run_id,
      limit_mode: "compare",
      from: older_sample.receipt_time |> DateTime.add(-600, :second) |> DateTime.to_iso8601(),
      to: older_sample.receipt_time |> DateTime.add(600, :second) |> DateTime.to_iso8601()
    }

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "replay-limits",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-limit-mode",
                 "compare",
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
  test "live replay mission timeline renders managed runtime operational events in browser",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-managed-runtime-timeline-viewport",
        display_name: "Replay Managed Runtime Timeline Viewport"
      )

    replay_run_id = "browser-managed-runtime-replay-run"
    other_replay_run_id = "browser-managed-runtime-other-replay-run"
    event_time = ~U[2026-06-30 12:06:00Z]

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, event_time)
    persist_replay_run!(mission, other_replay_run_id, event_time)

    assert {:ok, matching_event} =
             managed_action_operational_event(
               org.organization_id,
               mission.mission_id,
               "matching",
               event_time,
               replay_run_id
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _other_event} =
             managed_action_operational_event(
               org.organization_id,
               mission.mission_id,
               "other",
               event_time,
               other_replay_run_id
             )
             |> OperationalEvents.persist_event()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Managed Runtime Timeline",
        widgets: [
          %{
            type: :event_timeline,
            title: "Replay Mission Events",
            binding: %{source: :events, observables: []},
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
            "events" => %{
              "source_binding_id" => replay_sources.events_binding_id
            }
          }
        }
      })

    replay_query = %{
      time_mode: "replay_run",
      replay_run_id: replay_run_id,
      from: event_time |> DateTime.add(-60, :second) |> DateTime.to_iso8601(),
      to: event_time |> DateTime.add(60, :second) |> DateTime.to_iso8601()
    }

    conn = TestFixtures.member_conn(user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"
      )

    render_async(view, 5_000)

    assert has_element?(
             view,
             ~s([data-event-timeline-replay-run-id="#{replay_run_id}"][data-event-timeline-record-id="#{matching_event.event_id}"])
           )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "replay-mission-timeline-managed-runtime",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-event-id",
                 matching_event.event_id,
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
  test "live replay contact interval event timeline DataLinks pass browser smoke",
       %{conn: _conn, sandbox_owner: sandbox_owner} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-contact-interval-timeline-viewport",
        display_name: "Replay Contact Interval Timeline Viewport"
      )

    replay_run_id = "browser-contact-interval-replay-run"
    other_replay_run_id = "browser-contact-interval-other-replay-run"
    contact_id = "browser-replay-contact-alpha"
    other_contact_id = "browser-replay-contact-beta"
    source_endpoint_ref = "browser-replay-source-endpoint-alpha"
    starts_at = ~U[2026-06-30 12:01:00Z]
    ends_at = ~U[2026-06-30 12:04:00Z]

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, starts_at)
    persist_replay_run!(mission, other_replay_run_id, starts_at)

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: contact_id,
        mission_id: mission.mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        paths: contact_paths(source_endpoint_ref),
        starts_at: starts_at,
        ends_at: ends_at
      })

    assert {:ok, _scheduled_contact} =
             Cadence.Contacts.persist_scheduled_contact(org.organization_id, scheduled_contact)

    assert {:ok, matching_event} =
             contact_interval_operational_event(
               org.organization_id,
               mission.mission_id,
               contact_id,
               source_endpoint_ref,
               starts_at,
               ends_at,
               replay_run_id
             )
             |> OperationalEvents.persist_event()

    assert {:ok, _other_event} =
             contact_interval_operational_event(
               org.organization_id,
               mission.mission_id,
               other_contact_id,
               "browser-replay-source-endpoint-beta",
               starts_at,
               ends_at,
               other_replay_run_id
             )
             |> OperationalEvents.persist_event()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Contact Interval Timeline",
        widgets: [
          %{
            type: :event_timeline,
            title: "Replay Contact Events",
            binding: %{source: :events, observables: []},
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
            "events" => %{
              "source_binding_id" => replay_sources.events_binding_id
            }
          }
        }
      })

    replay_query = %{
      time_mode: "replay_run",
      replay_run_id: replay_run_id,
      from: starts_at |> DateTime.add(-60, :second) |> DateTime.to_iso8601(),
      to: ends_at |> DateTime.add(60, :second) |> DateTime.to_iso8601()
    }

    conn = TestFixtures.member_conn(user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"
      )

    render_async(view, 5_000)

    assert has_element?(
             view,
             ~s([data-event-timeline-record-id="#{contact_id}"][data-event-timeline-replay-run-id="#{replay_run_id}"][data-event-timeline-source-binding-id="#{replay_sources.events_binding_id}"])
           )

    refute has_element?(view, ~s([data-event-timeline-record-id="#{other_contact_id}"]))

    assert has_element?(
             view,
             ~s([data-event-timeline-row-link-target="contact"][data-event-timeline-row-link-id="#{contact_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.events_binding_id}"])
           )

    assert has_element?(
             view,
             ~s([data-event-timeline-row-link-target="operational event"][data-event-timeline-row-link-id="#{matching_event.event_id}"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-realm="replay"][phx-value-source-binding-id="#{replay_sources.events_binding_id}"])
           )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{replay_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "replay-contact-interval",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-contact-id",
                 contact_id,
                 "--expected-operational-event-id",
                 matching_event.event_id,
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
end
