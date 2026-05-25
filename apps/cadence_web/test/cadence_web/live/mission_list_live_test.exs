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

    assert {:ok, persisted} = Cadence.persist_mission(mission)
    persisted
  end

  describe "mount" do
    test "renders empty state when there are no missions" do
      {conn, _org} = signed_in_conn()

      {:ok, _view, html} = live(conn, ~p"/missions")

      assert html =~ "No missions"
    end

    test "renders missions in a table" do
      {conn, org} = signed_in_conn()
      m1 = persist_mission!(org, "alpha", "Alpha Mission")
      _m2 = persist_mission!(org, "beta", "Beta Mission")

      {:ok, view, html} = live(conn, ~p"/missions")

      assert html =~ "Alpha Mission"
      assert html =~ "alpha"
      assert html =~ "Beta Mission"
      assert html =~ "beta"
      assert html =~ "New Mission"
      assert has_element?(view, "#mission-list-table")
      assert has_element?(view, "#mission-row-#{m1.mission_id}")
      assert html =~ "Spacecraft"
      assert html =~ "No spacecraft"
    end

    test "shows only missions belonging to the current organization" do
      {conn, org} = signed_in_conn()
      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")
      _mine = persist_mission!(org, "mine", "My Mission")
      _theirs = persist_mission!(other_org, "theirs", "Their Mission")

      {:ok, _view, html} = live(conn, ~p"/missions")

      assert html =~ "My Mission"
      refute html =~ "Their Mission"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/missions")
    end

    test "user without membership redirects to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} = live(conn, ~p"/missions")
    end
  end
end
