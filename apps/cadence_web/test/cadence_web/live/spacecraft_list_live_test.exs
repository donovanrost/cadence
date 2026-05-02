defmodule CadenceWeb.SpacecraftListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders empty state when there are no spacecraft" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "No spacecraft"
      assert html =~ ~p"/missions/#{mission.mission_id}/spacecraft/new"
    end

    test "renders spacecraft in a table" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _s1 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1", scid: 101)
      s2 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-2")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "Alpha-1"
      assert html =~ "Alpha-2"
      assert html =~ "101"
      assert html =~ "Not set"
      assert html =~ "New Spacecraft"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{s2.spacecraft_id}/identity"
    end

    test "shows only spacecraft belonging to this mission" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      _mine = TestFixtures.persist_spacecraft!(mission, display_name: "Mine-1")
      _theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Theirs-1")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "Mine-1"
      refute html =~ "Theirs-1"
    end

    test "shows only spacecraft belonging to the current organization" do
      {conn, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      _theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Other-Org-Craft")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      refute html =~ "Other-Org-Craft"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/some-mission-id/spacecraft")
    end

    test "user without membership redirects to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} =
               live(conn, ~p"/missions/some-mission-id/spacecraft")
    end

    test "missing mission redirects to /missions" do
      {conn, _org, _mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: "/missions", flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/missing-mission-id/spacecraft")
    end
  end
end
