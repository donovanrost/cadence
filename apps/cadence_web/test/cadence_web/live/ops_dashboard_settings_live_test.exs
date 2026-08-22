defmodule CadenceWeb.OpsDashboardSettingsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  test "saves dashboard identity, tags, and runtime defaults as one settings version" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} = live(conn, settings_path(mission, dashboard))

    view
    |> form("#dashboard-settings-form",
      settings: %{
        name: "Power Flight",
        description: "Flight power posture",
        tags: "flight, power, flight",
        defaults_json: Jason.encode!(%{"time" => %{"mode" => "live"}})
      }
    )
    |> render_submit()

    assert {:ok, %Document{} = persisted} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert persisted.name == "Power Flight"
    assert persisted.description == "Flight power posture"
    assert persisted.metadata["tags"] == ["flight", "power"]
    assert persisted.defaults == %{"time" => %{"mode" => "live"}}
    assert Document.version(persisted) == 2
  end

  test "archives from Settings with an explicit lifecycle outcome" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Archive Me")

    {:ok, view, _html} = live(conn, settings_path(mission, dashboard))
    view |> element("#dashboard-settings-archive") |> render_click()

    assert_redirect(view, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert Cadence.Dashboards.list_dashboard_summaries(org.organization_id, mission.mission_id) ==
             []

    assert [%{dashboard_id: archived_id}] =
             Cadence.Dashboards.list_archived_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert archived_id == dashboard.dashboard_id
  end

  defp settings_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/settings"
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-settings")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
