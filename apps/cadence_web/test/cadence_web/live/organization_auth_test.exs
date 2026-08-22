defmodule CadenceWeb.OrganizationAuthTest do
  use Cadence.DataCase, async: true

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

    test "admin-eligible user without admin mode follows normal organization access" do
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

      assert socket.redirected == {:redirect, %{to: "/no-organization", status: 302}}
    end

    test "admin mode can open an organization without membership" do
      user =
        TestFixtures.persist_user!(
          email: "elevated-admin-#{System.unique_integer([:positive])}@example.com",
          capabilities: [:platform_admin]
        )

      org = TestFixtures.persist_org!(display_name: "Admin Org", slug: "admin-org")
      token = TestFixtures.member_session_token!(user)

      session = %{
        "user_session_token" => token,
        "current_organization_id" => org.organization_id,
        "admin_mode_expires_at" => CadenceWeb.AdminMode.expires_at()
      }

      assert {:cont, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.nav_context == :organization

      assert %Scope{
               organization: %{slug: "admin-org"},
               organization_membership: nil,
               admin_mode?: true
             } = socket.assigns.current_scope
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

  describe "on_mount :require_organization_admin" do
    test "continues for an organization administrator" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
      token = TestFixtures.member_session_token!(user)

      {:cont, socket} =
        OrganizationAuth.on_mount(
          :require_organization_scope,
          %{},
          %{"user_session_token" => token},
          %Phoenix.LiveView.Socket{}
        )

      assert {:cont, _socket} =
               OrganizationAuth.on_mount(:require_organization_admin, %{}, %{}, socket)
    end

    test "redirects an ordinary member to the organization home" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _membership = TestFixtures.grant_membership!(user, org, role: :member)
      token = TestFixtures.member_session_token!(user)

      {:cont, socket} =
        OrganizationAuth.on_mount(
          :require_organization_scope,
          %{},
          %{"user_session_token" => token},
          %Phoenix.LiveView.Socket{}
        )

      assert {:halt, socket} =
               OrganizationAuth.on_mount(:require_organization_admin, %{}, %{}, socket)

      assert socket.redirected == {:redirect, %{to: "/", status: 302}}
    end
  end
end
