# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardRevisionScopeViewportTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag sandbox_ownership_timeout: 600_000
  @moduletag timeout: 600_000

  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.DataSources.DataBinding
  alias Cadence.DataSources.DataSource
  alias Cadence.Management.DataSources
  alias Cadence.Dashboards.Placement
  alias Cadence.Projections.DataSources.Watermarks
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.Storage
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live telemetry revision range markers stay scoped to source binding and data view in browser",
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
        slug: "revision-source-binding-isolation-viewport",
        display_name: "Revision Source Binding Isolation Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Revision Binding")
    binding_set = persist_binding_set!(org, mission)
    alternate_binding_id = "alternate_flight_telemetry"

    assert {:ok, _telemetry_source} =
             DataSources.persist_data_source(DataSources.default_managed_data_source())

    assert {:ok, _telemetry_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_telemetry_binding())

    assert {:ok, _alternate_binding} =
             DataSources.persist_data_binding(%DataBinding{
               DataSources.default_flight_telemetry_binding()
               | binding_id: alternate_binding_id,
                 dataset: "alternate-flight",
                 priority: 1,
                 metadata: %{test_binding?: true}
             })

    sample_time =
      DateTime.utc_now()
      |> DateTime.add(10, :second)
      |> DateTime.truncate(:second)

    from_time = DateTime.add(sample_time, -1, :second)
    to_time = DateTime.add(sample_time, 60, :second)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [default_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    alternate_initial_sample = %{
      default_sample
      | sample_id: "browser-source-binding-alt-initial-sample"
    }

    assert :ok =
             Storage.persist_samples([alternate_initial_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: alternate_binding_id,
               revision: 1,
               validity_state: :canonical,
               dashboard_runtime_invalidation?: false
             )

    alternate_corrected_sample = %{
      alternate_initial_sample
      | sample_id: "browser-source-binding-alt-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    assert :ok =
             Storage.persist_samples([alternate_corrected_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: alternate_binding_id,
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    alternate_query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: alternate_binding_id,
      point_id: "HK.counter"
    ]

    [alternate_revision_state] =
      Storage.list_observation_identity_states(mission.mission_id, alternate_query_opts)

    assert alternate_revision_state.latest_sample_id == alternate_corrected_sample.sample_id
    assert alternate_revision_state.validity_state == :conflict

    assert {:ok, alternate_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               alternate_revision_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: alternate_binding_id,
                 decision_reason: "browser_smoke_source_binding_isolation",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-source-binding-isolation-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert alternate_decided_state.validity_state == :superseded

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Revision Source Binding Isolation Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Revision Source Binding Isolation",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
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

    dashboard_path = ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"

    alternate_all_revisions_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: alternate_binding_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    default_all_revisions_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    alternate_canonical_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "canonical", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: alternate_binding_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {alternate_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "corrected_range",
                 "--expected-revision-state",
                 "corrected",
                 "--expected-revision-source-binding-id",
                 alternate_binding_id,
                 "--url",
                 alternate_all_revisions_url,
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

    assert alternate_output =~ "dashboard_viewport_smoke passed"
    assert alternate_output =~ "\"telemetryRevisionRangeEvidence\""

    assert {default_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-absence",
                 "--absent-revision-warning-codes",
                 "corrected_range",
                 "--url",
                 default_all_revisions_url,
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

    assert default_output =~ "dashboard_viewport_smoke passed"
    assert default_output =~ "\"telemetryRevisionRangeAbsence\""

    assert {canonical_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "rendered-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-absence",
                 "--absent-revision-warning-codes",
                 "corrected_range",
                 "--allow-missing-revision-chart",
                 "--url",
                 alternate_canonical_url,
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

    assert canonical_output =~ "dashboard_viewport_smoke passed"
    assert canonical_output =~ "\"telemetryRevisionRangeAbsence\""
  end

  @tag :browser
  test "live telemetry revision range markers stay scoped to replay realm in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "replay-revision-marker-isolation-viewport",
        display_name: "Replay Revision Marker Isolation Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay Revision")
    binding_set = persist_binding_set!(org, mission)
    replay_run_id = "browser-replay-revision-marker"
    replay_sources = persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)

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

    persist_replay_run!(mission, replay_run_id, sample_time)

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [flight_initial_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    flight_advisory_sample = %{
      flight_initial_sample
      | sample_id: "browser-realm-flight-advisory-sample",
        raw_value: 39,
        engineering_value: 39
    }

    assert :ok =
             Storage.persist_samples([flight_advisory_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    replay_initial_sample = %{
      flight_initial_sample
      | sample_id: "browser-realm-replay-initial-sample"
    }

    assert :ok =
             Storage.persist_samples([replay_initial_sample],
               organization_id: org.organization_id,
               realm: :replay,
               replay_run_id: replay_run_id,
               data_source_id: replay_sources.telemetry_data_source_id,
               binding_id: replay_sources.telemetry_binding_id,
               revision: 1,
               validity_state: :canonical,
               dashboard_runtime_invalidation?: false
             )

    replay_corrected_sample = %{
      replay_initial_sample
      | sample_id: "browser-realm-replay-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    assert :ok =
             Storage.persist_samples([replay_corrected_sample],
               organization_id: org.organization_id,
               realm: :replay,
               replay_run_id: replay_run_id,
               data_source_id: replay_sources.telemetry_data_source_id,
               binding_id: replay_sources.telemetry_binding_id,
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    insert_replay_persisted_telemetry_samples!(
      [replay_initial_sample.sample_id, replay_corrected_sample.sample_id],
      replay_run_id
    )

    [flight_revision_state] =
      Storage.list_observation_identity_states(mission.mission_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :flight,
        data_source_id: DataSources.default_managed_data_source().data_source_id,
        binding_id: "default_flight_telemetry",
        point_id: "HK.counter"
      )

    [replay_revision_state] =
      Storage.list_observation_identity_states(mission.mission_id,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        realm: :replay,
        replay_run_id: replay_run_id,
        data_source_id: replay_sources.telemetry_data_source_id,
        binding_id: replay_sources.telemetry_binding_id,
        point_id: "HK.counter"
      )

    assert flight_revision_state.latest_sample_id == flight_advisory_sample.sample_id
    assert replay_revision_state.latest_sample_id == replay_corrected_sample.sample_id

    assert {:ok, flight_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               flight_revision_state.observation_identity_id,
               "mark_advisory",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_realm_flight_advisory",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-realm-flight-advisory-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, replay_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               replay_revision_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 data_source_id: replay_sources.telemetry_data_source_id,
                 binding_id: replay_sources.telemetry_binding_id,
                 decision_reason: "browser_smoke_realm_replay_corrected",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-realm-replay-corrected-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert flight_decided_state.validity_state == :advisory
    assert replay_decided_state.validity_state == :superseded

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Revision Marker Isolation Browser",
        placements: [
          %Placement{
            placement_id: "placement-revision-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Replay Revision Isolation",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
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
    dashboard_path = ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    flight_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    replay_url =
      base_url <>
        "#{dashboard_path}?#{URI.encode_query(%{time_mode: "replay_run", replay_run_id: replay_run_id, data_view: "all_revisions", data_source_id: replay_sources.telemetry_data_source_id, source_binding_id: replay_sources.telemetry_binding_id, from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)})}"

    assert {flight_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "advisory_backfill",
                 "--expected-revision-state",
                 "backfill",
                 "--expected-revision-warning-codes",
                 "advisory_backfill",
                 "--absent-revision-warning-codes",
                 "corrected_range",
                 "--url",
                 flight_url,
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

    assert flight_output =~ "dashboard_viewport_smoke passed"
    assert flight_output =~ "\"telemetryRevisionRangeEvidence\""

    assert {replay_output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
                 "--expected-revision-warning-code",
                 "corrected_range",
                 "--expected-revision-state",
                 "corrected",
                 "--expected-revision-warning-codes",
                 "corrected_range",
                 "--absent-revision-warning-codes",
                 "advisory_backfill",
                 "--expected-revision-data-source-id",
                 replay_sources.telemetry_data_source_id,
                 "--expected-revision-source-binding-id",
                 replay_sources.telemetry_binding_id,
                 "--expected-revision-replay-run-id",
                 replay_run_id,
                 "--url",
                 replay_url,
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

    assert replay_output =~ "dashboard_viewport_smoke passed"
    assert replay_output =~ "\"telemetryRevisionRangeEvidence\""
  end

  @tag :browser
  test "live telemetry watermark fallback markers open source evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    previous_source_execution =
      Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    source_watermark_config =
      Application.get_env(:cadence, :data_source_watermark_events, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      Keyword.put(previous_source_execution, :source_opts, %{
        telemetry: [watermark_fun: &browser_retention_gap_watermark/4]
      })
    )

    Application.put_env(
      :cadence,
      :data_source_watermark_events,
      Keyword.put(source_watermark_config, :enabled?, true)
    )

    on_exit(fn ->
      Application.put_env(
        :cadence_web,
        :dashboard_engine_source_execution,
        previous_source_execution
      )

      Application.put_env(:cadence, :data_source_watermark_events, source_watermark_config)
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "telemetry-watermark-marker-viewport",
        display_name: "Telemetry Watermark Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Marker")
    binding_set = persist_binding_set!(org, mission)

    assert {:ok, _source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_managed_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_telemetry_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _events_source} =
             DataSources.persist_data_source(
               %DataSource{
                 DataSources.default_events_data_source()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    assert {:ok, _events_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 DataSources.default_flight_events_binding()
                 | organization_id: org.organization_id,
                   mission_id: mission.mission_id
               },
               occurred_at: ~U[2026-06-15 00:00:00Z]
             )

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      27,
      DateTime.to_unix(~U[2026-06-16 00:20:00Z])
    )

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      29,
      DateTime.to_unix(~U[2026-06-16 00:30:00Z])
    )

    assert {:ok, watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: DataSources.default_flight_telemetry_binding().binding_id,
                 realm: :flight,
                 dataset: DataSources.default_flight_telemetry_binding().dataset,
                 complete_through: ~U[2026-06-16 00:30:00Z],
                 latest_receipt_time: ~U[2026-06-16 00:30:00Z],
                 retention_starts_at: ~U[2026-06-16 00:10:00Z],
                 sample_count: 2,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-16 00:30:30Z],
                 payload: %{write_id: "browser-telemetry-time-series-watermark-event"}
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, unrelated_watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: "alternate_flight_telemetry",
                 realm: :flight,
                 dataset: DataSources.default_flight_telemetry_binding().dataset,
                 complete_through: ~U[2026-06-16 00:31:00Z],
                 latest_receipt_time: ~U[2026-06-16 00:31:00Z],
                 retention_starts_at: ~U[2026-06-16 00:10:00Z],
                 sample_count: 1,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-16 00:31:30Z],
                 payload: %{write_id: "browser-unrelated-telemetry-time-series-watermark-event"}
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, unrelated_dataset_watermark_event, _watermark_status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 source_binding_id: DataSources.default_flight_telemetry_binding().binding_id,
                 realm: :flight,
                 dataset: "alternate_flight_dataset",
                 complete_through: ~U[2026-06-16 00:32:00Z],
                 latest_receipt_time: ~U[2026-06-16 00:32:00Z],
                 retention_starts_at: ~U[2026-06-16 00:10:00Z],
                 sample_count: 1,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-16 00:32:30Z],
                 payload: %{
                   write_id: "browser-unrelated-dataset-telemetry-time-series-watermark-event"
                 }
               },
               invalidate_runtime_cache?: false
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Telemetry Watermark Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Counter Retention Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: [:events]
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: DataSources.default_flight_telemetry_binding().binding_id, dataset: DataSources.default_flight_telemetry_binding().dataset, from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-watermark-marker-evidence",
                 "--expected-source-watermark-event-id",
                 watermark_event.source_watermark_event_id,
                 "--absent-source-watermark-event-ids",
                 [
                   unrelated_watermark_event.source_watermark_event_id,
                   unrelated_dataset_watermark_event.source_watermark_event_id
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
    assert output =~ "\"telemetryWatermarkMarkerEvidence\""
  end

  @tag :browser
  test "live replay telemetry watermark fallback markers open replay source evidence in browser",
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
        slug: "replay-telemetry-watermark-marker-viewport",
        display_name: "Replay Telemetry Watermark Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Replay Marker")
    binding_set = persist_binding_set!(org, mission)
    replay_run_id = "browser-replay-watermark-marker"

    persist_replay_dashboard_sources!(org.organization_id, mission.mission_id)
    persist_replay_run!(mission, replay_run_id, ~U[2026-06-16 00:20:00Z])

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      27,
      DateTime.to_unix(~U[2026-06-16 00:20:00Z])
    )

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      29,
      DateTime.to_unix(~U[2026-06-16 00:30:00Z])
    )

    samples =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    assert length(samples) == 2
    insert_replay_telemetry_samples!(samples, replay_run_id)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Telemetry Watermark Marker Browser",
        placements: [
          %Placement{
            placement_id: "placement-retention-counter-trend",
            layout: %{x: 0, y: 0, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Replay Counter Retention Trend",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
                sampling: :raw_series,
                overlays: []
              },
              options: %{}
            }
          },
          %Placement{
            placement_id: "placement-retention-counter-trend-peer",
            layout: %{x: 0, y: 3, w: 8, h: 3},
            scope_override: %{
              primary: %{kind: "spacecraft", mode: "one", ids: [spacecraft.spacecraft_id]}
            },
            widget_def: %WidgetDef{
              widget_type_id: "cadence.time_series",
              widget_type_version: 1,
              title: "Replay Counter Retention Trend Peer",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter"],
                scope_mode: :override,
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "replay_run", replay_run_id: replay_run_id, from: "2026-06-16T00:00:00Z", to: "2026-06-16T00:40:00Z"}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-watermark-marker-evidence",
                 "--expected-time-mode",
                 "replay_run",
                 "--expected-replay-run-id",
                 replay_run_id,
                 "--expected-shared-cursor-peer-placement-id",
                 "placement-retention-counter-trend-peer",
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
    assert output =~ "\"telemetryWatermarkMarkerEvidence\""
  end
end
