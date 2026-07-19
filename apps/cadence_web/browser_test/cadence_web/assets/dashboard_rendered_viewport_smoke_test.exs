# This opt-in matrix lives outside the default test path so normal test runs do not
# pay its substantial compilation cost. Use the browser Mix aliases to run it.
Code.require_file(Path.expand("../../support/dashboard_rendered_viewport_support.exs", __DIR__))

Code.require_file(
  Path.expand("../../support/dashboard_authenticated_route_scenario.exs", __DIR__)
)

defmodule CadenceWeb.Assets.DashboardRenderedViewportSmokeTest do
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

  alias Cadence.Dashboards.DataSources
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  alias CadenceWeb.TestFixtures
  alias CadenceWeb.Assets.DashboardAuthenticatedRouteScenario

  @tag :browser_smoke
  test "dashboard viewport smoke helper times out and terminates node child", %{conn: _conn} do
    marker = "dashboard-smoke-timeout-#{System.unique_integer([:positive])}"
    script = "const marker = #{inspect(marker)}; setInterval(() => marker, 1000)"

    assert {output, status} =
             run_dashboard_viewport_smoke(["-e", script],
               cd: Path.expand("../../..", __DIR__),
               timeout: 100
             )

    assert status != 0
    assert output =~ "Dashboard viewport smoke timed out after 100ms"

    Process.sleep(100)

    assert {process_output, 0} =
             System.cmd("ps", ["-ax", "-o", "pid,ppid,stat,command"], stderr_to_stdout: true)

    refute process_output =~ marker
  end

  @tag :browser_smoke
  test "rendered dashboard HTML passes browser viewport smoke", %{conn: _conn} do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org, slug: "viewport", display_name: "Viewport Mission")

    conn = TestFixtures.member_conn(user)

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")
    binding_set = persist_binding_set!(org, mission)

    ingest!(mission, binding_set, spacecraft.spacecraft_id, 14, 1_700_000_090)
    ingest!(mission, binding_set, spacecraft.spacecraft_id, 15, 1_700_000_100)

    [older_sample, _latest_sample] =
      TelemetryReads.sample_history(
        org.organization_id,
        mission.mission_id,
        "HK.counter",
        spacecraft_id: spacecraft.spacecraft_id,
        order: :asc
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Viewport Power",
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
    trend_widget = render_item_by_title(document, "Counter Trend").widget

    selected_query = %{
      panel: "data_link",
      selected_target: "telemetry_sample",
      selected_id: older_sample.sample_id,
      selected_placement: trend_widget.widget_id,
      selected_time: DateTime.to_unix(older_sample.receipt_time, :millisecond),
      data_source_id: DataSources.default_managed_data_source().data_source_id,
      source_binding_id: "default_flight_telemetry",
      limit_mode: "compare"
    }

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{selected_query}"
      )

    html = render_async(view, 5_000)

    assert has_element?(view, "#ops-dashboard-show-page")
    assert has_element?(view, ~s([phx-hook="DashboardGrid"]))
    assert has_element?(view, ~s([phx-hook="TelemetryChart"]))
    assert has_element?(view, "#dashboard-panel")
    assert has_element?(view, "#dashboard-data-link-copy-link")

    app_root = Path.expand("../../..", __DIR__)
    ensure_assets_built!(app_root)

    artifact_path = rendered_dashboard_artifact!(html, app_root)
    script = Path.join(app_root, "assets/test/dashboard_viewport_smoke.mjs")

    on_exit(fn -> File.rm(artifact_path) end)

    assert {output, 0} =
             run_dashboard_viewport_smoke(
               [script, "--profile", "rendered-dashboard", "--html", artifact_path],
               cd: app_root,
               stderr_to_stdout: true
             )

    assert output =~ "dashboard_viewport_smoke passed"
  end

  @tag :browser_smoke
  test "live authenticated dashboard route passes browser viewport smoke", %{
    conn: _conn,
    sandbox_owner: sandbox_owner
  } do
    DashboardAuthenticatedRouteScenario.run(sandbox_owner)
  end
end
