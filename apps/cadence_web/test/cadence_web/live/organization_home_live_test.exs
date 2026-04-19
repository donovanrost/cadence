defmodule CadenceWeb.OrganizationHomeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

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
  end

  describe "authorization" do
    test "redirects unauthenticated users to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/")
    end

    test "redirects user without membership to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} = live(conn, ~p"/")
    end
  end
end
