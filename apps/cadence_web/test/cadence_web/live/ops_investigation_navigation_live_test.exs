defmodule CadenceWeb.OpsInvestigationNavigationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.{DataBinding, DataSource}
  alias CadenceWeb.TestFixtures

  test "Dashboard, Explore, Sources, Data Operations, Timeline, and Diagnostics round-trip context" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, slug: "investigation-navigation")
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Investigation SC")
    conn = TestFixtures.member_conn(user)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        dashboard_id: "investigation-dashboard",
        name: "Investigation Dashboard"
      )

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "investigation-source",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: organization.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "investigation-binding",
               organization_id: organization.organization_id,
               mission_id: mission.mission_id,
               realm: :rehearsal,
               logical_source: :telemetry,
               data_source_id: "investigation-source",
               dataset: "rehearsal",
               priority: 0
             })

    dashboard_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{spacecraft_id: spacecraft.spacecraft_id, scope_kind: "spacecraft", scope_id: spacecraft.spacecraft_id, time_mode: "archive", time_axis: "receipt_time", from: "2026-08-01T10:00:00Z", to: "2026-08-01T11:00:00Z", realm: "rehearsal", data_view: "all_revisions", data_source_id: "investigation-source", source_binding_id: "investigation-binding", limit_mode: "current"}}"

    {:ok, dashboard_view, _html} = live(conn, dashboard_path)

    assert has_element?(dashboard_view, "#ops-context-rail")

    explore_path = link_href(dashboard_view, "#dashboard-investigate-telemetry")
    assert explore_path =~ "source_dashboard_id=#{dashboard.dashboard_id}"
    assert explore_path =~ "time_mode=archive"
    assert explore_path =~ "selection_view=all_revisions"
    assert explore_path =~ "data_source_id=investigation-source"
    assert explore_path =~ "source_binding_id=investigation-binding"
    assert explore_path =~ "scope_kind=spacecraft"
    assert explore_path =~ "limit_mode=current"

    explore_path =
      merge_query(explore_path, %{
        "point_id" => "HK.counter",
        "question" => "missing_history",
        "replay_run_id" => "replay-investigation"
      })

    {:ok, explore, _html} = live(conn, explore_path)

    assert has_element?(explore, "#ops-context-rail")
    assert has_element?(explore, "#telemetry-explore-question-data-operations")
    assert has_element?(explore, "#telemetry-explore-open-source")
    assert has_element?(explore, "#telemetry-explore-open-dashboard-diagnostics")

    assert has_element?(
             explore,
             ~s(#telemetry-explore-back-to-dashboard[href*="replay_run_id=replay-investigation"][href*="data_view=all_revisions"][href*="source_binding_id=investigation-binding"][href*="selected_id=HK.counter"])
           )

    timeline_path = link_href(explore, "#telemetry-explore-question-timeline")
    assert timeline_path =~ "return_to=explore"
    assert timeline_path =~ "replay_run_id=replay-investigation"
    assert timeline_path =~ "data_view=all_revisions"
    assert timeline_path =~ "source_binding_id=investigation-binding"

    {:ok, timeline, _html} = live(conn, timeline_path)
    assert has_element?(timeline, "#ops-context-rail")

    assert has_element?(
             timeline,
             ~s(#timeline-return-to-origin[href*="/ops/explore"][href*="replay_run_id=replay-investigation"][href*="selection_view=all_revisions"][href*="source_dashboard_id=#{dashboard.dashboard_id}"])
           )

    {:ok, source_view, _html} =
      live(conn, link_href(explore, "#telemetry-explore-open-source"))

    assert has_element?(source_view, "#ops-context-rail")
    assert has_element?(source_view, "#ops-data-sources-page")

    {:ok, data_operations, _html} =
      live(conn, link_href(explore, "#telemetry-explore-question-data-operations"))

    assert has_element?(data_operations, "#ops-context-rail")
    assert has_element?(data_operations, "#ops-data-operations-page")

    {:ok, diagnostics, _html} =
      live(conn, link_href(explore, "#telemetry-explore-open-dashboard-diagnostics"))

    assert has_element?(diagnostics, "#ops-context-rail")
    assert has_element?(diagnostics, "#dashboard-diagnostics-page")
  end

  defp link_href(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("href")
    |> List.first()
  end

  defp merge_query(path, extra) do
    uri = URI.parse(path)
    query = uri.query |> Kernel.||("") |> URI.decode_query() |> Map.merge(extra)
    URI.to_string(%URI{uri | query: URI.encode_query(query)})
  end
end
