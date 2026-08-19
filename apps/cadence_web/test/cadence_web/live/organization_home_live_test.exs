defmodule CadenceWeb.OrganizationHomeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures

  describe "mount" do
    test "renders org display_name and slug" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
      _membership = TestFixtures.grant_membership!(user, org)

      conn = TestFixtures.member_conn(user)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Cadence Ops"
      assert html =~ "cadence-ops"
    end

    test "sidebar highlights the Home nav item" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _membership = TestFixtures.grant_membership!(user, org)

      {:ok, _view, html} = live(TestFixtures.member_conn(user), ~p"/")

      assert html =~ ~r/border-primary[^"]*".*Home/s
    end

    test "shows the current mission count and link to /missions" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _ = TestFixtures.grant_membership!(user, org)

      mission =
        Mission.new(%{
          organization_id: org.organization_id,
          slug: "alpha",
          display_name: "Alpha"
        })

      assert {:ok, _} = Cadence.Missions.persist_mission(mission)

      {:ok, view, html} = live(TestFixtures.member_conn(user), ~p"/")

      assert html =~ "All missions"
      assert html =~ ~s(href="/missions")
      assert has_element?(view, "#organization-stat-missions", "1")
    end

    test "lists recent missions with status badges" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _ = TestFixtures.grant_membership!(user, org)

      mission =
        Mission.new(%{
          organization_id: org.organization_id,
          slug: "alpha",
          display_name: "Alpha Mission"
        })

      assert {:ok, _} = Cadence.Missions.persist_mission(mission)

      {:ok, view, html} = live(TestFixtures.member_conn(user), ~p"/")

      assert has_element?(view, "#organization-recent-missions")
      assert html =~ "Alpha Mission"
      assert html =~ "No spacecraft"
    end
  end

  describe "authorization" do
    test "active admin mode redirects to /admin even from /" do
      user =
        TestFixtures.persist_user!(
          email: "elevated-admin-root@example.com",
          capabilities: [:platform_admin]
        )

      token = TestFixtures.member_session_token!(user)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{
          user_session_token: token,
          admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
        })

      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/")
    end
  end
end
