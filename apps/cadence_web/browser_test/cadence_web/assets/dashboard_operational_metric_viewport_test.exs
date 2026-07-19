# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardOperationalMetricViewportTest do
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
  alias Cadence.Dashboards.DataBinding
  alias Cadence.Dashboards.DataSource
  alias Cadence.Dashboards.DataSources
  alias Cadence.Dashboards.SourceHealth
  alias Cadence.Dashboards.SourceWatermarks
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  defp persist_replay_operational_metric_browser_topology! do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-operational-metric-time-series-viewport",
        display_name: "Replay Operational Metric Time Series Viewport"
      )

    replay_run_id = "browser-operational-metric-replay-run"
    other_replay_run_id = "browser-operational-metric-other-replay-run"
    empty_replay_run_id = "browser-operational-metric-empty-replay-run"
    partial_replay_run_id = "browser-operational-metric-partial-replay-run"
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]
    source_health_config = Application.get_env(:cadence, :dashboard_source_health_events, [])

    source_watermark_config =
      Application.get_env(:cadence, :dashboard_source_watermark_events, [])

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
      :cadence,
      :dashboard_source_watermark_events,
      Keyword.put(source_watermark_config, :enabled?, true)
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_health_events, source_health_config)
      Application.put_env(:cadence, :dashboard_source_watermark_events, source_watermark_config)
    end)

    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, from_time)
    persist_replay_run!(mission, other_replay_run_id, from_time)
    persist_replay_run!(mission, empty_replay_run_id, from_time)
    persist_replay_run!(mission, partial_replay_run_id, from_time)

    assert {:ok, _event, _status} =
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
                 observed_at: ~U[2026-06-17 12:00:50Z],
                 payload: %{
                   probe_kind: "adapter",
                   probe_message:
                     "Replay operational observable schema probe completed with warnings.",
                   connection_test_result: "succeeded",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Replay operational observable adapter responded."
                 }
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, _watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: replay_sources.operational_data_source_id,
                 source_binding_id: replay_sources.operational_binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 complete_through: ~U[2026-06-17 12:01:45Z],
                 latest_receipt_time: ~U[2026-06-17 12:01:45Z],
                 retention_starts_at: ~U[2026-06-17 11:00:00Z],
                 sample_count: 6,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-17 12:01:50Z],
                 payload: %{write_id: "browser-replay-operational-metric-watermark"}
               },
               invalidate_runtime_cache?: false
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

    dss_63 =
      GroundStation.new(%{
        ground_station_id: "dss-63",
        mission_id: mission.mission_id,
        display_name: "Madrid DSS-63",
        provider: "DSN",
        region: "Madrid",
        metadata: %{
          "source_endpoint_id" => "browser-source-endpoint-beta",
          "transport_id" => "browser-transport-beta",
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(org.organization_id, dss_14)

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(org.organization_id, dss_63)

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
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    replay_metric_binding_set =
      persist_application_binding_set!(
        org,
        mission,
        alpha_endpoint.source_endpoint_id,
        suffix: "replay-operational-metric"
      )

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               org.organization_id,
               mission.mission_id,
               replay_metric_binding_set.binding_set_id,
               replay_metric_binding_set.version,
               activated_at: from_time
             )

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
          "ground_station_id" => dss_63.ground_station_id,
          "link_assignment_id" => "link-beta"
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, beta_transport)

    %{
      alpha_endpoint: alpha_endpoint,
      alpha_transport: alpha_transport,
      beta_endpoint: beta_endpoint,
      beta_transport: beta_transport,
      dss_14: dss_14,
      dss_63: dss_63,
      empty_replay_run_id: empty_replay_run_id,
      from_time: from_time,
      mission: mission,
      org: org,
      other_replay_run_id: other_replay_run_id,
      partial_replay_run_id: partial_replay_run_id,
      replay_run_id: replay_run_id,
      to_time: to_time,
      user: user
    }
  end

  defp persist_replay_operational_metric_browser_data!(fixture, sandbox_owner) do
    %{
      alpha_endpoint: alpha_endpoint,
      alpha_transport: alpha_transport,
      beta_endpoint: beta_endpoint,
      beta_transport: beta_transport,
      dss_63: dss_63,
      from_time: from_time,
      mission: mission,
      org: org,
      other_replay_run_id: other_replay_run_id,
      partial_replay_run_id: partial_replay_run_id,
      replay_run_id: replay_run_id,
      to_time: to_time
    } = fixture

    for {sample_id, observable_id, resource_id, value, observed_at, opts} <- [
          {"rf-live", "link.snr_db", "link-alpha", 9.0, ~U[2026-06-17 12:00:10Z], []},
          {"rf-replay-acquired", "link.snr_db", "link-alpha", 12.25, ~U[2026-06-17 12:00:30Z],
           [replay_run_id: replay_run_id]},
          {"rf-beta-replay", "link.snr_db", "link-beta", 6.5, ~U[2026-06-17 12:00:45Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"rf-other-replay", "link.snr_db", "link-alpha", 4.5, ~U[2026-06-17 12:01:00Z],
           [replay_run_id: other_replay_run_id]},
          {"rf-replay-locked", "link.snr_db", "link-alpha", 14.0, ~U[2026-06-17 12:01:30Z],
           [replay_run_id: replay_run_id]},
          {"rf-partial-acquired", "link.snr_db", "link-alpha", 10.5, ~U[2026-06-17 12:00:30Z],
           [replay_run_id: partial_replay_run_id]},
          {"rf-partial-locked", "link.snr_db", "link-alpha", 11.25, ~U[2026-06-17 12:01:30Z],
           [replay_run_id: partial_replay_run_id]},
          {"rf-symbol-rate-live", "link.symbol_rate_sps", "link-alpha", 800_000.0,
           ~U[2026-06-17 12:00:14Z], []},
          {"rf-symbol-rate-replay-acquired", "link.symbol_rate_sps", "link-alpha", 1_024_000.0,
           ~U[2026-06-17 12:00:34Z], [replay_run_id: replay_run_id]},
          {"rf-symbol-rate-beta-replay", "link.symbol_rate_sps", "link-beta", 512_000.0,
           ~U[2026-06-17 12:00:49Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"rf-symbol-rate-other-replay", "link.symbol_rate_sps", "link-alpha", 640_000.0,
           ~U[2026-06-17 12:01:04Z], [replay_run_id: other_replay_run_id]},
          {"rf-symbol-rate-replay-locked", "link.symbol_rate_sps", "link-alpha", 2_048_000.0,
           ~U[2026-06-17 12:01:34Z], [replay_run_id: replay_run_id]},
          {"rf-ebn0-live", "link.eb_n0_db", "link-alpha", 7.0, ~U[2026-06-17 12:00:12Z], []},
          {"rf-ebn0-replay-acquired", "link.eb_n0_db", "link-alpha", 8.25,
           ~U[2026-06-17 12:00:32Z], [replay_run_id: replay_run_id]},
          {"rf-ebn0-beta-replay", "link.eb_n0_db", "link-beta", 5.5, ~U[2026-06-17 12:00:47Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id
           ]},
          {"rf-ebn0-other-replay", "link.eb_n0_db", "link-alpha", 4.0, ~U[2026-06-17 12:01:02Z],
           [replay_run_id: other_replay_run_id]},
          {"rf-ebn0-replay-locked", "link.eb_n0_db", "link-alpha", 9.75, ~U[2026-06-17 12:01:32Z],
           [replay_run_id: replay_run_id]},
          {"bitrate-live", "comms.transport.downlink_bitrate", alpha_transport.transport_id,
           64_000.0, ~U[2026-06-17 12:00:15Z], []},
          {"uplink-bitrate-live", "comms.transport.uplink_bitrate", alpha_transport.transport_id,
           4_800.0, ~U[2026-06-17 12:00:20Z], []},
          {"bitrate-replay-acquired", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 72_000.0, ~U[2026-06-17 12:00:35Z],
           [replay_run_id: replay_run_id]},
          {"uplink-bitrate-replay-acquired", "comms.transport.uplink_bitrate",
           alpha_transport.transport_id, 5_600.0, ~U[2026-06-17 12:00:40Z],
           [replay_run_id: replay_run_id]},
          {"bitrate-beta-replay", "comms.transport.downlink_bitrate", beta_transport.transport_id,
           48_000.0, ~U[2026-06-17 12:00:55Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id,
             link_id: "link-beta"
           ]},
          {"uplink-bitrate-beta-replay", "comms.transport.uplink_bitrate",
           beta_transport.transport_id, 3_200.0, ~U[2026-06-17 12:00:58Z],
           [
             replay_run_id: replay_run_id,
             transport_id: beta_transport.transport_id,
             source_endpoint_id: beta_endpoint.source_endpoint_id,
             ground_station_id: dss_63.ground_station_id,
             link_id: "link-beta"
           ]},
          {"bitrate-other-replay", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 32_000.0, ~U[2026-06-17 12:01:05Z],
           [replay_run_id: other_replay_run_id]},
          {"uplink-bitrate-other-replay", "comms.transport.uplink_bitrate",
           alpha_transport.transport_id, 2_400.0, ~U[2026-06-17 12:01:10Z],
           [replay_run_id: other_replay_run_id]},
          {"ingress-latency-replay-acquired", "ingress.processing_latency_ms",
           alpha_endpoint.source_endpoint_id, 18.5, ~U[2026-06-17 12:00:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]},
          {"ingress-latency-replay-locked", "ingress.processing_latency_ms",
           alpha_endpoint.source_endpoint_id, 21.0, ~U[2026-06-17 12:01:45Z],
           [replay_run_id: replay_run_id, transport_id: nil]},
          {"bitrate-partial-acquired", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 88_000.0, ~U[2026-06-17 12:00:35Z],
           [replay_run_id: partial_replay_run_id]},
          {"bitrate-partial-locked", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 104_000.0, ~U[2026-06-17 12:01:35Z],
           [replay_run_id: partial_replay_run_id]},
          {"bitrate-replay-locked", "comms.transport.downlink_bitrate",
           alpha_transport.transport_id, 96_000.0, ~U[2026-06-17 12:01:35Z],
           [replay_run_id: replay_run_id]},
          {"uplink-bitrate-replay-locked", "comms.transport.uplink_bitrate",
           alpha_transport.transport_id, 8_400.0, ~U[2026-06-17 12:01:40Z],
           [replay_run_id: replay_run_id]}
        ] do
      persist_operational_observable_metric_event!(
        org.organization_id,
        mission.mission_id,
        sample_id,
        observable_id,
        resource_id,
        value,
        observed_at,
        opts
      )
    end

    dashboard =
      persist_replay_operational_metric_time_series_dashboard!(
        org,
        mission,
        alpha_transport.transport_id,
        source_endpoint_id: alpha_endpoint.source_endpoint_id,
        overlays: [:events]
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    Map.merge(fixture, %{
      app_root: app_root,
      base_url: base_url,
      dashboard: dashboard,
      dashboard_url: dashboard_url,
      script: script
    })
  end

  @tag :browser_smoke
  test "live replay operational metric time-series charts use default event-backed readers in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    fixture =
      persist_replay_operational_metric_browser_topology!()
      |> persist_replay_operational_metric_browser_data!(sandbox_owner)

    %{
      alpha_endpoint: alpha_endpoint,
      alpha_transport: alpha_transport,
      app_root: app_root,
      base_url: base_url,
      dashboard: dashboard,
      dashboard_url: dashboard_url,
      dss_14: dss_14,
      empty_replay_run_id: empty_replay_run_id,
      from_time: from_time,
      mission: mission,
      partial_replay_run_id: partial_replay_run_id,
      replay_run_id: replay_run_id,
      script: script,
      to_time: to_time,
      user: user
    } = fixture

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-rf-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:rf-replay-acquired",
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:rf-replay-locked"
                 ]
                 |> Enum.join(","),
                 "--expected-bitrate-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:bitrate-replay-acquired",
                   "operational_event:operational_observable_snapshot:#{replay_run_id}:bitrate-replay-locked"
                 ]
                 |> Enum.join(","),
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: partial_replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {partial_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series-partial",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 partial_replay_run_id,
                 "--expected-rf-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:rf-partial-acquired",
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:rf-partial-locked"
                 ]
                 |> Enum.join(","),
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

    assert {partial_bitrate_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series-partial",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 partial_replay_run_id,
                 "--expected-placement-id",
                 "placement-transport-bitrate-history",
                 "--expected-returned-observable",
                 "comms.transport.downlink_bitrate",
                 "--expected-missing-observable",
                 "comms.transport.uplink_bitrate",
                 "--expected-returned-values",
                 "88000,104000",
                 "--expected-operational-event-ids",
                 [
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:bitrate-partial-acquired",
                   "operational_event:operational_observable_snapshot:#{partial_replay_run_id}:bitrate-partial-locked"
                 ]
                 |> Enum.join(","),
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

    assert partial_bitrate_output =~ "dashboard_viewport_smoke passed"

    empty_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "replay_run", replay_run_id: empty_replay_run_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {no_data_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-replay-time-series-no-data",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
                 "--expected-replay-run-id",
                 empty_replay_run_id,
                 "--url",
                 empty_dashboard_url,
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
  end

  @tag :browser
  test "live archive operational metric time-series no-data widgets preserve source context in browser",
       %{
         conn: _conn,
         sandbox_owner: sandbox_owner
       } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

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
        slug: "archive-operational-metric-no-data-viewport",
        display_name: "Archive Operational Metric No Data Viewport"
      )

    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    flight_operational_source = %DataSource{
      DataSources.default_operational_observables_data_source()
      | data_source_id: "managed_operational_observables_archive_no_data",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        metadata: %{bootstrap_default?: false}
    }

    flight_operational_binding = %DataBinding{
      DataSources.default_flight_operational_observables_binding()
      | binding_id: "archive_operational_observables_no_data",
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :flight,
        data_source_id: flight_operational_source.data_source_id,
        dataset: "operational_observables",
        metadata: %{bootstrap_default?: false}
    }

    assert {:ok, _source} = DataSources.persist_data_source(flight_operational_source)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(flight_operational_binding,
               occurred_at: from_time
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

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, alpha_endpoint)

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

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, alpha_transport)

    dashboard =
      persist_replay_operational_metric_time_series_dashboard!(
        org,
        mission,
        alpha_transport.transport_id,
        source_endpoint_id: alpha_endpoint.source_endpoint_id,
        data_override: %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "operational_observables" => %{
              "data_source_id" => flight_operational_source.data_source_id,
              "source_binding_id" => flight_operational_binding.binding_id
            }
          }
        }
      )

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{scope_kind: "link", scope_id: "link-alpha", time_mode: "archive", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-metric-archive-time-series-no-data",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
                 "--expected-transport-id",
                 alpha_transport.transport_id,
                 "--expected-ground-station-id",
                 dss_14.ground_station_id,
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

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous_source_execution
      |> Keyword.put(:runtime_cache, false)
      |> Keyword.put(:source_result_cache?, false)
      |> Keyword.put(:frame_cache?, false)
      |> Keyword.put(:source_opts, %{
        operational_observables: [
          ingress_processing_latency_history_snapshots_fun:
            &browser_ingress_latency_history_source_unavailable/3
        ]
      })
    )

    assert {unavailable_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "operational-ingress-latency-time-series-source-unavailable",
                 "--expected-link-id",
                 "link-alpha",
                 "--expected-source-endpoint-id",
                 alpha_endpoint.source_endpoint_id,
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

    assert unavailable_output =~ "dashboard_viewport_smoke passed"
    assert unavailable_output =~ "\"operationalIngressLatencyTimeSeriesSourceUnavailable\""
  end
end
