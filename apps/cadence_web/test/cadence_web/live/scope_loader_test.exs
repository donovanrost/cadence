defmodule CadenceWeb.ScopeLoaderTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias CadenceWeb.ScopeLoader
  alias CadenceWeb.TestFixtures

  test "returns socket with current_scope when session has a valid token" do
    user = TestFixtures.persist_user!()
    token = TestFixtures.member_session_token!(user)

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

    socket = ScopeLoader.assign_scope_from_session(socket, %{"user_session_token" => token})
    assert %Scope{user: %{email: email}} = socket.assigns.current_scope
    assert email == user.email
  end

  test "assigns nil current_scope for empty session" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    socket = ScopeLoader.assign_scope_from_session(socket, %{})
    assert socket.assigns.current_scope == nil
  end

  test "assigns nil for invalid token" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    socket = ScopeLoader.assign_scope_from_session(socket, %{"user_session_token" => "bogus"})
    assert socket.assigns.current_scope == nil
  end
end
