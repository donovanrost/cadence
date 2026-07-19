# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardTelemetryLifecycleViewportTest do
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
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live partial telemetry time-series lifecycle passes browser smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "partial-telemetry-time-series-viewport",
        display_name: "Partial Telemetry Time Series Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Partial Series")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    sample_unix = DateTime.to_unix(sample_time, :second)

    assert {:ok, first_ingest_result} =
             ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, sample_unix)

    assert {:ok, second_ingest_result} =
             ingest!(mission, binding_set, spacecraft.spacecraft_id, 19, sample_unix + 1)

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Partial Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-partial-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Partial Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "partial-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-partial-time-series",
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-empty-observable",
                 "HK.voltage",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
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
    assert output =~ "\"partialTelemetryTimeSeries\""
  end

  @tag :browser
  test "live source-unavailable telemetry time-series blocks chart rendering in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [history_fun: &browser_source_unavailable_history/4]
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
        slug: "source-unavailable-telemetry-time-series-viewport",
        display_name: "Source Unavailable Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Unavailable Series")

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
        name: "Source Unavailable Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-unavailable-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Source Unavailable Voltage Trend",
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
                 "source-unavailable-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-source-unavailable-time-series",
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
    assert output =~ "\"sourceUnavailableTelemetryTimeSeries\""
  end

  @tag :browser
  test "live source-degraded telemetry time-series preserves chart data in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

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
      previous_source_execution
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
      |> Keyword.put(:source_opts, %{
        telemetry: [watermark_fun: &browser_fresh_watermark/4]
      })
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
        slug: "source-degraded-telemetry-time-series-viewport",
        display_name: "Source Degraded Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Source Degraded Series")

    binding_set = persist_binding_set!(org, mission)

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

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               21,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               23,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    assert {:ok, source_health_event, _source_health_status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: DataSources.default_flight_telemetry_binding().binding_id,
                 realm: :flight,
                 dataset: DataSources.default_flight_telemetry_binding().dataset,
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   probe_kind: "connection_test",
                   probe_message: "Telemetry source probe completed with warnings.",
                   connection_test_result: "degraded",
                   connection_test_kind: "questdb",
                   connection_test_message: "QuestDB responded with degraded health."
                 }
               },
               invalidate_runtime_cache?: false
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Degraded Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-source-degraded-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Source Degraded Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
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
                 "source-degraded-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-source-degraded-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-source-health-event-id",
                 source_health_event.source_health_event_id,
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
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
    assert output =~ "\"sourceDegradedTelemetryTimeSeries\""
  end

  @tag :browser
  test "live stale telemetry time-series preserves chart data and source evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_stale_watermark/4]
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
        slug: "stale-telemetry-time-series-viewport",
        display_name: "Stale Telemetry Time Series Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Stale Series")
    binding_set = persist_binding_set!(org, mission)

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

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               31,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               33,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Stale Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-stale-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Stale Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "stale-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-stale-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
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
    assert output =~ "\"staleTelemetryTimeSeries\""
  end

  @tag :browser
  test "live unknown-watermark telemetry time-series preserves chart data and source evidence in browser",
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
        telemetry: [watermark_fun: &browser_unknown_watermark/4]
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
        slug: "unknown-watermark-telemetry-time-series-viewport",
        display_name: "Unknown Watermark Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Unknown Watermark Series")

    binding_set = persist_binding_set!(org, mission)

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

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               41,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               43,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Unknown Watermark Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-unknown-watermark-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Unknown Watermark Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                data_mode: :context,
                value_type: :engineering,
                sampling: :raw_series,
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "unknown-watermark-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-unknown-watermark-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
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
    assert output =~ "\"unknownWatermarkTelemetryTimeSeries\""
  end

  @tag :browser
  test "live retention-gap telemetry time-series preserves chart data and source evidence in browser",
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
        slug: "retention-gap-telemetry-time-series-viewport",
        display_name: "Retention Gap Telemetry Time Series Viewport"
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "SC Retention Gap Series")

    binding_set = persist_binding_set!(org, mission)

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

    assert {:ok, first_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               51,
               DateTime.to_unix(~U[2026-06-16 00:20:00Z])
             )

    assert {:ok, second_ingest_result} =
             ingest!(
               mission,
               binding_set,
               spacecraft.spacecraft_id,
               53,
               DateTime.to_unix(~U[2026-06-16 00:30:00Z])
             )

    assert {:ok, [first_sample]} =
             Cadence.Persistence.telemetry_samples(first_ingest_result.outputs)

    assert {:ok, [second_sample]} =
             Cadence.Persistence.telemetry_samples(second_ingest_result.outputs)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Retention Gap Telemetry Time Series Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-gap-time-series",
            layout: %{x: 0, y: 0, w: 8, h: 4},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Retention Gap Counter Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
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
                 "retention-gap-telemetry-time-series",
                 "--expected-placement-id",
                 "placement-retention-gap-time-series",
                 "--expected-spacecraft-id",
                 spacecraft.spacecraft_id,
                 "--expected-returned-observable",
                 "HK.counter",
                 "--expected-sample-ids",
                 Enum.join([first_sample.sample_id, second_sample.sample_id], ","),
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
    assert output =~ "\"retentionGapTelemetryTimeSeries\""
  end
end
