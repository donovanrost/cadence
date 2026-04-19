defmodule CadenceWeb.OrganizationAuthTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias CadenceWeb.OrganizationAuth
  alias CadenceWeb.TestFixtures

  @moduletag :capture_log

  describe "on_mount :require_organization_scope" do
    test "continues and assigns nav_context when scope has an organization membership" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
      _membership = TestFixtures.grant_membership!(user, org)
      token = TestFixtures.member_session_token!(user)

      session = %{"user_session_token" => token}

      assert {:cont, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.nav_context == :organization
      assert %Scope{organization: %{slug: "cadence-ops"}} = socket.assigns.current_scope
      assert socket.assigns.unread_notifications_count == 0
      assert socket.assigns.recent_notifications == []
    end

    test "redirects to /no-organization when the scope has no membership" do
      user = TestFixtures.persist_user!()
      token = TestFixtures.member_session_token!(user)

      session = %{"user_session_token" => token}

      assert {:halt, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.redirected == {:redirect, %{to: "/no-organization", status: 302}}
    end

    test "redirects platform admin to /admin even without org membership" do
      user =
        CadenceWeb.TestFixtures.persist_user!(
          email: "admin-#{System.unique_integer([:positive])}@example.com",
          capabilities: [:platform_admin]
        )

      token = CadenceWeb.TestFixtures.member_session_token!(user)

      session = %{"user_session_token" => token}

      assert {:halt, socket} =
               CadenceWeb.OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.redirected == {:redirect, %{to: "/admin", status: 302}}
    end

    test "continues for platform admin with an organization membership" do
      user =
        TestFixtures.persist_user!(
          email: "admin-with-org-#{System.unique_integer([:positive])}@example.com",
          capabilities: [:platform_admin]
        )

      org = TestFixtures.persist_org!(display_name: "Admin Org", slug: "admin-org")
      _membership = TestFixtures.grant_membership!(user, org)
      token = TestFixtures.member_session_token!(user)

      session = %{"user_session_token" => token}

      assert {:cont, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.nav_context == :organization
      assert %Scope{organization: %{slug: "admin-org"}} = socket.assigns.current_scope
    end

    test "redirects to /sign-in when there is no session token" do
      session = %{}

      assert {:halt, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.redirected == {:redirect, %{to: "/sign-in", status: 302}}
    end
  end
end
