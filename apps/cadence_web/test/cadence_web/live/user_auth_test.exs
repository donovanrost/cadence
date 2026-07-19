defmodule CadenceWeb.UserAuthTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias CadenceWeb.TestFixtures
  alias CadenceWeb.UserAuth

  describe "on_mount :require_user_scope" do
    test "continues with user scope" do
      user = TestFixtures.persist_user!()
      token = TestFixtures.member_session_token!(user)
      session = %{"user_session_token" => token}

      assert {:cont, socket} =
               UserAuth.on_mount(:require_user_scope, %{}, session, %Phoenix.LiveView.Socket{})

      assert %Scope{user: %{email: email}} = socket.assigns.current_scope
      assert email == user.email
    end

    test "halts to /sign-in when unauthenticated" do
      assert {:halt, socket} =
               UserAuth.on_mount(:require_user_scope, %{}, %{}, %Phoenix.LiveView.Socket{})

      assert socket.redirected == {:redirect, %{to: "/sign-in", status: 302}}
    end

    test "halts to /sign-in when token is invalid" do
      assert {:halt, socket} =
               UserAuth.on_mount(
                 :require_user_scope,
                 %{},
                 %{"user_session_token" => "bogus"},
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.redirected == {:redirect, %{to: "/sign-in", status: 302}}
    end
  end

  describe "on_mount(:attach_user_menu, ...)" do
    test "assigns empty memberships and platform_admin? false when no user in scope" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: nil}}

      assert {:cont, updated} =
               CadenceWeb.UserAuth.on_mount(:attach_user_menu, %{}, %{}, socket)

      assert updated.assigns.user_menu_memberships == []
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "assigns memberships for an authenticated user" do
      user = CadenceWeb.TestFixtures.persist_user!()
      org = CadenceWeb.TestFixtures.persist_org!(display_name: "Memberships Co")
      _ = CadenceWeb.TestFixtures.grant_membership!(user, org)

      {:ok, scope} =
        Cadence.Auth.authenticate_api_token(CadenceWeb.TestFixtures.member_session_token!(user))

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, current_scope: scope}
      }

      assert {:cont, updated} =
               CadenceWeb.UserAuth.on_mount(:attach_user_menu, %{}, %{}, socket)

      assert [%{membership: membership, organization: loaded_org}] =
               updated.assigns.user_menu_memberships

      assert membership.user_id == user.user_id
      assert loaded_org.organization_id == org.organization_id
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "sets platform_admin? true when user scope includes :platform_admin capability" do
      user = CadenceWeb.TestFixtures.persist_user!(capabilities: [:platform_admin])

      {:ok, scope} =
        Cadence.Auth.authenticate_api_token(CadenceWeb.TestFixtures.member_session_token!(user))

      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: scope}}

      assert {:cont, updated} =
               CadenceWeb.UserAuth.on_mount(:attach_user_menu, %{}, %{}, socket)

      assert updated.assigns.user_menu_platform_admin? == true
    end
  end
end
