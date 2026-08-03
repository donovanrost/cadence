defmodule CadenceWeb.Assets.DashboardAuthenticatedRouteSetup do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks
  import CadenceWeb.Assets.DashboardRenderedViewportDataFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportOperationalFixtures
  import CadenceWeb.Assets.DashboardRenderedViewportRunner

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.DataSources
  alias Cadence.Control.Replay.Store.ReplayRunRow
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.Telemetry.Storage
  alias CadenceWeb.TestFixtures

  def run(sandbox_owner, mode \\ :legacy_inline) do
    previous_live_deps = Application.get_env(:cadence_web, :ops_dashboard_show_live, [])

    previous_inline_resolve? =
      Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)

    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    Application.put_env(
      :cadence_web,
      :ops_dashboard_show_live,
      Keyword.put(
        previous_live_deps,
        :late_data_policy_event_opts,
        dashboard_runtime_invalidation?: false
      )
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :ops_dashboard_show_live, previous_live_deps)

      case previous_inline_resolve? do
        nil -> Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)
        value -> Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)

    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org, slug: "live-viewport", display_name: "Live Viewport")

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Live")
    binding_set = persist_binding_set!(org, mission)
    seed_limit_definition!(mission)

    base_unix = DateTime.utc_now() |> DateTime.add(1, :second) |> DateTime.to_unix(:second)

    catalog_revision_id =
      seed_catalog_revision_event!(org, mission, DateTime.from_unix!(base_unix - 60))

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 21, base_unix)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 22, base_unix + 10)
    evaluate_limit_events!(org, mission, spacecraft)

    [older_sample, latest_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Viewport Power",
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
          },
          %{
            type: :event_timeline,
            title: "Workflow Events",
            binding: %{mode: :context, source: :events},
            layout: %{x: 4, y: 3, w: 8, h: 3}
          },
          %{
            type: :constellation_health,
            title: "Fleet",
            binding: %{mode: :constellation},
            layout: %{x: 0, y: 3, w: 4, h: 3}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    counter_item = render_item_by_title(document, "Counter")
    trend_widget = render_item_by_title(document, "Counter Trend").widget

    selected_query = %{
      panel: "data_link",
      selected_target: "telemetry_sample",
      selected_id: older_sample.sample_id,
      selected_placement: trend_widget.widget_id,
      selected_time: DateTime.to_unix(older_sample.receipt_time, :millisecond),
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      source_binding_id: "default_flight_telemetry"
    }

    app_root = Path.expand("../..", __DIR__)
    ensure_assets_built!(app_root)

    port = free_tcp_port()

    start_browser_endpoint!(port, sandbox_owner)

    base_url = "http://localhost:#{port}"

    dashboard_url =
      base_url <>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{selected_query}"

    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [
                 script,
                 "--profile",
                 "live-dashboard",
                 "--url",
                 dashboard_url,
                 "--expected-limit-definition-id",
                 "browser-viewport-counter-limits",
                 "--expected-limit-set-name",
                 "browser-smoke",
                 "--expected-catalog-revision-id",
                 catalog_revision_id,
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
    assert output =~ "\"contextRail\""
    assert output =~ "\"sectionKeys\""

    persisted_layout_document = fetch_dashboard_document!(org, mission, dashboard)

    persisted_counter_placement =
      placement_by_id!(persisted_layout_document, counter_item.placement_id)

    assert persisted_counter_placement.layout.x == counter_item.layout.x
    assert persisted_counter_placement.layout.y == counter_item.layout.y
    assert persisted_counter_placement.layout.w == counter_item.layout.w
    # edit mode runs float(false): the smoke mutates height (a vertical move
    # would compact straight back), so the resize is what persists
    assert persisted_counter_placement.layout.h == counter_item.layout.h + 1

    if mode == :current_ia do
      %{
        app_root: app_root,
        base_unix: base_unix,
        base_url: base_url,
        dashboard: dashboard,
        mission: mission,
        org: org,
        script: script,
        trend_widget: trend_widget,
        user: user
      }
    else
      assert [started_event] =
               mission.mission_id
               |> Storage.list_backfill_lifecycle_events(
                 organization_id: org.organization_id,
                 event_type: :backfill_started
               )
               |> Enum.filter(&(&1.reason == "browser_smoke_historical_start"))

      assert started_event.payload["stage_transition_source"] == "dashboard_stage_action"
      assert started_event.payload["dashboard_context"]["dashboard_id"] == dashboard.dashboard_id
      assert started_event.payload["dashboard_context"]["dashboard_limit_mode"] == "compare"

      assert {:ok, started_job} =
               Cadence.fetch_telemetry_historical_data_workflow_job(started_event.backfill_run_id)

      assert started_job.status == :queued
      assert started_job.payload["workflow"] == "backfill"

      claimed_jobs = Cadence.Jobs.claim_jobs(10)
      claimed_started_job = Enum.find(claimed_jobs, &(&1.job_id == started_job.job_id))

      assert claimed_started_job

      assert {:ok, completed_job} = Cadence.Jobs.Runner.run_job(claimed_started_job.job_id)
      assert completed_job.status == :completed

      assert [completed_event] =
               mission.mission_id
               |> Storage.list_backfill_lifecycle_events(
                 organization_id: org.organization_id,
                 event_type: :backfill_completed
               )
               |> Enum.filter(&(&1.backfill_run_id == started_event.backfill_run_id))

      assert completed_event.reason == "historical_data_job_completed"
      assert completed_event.payload["job_id"] == completed_job.job_id

      completed_query = %{
        panel: "data_link",
        selected_target: "telemetry_backfill_lifecycle_event",
        selected_id: completed_event.backfill_lifecycle_event_id
      }

      completed_dashboard_url =
        base_url <>
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{completed_query}"

      assert {completed_output, 0} =
               run_dashboard_viewport_smoke(
                 [
                   script,
                   "--profile",
                   "live-dashboard",
                   "--interaction-mode",
                   "completed-workflow",
                   "--url",
                   completed_dashboard_url,
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

      assert completed_output =~ "dashboard_viewport_smoke passed"

      assert [late_data_policy_event] =
               mission.mission_id
               |> Storage.list_backfill_lifecycle_events(
                 organization_id: org.organization_id,
                 event_type: :late_data_accepted
               )
               |> Enum.filter(
                 &(&1.payload["source_event_id"] == completed_event.backfill_lifecycle_event_id)
               )

      assert late_data_policy_event.payload["dashboard_context"]["dashboard_limit_mode"] ==
               "compare"

      Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

      for limit_mode <- ["current", "recomputed"] do
        completed_event =
          record_completed_late_data_policy_source_event!(
            org,
            mission,
            dashboard,
            spacecraft,
            [older_sample, latest_sample],
            limit_mode
          )

        completed_query = %{
          panel: "data_link",
          selected_target: "telemetry_backfill_lifecycle_event",
          selected_id: completed_event.backfill_lifecycle_event_id,
          limit_mode: limit_mode
        }

        completed_dashboard_url =
          base_url <>
            ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{completed_query}"

        assert {completed_output, 0} =
                 run_dashboard_viewport_smoke(
                   [
                     script,
                     "--profile",
                     "live-dashboard",
                     "--interaction-mode",
                     "completed-workflow",
                     "--expected-limit-mode",
                     limit_mode,
                     "--url",
                     completed_dashboard_url,
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

        assert completed_output =~ "dashboard_viewport_smoke passed"

        assert [late_data_policy_event] =
                 mission.mission_id
                 |> Storage.list_backfill_lifecycle_events(
                   organization_id: org.organization_id,
                   event_type: :late_data_accepted
                 )
                 |> Enum.filter(
                   &(&1.payload["source_event_id"] == completed_event.backfill_lifecycle_event_id)
                 )

        assert late_data_policy_event.reason == "browser_smoke_late_data_policy_#{limit_mode}"

        assert late_data_policy_event.payload["dashboard_context"]["dashboard_limit_mode"] ==
                 limit_mode
      end

      replay_policy_mission =
        TestFixtures.persist_mission!(org,
          slug: "live-viewport-replay-policy",
          display_name: "Live Viewport Replay Policy"
        )

      replay_policy_spacecraft =
        TestFixtures.persist_spacecraft!(replay_policy_mission, display_name: "SC Replay Policy")

      replay_policy_binding_set = persist_binding_set!(org, replay_policy_mission)
      seed_limit_definition!(replay_policy_mission)

      ingest!(
        replay_policy_mission,
        replay_policy_binding_set,
        replay_policy_spacecraft.spacecraft_id,
        21,
        base_unix
      )

      ingest!(
        replay_policy_mission,
        replay_policy_binding_set,
        replay_policy_spacecraft.spacecraft_id,
        22,
        base_unix + 10
      )

      evaluate_limit_events!(org, replay_policy_mission, replay_policy_spacecraft)

      [replay_older_sample, replay_latest_sample] =
        TelemetryReads.sample_history(
          org.organization_id,
          replay_policy_mission.mission_id,
          "HK.counter",
          spacecraft_id: replay_policy_spacecraft.spacecraft_id,
          order: :asc
        )

      replay_policy_dashboard =
        TestFixtures.persist_dashboard_document!(replay_policy_mission,
          name: "Replay Policy Power",
          widgets: [
            %{
              type: :value_tile,
              title: "Counter",
              binding: %{
                mode: :fixed,
                spacecraft_id: replay_policy_spacecraft.spacecraft_id,
                point_id: "HK.counter"
              },
              layout: %{x: 0, y: 0, w: 4, h: 2}
            },
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: replay_policy_spacecraft.spacecraft_id,
                point_id: "HK.counter"
              },
              layout: %{x: 4, y: 0, w: 6, h: 3}
            },
            %{
              type: :event_timeline,
              title: "Workflow Events",
              binding: %{mode: :context, source: :events},
              layout: %{x: 4, y: 3, w: 8, h: 3}
            },
            %{
              type: :constellation_health,
              title: "Fleet",
              binding: %{mode: :constellation},
              layout: %{x: 0, y: 3, w: 4, h: 3}
            }
          ]
        )

      replay_policy_run_id = "browser-smoke-late-policy-replay"
      persist_replay_dashboard_sources!(org.organization_id, replay_policy_mission.mission_id)

      replay_policy_run =
        Run.new(%{
          replay_run_id: replay_policy_run_id,
          mission_id: replay_policy_mission.mission_id,
          binding_set_id: replay_policy_binding_set.binding_set_id,
          binding_set_version: replay_policy_binding_set.version,
          status: :completed,
          replayed_evidence_count: 2,
          replayed_packet_count: 2,
          replayed_sample_count: 2,
          started_at: DateTime.add(replay_older_sample.receipt_time, -60, :second),
          completed_at: DateTime.add(replay_older_sample.receipt_time, 60, :second)
        })

      Repo.insert!(ReplayRunRow.changeset(replay_policy_run))

      insert_replay_telemetry_samples!(
        [replay_older_sample, replay_latest_sample],
        replay_policy_run_id
      )

      insert_replay_limit_events!(
        replay_policy_mission,
        replay_policy_spacecraft,
        [replay_older_sample, replay_latest_sample],
        replay_policy_run_id
      )

      replay_completed_event =
        record_completed_late_data_policy_source_event!(
          org,
          replay_policy_mission,
          replay_policy_dashboard,
          replay_policy_spacecraft,
          [replay_older_sample, replay_latest_sample],
          "compare",
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: replay_policy_run_id
        )

      replay_completed_query = %{
        panel: "data_link",
        selected_target: "telemetry_backfill_lifecycle_event",
        selected_id: replay_completed_event.backfill_lifecycle_event_id,
        time_mode: "replay_run",
        replay_run_id: replay_policy_run_id,
        limit_mode: "compare"
      }

      replay_completed_dashboard_url =
        base_url <>
          ~p"/missions/#{replay_policy_mission.mission_id}/ops/dashboards/#{replay_policy_dashboard.dashboard_id}?#{replay_completed_query}"

      assert {replay_completed_output, 0} =
               run_dashboard_viewport_smoke(
                 [
                   script,
                   "--profile",
                   "live-dashboard",
                   "--interaction-mode",
                   "completed-workflow",
                   "--expected-time-mode",
                   "replay_run",
                   "--expected-replay-run-id",
                   replay_policy_run_id,
                   "--expected-limit-mode",
                   "compare",
                   "--expected-late-data-policy-execution-mode",
                   "event_only",
                   "--skip-late-data-policy-submit",
                   "--url",
                   replay_completed_dashboard_url,
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

      assert replay_completed_output =~ "dashboard_viewport_smoke passed"

      case previous_inline_resolve? do
        nil -> Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)
        value -> Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end

      %{
        app_root: app_root,
        base_unix: base_unix,
        base_url: base_url,
        dashboard: dashboard,
        mission: mission,
        org: org,
        script: script,
        trend_widget: trend_widget,
        user: user
      }
    end
  end
end
