defmodule CadenceWeb.MissionShowLiveTest do
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
    org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
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

    assert {:ok, persisted} = Cadence.persist_mission(mission)
    persisted
  end

  describe "mount" do
    test "renders mission details with the mission sidebar layout" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "alpha", "Alpha Mission")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}")

      assert html =~ "Alpha Mission"
      assert html =~ "alpha"
      assert html =~ mission.mission_id
      # Sidebar Overview nav item is highlighted.
      assert html =~ ~r/border-primary[^"]*".*Overview/s
      # Sidebar back link shows the org display_name.
      assert html =~ "Cadence Ops"
    end
  end

  describe "authorization" do
    test "redirects to /missions when mission id is unknown" do
      {conn, _org} = signed_in_conn()

      assert {:error, {:redirect, %{to: "/missions"}}} =
               live(conn, ~p"/missions/mission_unknown")
    end

    test "redirects to /missions when mission belongs to another org" do
      {conn, _mine} = signed_in_conn()
      other = TestFixtures.persist_org!(slug: "other-org")
      their_mission = persist_mission!(other, "theirs", "Their Mission")

      assert {:error, {:redirect, %{to: "/missions"}}} =
               live(conn, ~p"/missions/#{their_mission.mission_id}")
    end

    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/mission_anything")
    end
  end
end
