defmodule CadenceWeb.MissionListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  defp persist_mission!(org, slug, display_name) do
    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.Missions.persist_mission(mission)
    persisted
  end

  describe "mount" do
    test "renders empty state when there are no missions" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions")

      assert has_element?(view, "#mission-list-component")

      vue = LiveVue.Test.get_vue(view, id: "mission-list-component")

      assert vue.component == "MissionList"
      assert vue.props["presentation"]["empty_state"]["visible"]
      assert vue.props["presentation"]["empty_state"]["id"] == "mission-list-empty-state"
    end

    test "renders missions through the Vue table host and JSON-safe row props" do
      {conn, org} = signed_in_conn()
      m1 = persist_mission!(org, "alpha", "Alpha Mission")
      m2 = persist_mission!(org, "beta", "Beta Mission")

      {:ok, view, _html} = live(conn, ~p"/missions")

      assert has_element?(view, "#mission-list-component")

      vue = LiveVue.Test.get_vue(view, id: "mission-list-component")

      assert vue.component == "MissionList"
      assert vue.ssr == false
      assert Map.keys(vue.props) == ["presentation"]
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))

      assert vue.props["presentation"]["card"]["rows"] == [
               %{
                 "id" => "mission-row-#{m1.mission_id}",
                 "display_name" => "Alpha Mission",
                 "slug" => "alpha",
                 "spacecraft_count" => 0,
                 "status" => "info",
                 "status_label" => "No spacecraft",
                 "href" => "/missions/#{m1.mission_id}"
               },
               %{
                 "id" => "mission-row-#{m2.mission_id}",
                 "display_name" => "Beta Mission",
                 "slug" => "beta",
                 "spacecraft_count" => 0,
                 "status" => "info",
                 "status_label" => "No spacecraft",
                 "href" => "/missions/#{m2.mission_id}"
               }
             ]
    end

    test "shows only missions belonging to the current organization" do
      {conn, org} = signed_in_conn()
      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")
      mine = persist_mission!(org, "mine", "My Mission")
      theirs = persist_mission!(other_org, "theirs", "Their Mission")

      {:ok, view, _html} = live(conn, ~p"/missions")

      vue = LiveVue.Test.get_vue(view, id: "mission-list-component")
      rows = vue.props["presentation"]["card"]["rows"]

      assert rows == [
               %{
                 "id" => "mission-row-#{mine.mission_id}",
                 "display_name" => "My Mission",
                 "slug" => "mine",
                 "spacecraft_count" => 0,
                 "status" => "info",
                 "status_label" => "No spacecraft",
                 "href" => "/missions/#{mine.mission_id}"
               }
             ]

      refute Enum.any?(rows, &(&1["id"] == "mission-row-#{theirs.mission_id}"))
      refute Enum.any?(rows, &(&1["display_name"] == "Their Mission"))
    end
  end
end
