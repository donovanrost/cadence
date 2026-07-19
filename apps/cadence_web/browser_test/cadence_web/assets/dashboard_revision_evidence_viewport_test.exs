# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

defmodule CadenceWeb.Assets.DashboardRevisionEvidenceViewportTest do
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
  alias Cadence.Dashboards.WidgetDef
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage
  alias CadenceWeb.TestFixtures

  @tag :browser
  test "live telemetry revision range markers open frame evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "revision-range-marker-viewport",
        display_name: "Revision Range Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Revision Range")
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

    [initial_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    corrected_sample = %{
      initial_sample
      | sample_id: "browser-revision-range-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    assert :ok =
             Storage.persist_samples([corrected_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    [revision_state] =
      Storage.list_observation_identity_states(
        mission.mission_id,
        Keyword.put(query_opts, :point_id, "HK.counter")
      )

    assert revision_state.latest_sample_id == corrected_sample.sample_id
    assert revision_state.validity_state == :conflict

    assert {:ok, decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               revision_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_superseded_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-corrected-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert decided_state.validity_state == :superseded
    assert decided_state.latest_sample_id == corrected_sample.sample_id

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Revision Range Marker Browser",
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
              title: "Counter Revision Range",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--interaction-mode",
                 "telemetry-revision-range-evidence",
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
    assert output =~ "\"telemetryRevisionRangeEvidence\""
  end

  @tag :browser
  test "live telemetry advisory backfill range markers open frame evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "advisory-backfill-marker-viewport",
        display_name: "Advisory Backfill Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Advisory Backfill")
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

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [initial_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    advisory_sample = %{
      initial_sample
      | sample_id: "browser-revision-range-advisory-sample",
        raw_value: 39,
        engineering_value: 39
    }

    assert :ok =
             Storage.persist_samples([advisory_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    [revision_state] =
      Storage.list_observation_identity_states(
        mission.mission_id,
        Keyword.put(query_opts, :point_id, "HK.counter")
      )

    assert revision_state.latest_sample_id == advisory_sample.sample_id
    assert revision_state.validity_state == :conflict

    assert {:ok, decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               revision_state.observation_identity_id,
               "mark_advisory",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_advisory_backfill_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-advisory-backfill-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert decided_state.validity_state == :advisory
    assert decided_state.latest_sample_id == advisory_sample.sample_id

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Advisory Backfill Marker Browser",
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
              title: "Counter Advisory Backfill Range",
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
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
    assert output =~ "\"telemetryRevisionRangeEvidence\""
  end

  defp persist_mixed_revision_browser_fixture!(sandbox_owner) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "mixed-revision-marker-viewport",
        display_name: "Mixed Revision Marker Viewport"
      )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Mixed Revision")
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

    ingest!(
      mission,
      binding_set,
      spacecraft.spacecraft_id,
      37,
      DateTime.to_unix(sample_time, :second),
      dashboard_runtime_invalidation?: false
    )

    [corrected_initial_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    advisory_initial_sample = %Sample{
      sample_id: "browser-mixed-revision-voltage-initial-sample",
      mission_id: mission.mission_id,
      spacecraft_id: spacecraft.spacecraft_id,
      point_id: "HK.voltage",
      point_name: "HK.voltage",
      packet_definition_id: corrected_initial_sample.packet_definition_id,
      packet_definition_version: corrected_initial_sample.packet_definition_version,
      packet_id: corrected_initial_sample.packet_id,
      evidence_id: corrected_initial_sample.evidence_id,
      raw_value: 120,
      engineering_value: 120,
      quality_state: :good,
      generation_time: sample_time,
      receipt_time: sample_time,
      provenance: %{}
    }

    assert :ok =
             Storage.persist_samples([advisory_initial_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 1,
               validity_state: :canonical,
               dashboard_runtime_invalidation?: false
             )

    corrected_sample = %{
      corrected_initial_sample
      | sample_id: "browser-mixed-revision-corrected-sample",
        raw_value: 41,
        engineering_value: 41
    }

    advisory_sample = %{
      advisory_initial_sample
      | sample_id: "browser-mixed-revision-advisory-sample",
        raw_value: 122,
        engineering_value: 122
    }

    assert :ok =
             Storage.persist_samples([corrected_sample, advisory_sample],
               organization_id: org.organization_id,
               realm: :flight,
               data_source_id: DataSources.default_managed_data_source().data_source_id,
               binding_id: "default_flight_telemetry",
               revision: 2,
               validity_state: :conflict,
               dashboard_runtime_invalidation?: false
             )

    query_opts = [
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      realm: :flight,
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      binding_id: "default_flight_telemetry"
    ]

    revision_states =
      Storage.list_observation_identity_states(
        mission.mission_id,
        query_opts
      )

    assert length(revision_states) == 2

    corrected_state =
      Enum.find(revision_states, &(&1.latest_sample_id == corrected_sample.sample_id))

    advisory_state =
      Enum.find(revision_states, &(&1.latest_sample_id == advisory_sample.sample_id))

    assert corrected_state.validity_state == :conflict
    assert advisory_state.validity_state == :conflict

    assert {:ok, corrected_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               corrected_state.observation_identity_id,
               "mark_superseded",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_mixed_corrected_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-mixed-corrected-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert {:ok, advisory_decided_state} =
             Cadence.apply_telemetry_observation_identity_decision(
               advisory_state.observation_identity_id,
               "mark_advisory",
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 realm: :flight,
                 data_source_id: DataSources.default_managed_data_source().data_source_id,
                 binding_id: "default_flight_telemetry",
                 decision_reason: "browser_smoke_mixed_advisory_backfill_range",
                 authority: "operator",
                 requested_by: "dashboard",
                 operator_id: "operator-source",
                 evidence_ref: %{
                   "kind" => "dashboard_revision_marker",
                   "id" => "browser-mixed-advisory-backfill-range-marker-1"
                 }
               },
               dashboard_runtime_invalidation?: false
             )

    assert corrected_decided_state.validity_state == :superseded
    assert advisory_decided_state.validity_state == :advisory

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Mixed Revision Marker Browser",
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
              title: "Counter Mixed Revision Range",
              binding: %{
                source: :telemetry,
                observables: ["HK.counter", "HK.voltage"],
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
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    %{
      app_root: app_root,
      base_url: base_url,
      dashboard_url: dashboard_url,
      from_time: from_time,
      mission: mission,
      script: script,
      spacecraft: spacecraft,
      to_time: to_time,
      user: user
    }
  end

  @tag :browser
  test "live telemetry mixed revision range markers open frame evidence in browser", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    fixture = persist_mixed_revision_browser_fixture!(sandbox_owner)

    %{
      app_root: app_root,
      base_url: base_url,
      dashboard_url: dashboard_url,
      from_time: from_time,
      mission: mission,
      script: script,
      spacecraft: spacecraft,
      to_time: to_time,
      user: user
    } = fixture

    shared_marker_args = [
      "--expected-revision-warning-codes",
      "corrected_range,advisory_backfill"
    ]

    assert {corrected_output, 0} =
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
                 "corrected"
               ] ++
                 shared_marker_args ++
                 [
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

    assert corrected_output =~ "dashboard_viewport_smoke passed"
    assert corrected_output =~ "\"telemetryRevisionRangeEvidence\""

    assert {advisory_output, 0} =
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
                 "--expected-revision-evidence-subject",
                 "HK.voltage"
               ] ++
                 shared_marker_args ++
                 [
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

    assert advisory_output =~ "dashboard_viewport_smoke passed"
    assert advisory_output =~ "\"telemetryRevisionRangeEvidence\""

    counter_only_dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Counter Only Mixed Revision Marker Browser",
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
              title: "Counter Only Revision Range",
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

    counter_only_dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{counter_only_dashboard.dashboard_id}?#{%{time_mode: "archive", data_view: "all_revisions", data_source_id: DataSources.default_managed_data_source().data_source_id, source_binding_id: "default_flight_telemetry", from: DateTime.to_iso8601(from_time), to: DateTime.to_iso8601(to_time)}}"

    assert {counter_only_output, 0} =
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
                 "--url",
                 counter_only_dashboard_url,
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

    assert counter_only_output =~ "dashboard_viewport_smoke passed"
    assert counter_only_output =~ "\"telemetryRevisionRangeEvidence\""
  end
end
