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
end
