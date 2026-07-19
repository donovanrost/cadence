# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardTelemetryFallbackViewportTest do
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
  alias Cadence.Dashboards.SourceWatermarks
  alias Cadence.Dashboards.WidgetDef
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live empty telemetry time-series preserves no-data source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_fresh_watermark/4]
      })
    )

    on_exit(fn ->
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
        slug: "empty-telemetry-time-series-viewport",
        display_name: "Empty Telemetry Time Series Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Empty Series")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Empty Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-empty-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Empty Voltage Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-empty-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
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
    assert output =~ "\"emptyTelemetryTimeSeries\""
  end

  @tag :browser
  test "live empty telemetry value tile preserves no-data source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "empty-telemetry-value-tile-viewport",
        display_name: "Empty Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Empty Tile")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Empty Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-empty-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Empty Voltage Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-empty-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
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
    assert output =~ "\"emptyTelemetryValueTile\""
  end

  @tag :browser
  test "live retention-gap telemetry value tile preserves blocking source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_retention_gap_watermark/4]
      })
    )

    on_exit(fn ->
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
        slug: "retention-gap-telemetry-value-tile-viewport",
        display_name: "Retention Gap Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Retention Tile")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Retention Gap Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-gap-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Retention Gap Voltage Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-retention-gap-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-widget-lifecycle-state",
                 "retention_gap",
                 "--expected-widget-lifecycle-severity",
                 "error",
                 "--expected-widget-warning-code",
                 "retention_gap",
                 "--expected-widget-source-state",
                 "retention_gap",
                 "--expected-widget-source-severity",
                 "error",
                 "--expected-widget-source-warning-code",
                 "retention_gap",
                 "--expected-widget-source-empty-reason",
                 "scope_no_data",
                 "--expected-widget-notice",
                 "This widget cannot load because the selected time range is outside available source retention.",
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
    assert output =~ "\"emptyTelemetryValueTile\""
  end

  @tag :browser
  test "live source-unavailable telemetry value tile preserves blocking source context in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [latest_fun: &browser_source_unavailable_latest/4]
      })
    )

    on_exit(fn ->
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
        slug: "source-unavailable-telemetry-value-tile-viewport",
        display_name: "Source Unavailable Telemetry Value Tile Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Unavailable Tile")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_managed_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_telemetry_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Unavailable Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-unavailable-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "empty-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-source-unavailable-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-widget-lifecycle-state",
                 "error",
                 "--expected-widget-lifecycle-severity",
                 "error",
                 "--expected-widget-warning-code",
                 "source_unavailable",
                 "--expected-widget-source-state",
                 "unavailable",
                 "--expected-widget-source-severity",
                 "error",
                 "--expected-widget-source-warning-code",
                 "source_unavailable",
                 "--expected-widget-source-empty-reason",
                 "",
                 "--expected-widget-notice",
                 "This widget cannot load because its source failed.",
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
    assert output =~ "\"emptyTelemetryValueTile\""
  end

  @tag :browser
  test "live stale telemetry value tile preserves sampled actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "stale-telemetry-value-tile-viewport",
        display_name: "Stale Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Stale Tile")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Stale Counter Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "stale-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-stale-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-id",
                 counter_sample.sample_id,
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
    assert output =~ "\"staleTelemetryValueTile\""
  end

  @tag :browser
  test "live watermarked telemetry value tile renders fresh source context in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "fresh-telemetry-value-tile-viewport",
        display_name: "Fresh Telemetry Value Tile Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Fresh Tile")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    source_watermark_config =
      Application.get_env(:cadence, :dashboard_source_watermark_events, [])

    Application.put_env(
      :cadence,
      :dashboard_source_watermark_events,
      Keyword.put(source_watermark_config, :enabled?, true)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_watermark_events, source_watermark_config)
    end)

    assert {:ok, _watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 complete_through: sample_time,
                 latest_receipt_time: sample_time,
                 retention_starts_at: sample_time,
                 sample_count: 1,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: DateTime.add(sample_time, 1, :second),
                 payload: %{write_id: "browser-fresh-value-tile-watermark"}
               },
               invalidate_runtime_cache?: false
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Fresh Telemetry Value Tile Browser",
        placements: [
          %Placement{
            placement_id: "placement-fresh-value-tile",
            layout: %{x: 0, y: 0, w: 3, h: 2},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.value_tile",
              widget_type_version: 1,
              title: "Fresh Counter Tile",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "fresh-telemetry-value-tile",
                 "--expected-placement-id",
                 "placement-fresh-value-tile",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-id",
                 counter_sample.sample_id,
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
    assert output =~ "\"freshTelemetryValueTile\""
  end

  @tag :browser
  test "live partial telemetry data table preserves returned row actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "partial-telemetry-data-table-viewport",
        display_name: "Partial Telemetry Data Table Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Table")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Partial Telemetry Data Table Browser",
        placements: [
          %Placement{
            placement_id: "placement-partial-data-table",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              widget_type_version: 1,
              title: "Partial Counter Table",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "partial-telemetry-data-table",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-sample-id",
                 counter_sample.sample_id,
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
    assert output =~ "\"partialTelemetryDataTable\""
  end

  @tag :browser
  test "live partial telemetry status matrix preserves returned row actions in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "partial-telemetry-status-matrix-viewport",
        display_name: "Partial Telemetry Status Matrix Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Matrix")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      15,
      DateTime.to_unix(sample_time, :second)
    )

    [counter_sample] =
      Cadence.telemetry_history(org.organization_id, mission.mission_id, "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Partial Telemetry Status Matrix Browser",
        placements: [
          %Placement{
            placement_id: "placement-partial-status-matrix",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.status_matrix",
              widget_type_version: 1,
              title: "Partial Counter Matrix",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "partial-telemetry-status-matrix",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-sample-id",
                 counter_sample.sample_id,
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
    assert output =~ "\"partialTelemetryStatusMatrix\""
  end

  @tag :browser
  test "live source-unavailable telemetry row widgets preserve blocking source context in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [latest_fun: &browser_source_unavailable_latest/4]
      })
    )

    on_exit(fn ->
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
        slug: "source-unavailable-telemetry-row-widgets-viewport",
        display_name: "Source Unavailable Telemetry Row Widgets Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Unavailable Rows")

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(%DataSource{
               DataSources.default_managed_data_source()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_telemetry_binding()
               | organization_id: org.organization_id,
                 mission_id: mission.mission_id
             })

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Unavailable Telemetry Row Widgets Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-unavailable-data-table",
            layout: %{x: 0, y: 0, w: 6, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.data_table",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Table",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
            }
          },
          %Placement{
            placement_id: "placement-source-unavailable-status-matrix",
            layout: %{x: 6, y: 0, w: 6, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.status_matrix",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Matrix",
              binding: %{
                source: :telemetry,
                observables: ["HK.voltage"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :latest,
                overlays: []
              },
              options: %{}
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "source-unavailable-telemetry-row-widgets",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-data-table-placement-id",
                 "placement-source-unavailable-data-table",
                 "--expected-status-matrix-placement-id",
                 "placement-source-unavailable-status-matrix",
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
    assert output =~ "\"sourceUnavailableTelemetryRowWidgets\""
  end
end
