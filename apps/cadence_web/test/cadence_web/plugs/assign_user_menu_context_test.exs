defmodule CadenceWeb.Plugs.AssignUserMenuContextTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.Plugs.AssignUserMenuContext
  alias CadenceWeb.TestFixtures

  describe "call/2" do
    test "assigns empty memberships and false platform_admin when no scope", %{conn: conn} do
      conn = assign(conn, :current_scope, nil)
      updated = AssignUserMenuContext.call(conn, [])

      assert updated.assigns.user_menu_memberships == []
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "assigns memberships for an authenticated user", %{conn: _conn} do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Plug Co")
      _ = TestFixtures.grant_membership!(user, org)

      conn = TestFixtures.member_conn(user)
      conn = CadenceWeb.Plugs.FetchBrowserCurrentScope.call(conn, [])

      updated = AssignUserMenuContext.call(conn, [])

      assert [%{organization: loaded_org}] = updated.assigns.user_menu_memberships
      assert loaded_org.organization_id == org.organization_id
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "marks platform admins", %{conn: _conn} do
      user = TestFixtures.persist_user!(capabilities: [:platform_admin])

      conn = TestFixtures.member_conn(user)
      conn = CadenceWeb.Plugs.FetchBrowserCurrentScope.call(conn, [])

      updated = AssignUserMenuContext.call(conn, [])

      assert updated.assigns.user_menu_platform_admin? == true
    end
  end
end
