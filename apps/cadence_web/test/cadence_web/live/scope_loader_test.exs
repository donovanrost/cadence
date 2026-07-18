defmodule CadenceWeb.ScopeLoaderTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  alias Cadence.Auth.Scope
  alias CadenceWeb.ScopeLoader
  alias CadenceWeb.TestFixtures

  test "extracts browser test sandbox owner key from LiveView session maps" do
    assert ScopeLoader.browser_test_sandbox_owner_key(%{
             "browser_test_sandbox_owner_key" => "browser-key-1"
           }) == "browser-key-1"

    assert ScopeLoader.browser_test_sandbox_owner_key(%{
             browser_test_sandbox_owner_key: "browser-key-2"
           }) == "browser-key-2"

    assert ScopeLoader.browser_test_sandbox_owner_key(%{}) == nil
    assert ScopeLoader.browser_test_sandbox_owner_key(nil) == nil
  end

  test "rejects mismatched browser test sandbox owner keys" do
    previous_owner = Application.get_env(:cadence_web, :browser_test_sandbox_owner)

    Application.put_env(:cadence_web, :browser_test_sandbox_owner, %{
      owner: self(),
      key: "browser-key"
    })

    on_exit(fn ->
      case previous_owner do
        nil -> Application.delete_env(:cadence_web, :browser_test_sandbox_owner)
        owner -> Application.put_env(:cadence_web, :browser_test_sandbox_owner, owner)
      end
    end)

    assert ScopeLoader.allow_browser_test_sandbox_owner("wrong-key") ==
             {:error, :browser_test_sandbox_owner_key_mismatch}

    assert ScopeLoader.browser_test_sandbox_owner("wrong-key") ==
             {:error, :browser_test_sandbox_owner_key_mismatch}
  end

  test "reports missing browser test sandbox owner for keyed sessions" do
    previous_owner = Application.get_env(:cadence_web, :browser_test_sandbox_owner)
    Application.delete_env(:cadence_web, :browser_test_sandbox_owner)

    on_exit(fn ->
      case previous_owner do
        nil -> Application.delete_env(:cadence_web, :browser_test_sandbox_owner)
        owner -> Application.put_env(:cadence_web, :browser_test_sandbox_owner, owner)
      end
    end)

    assert ScopeLoader.allow_browser_test_sandbox_owner("browser-key") ==
             {:error, :browser_test_sandbox_owner_missing}

    assert ScopeLoader.browser_test_sandbox_owner("browser-key") ==
             {:error, :browser_test_sandbox_owner_missing}

    assert ScopeLoader.allow_browser_test_sandbox_owner(nil) == :ok
    assert ScopeLoader.browser_test_sandbox_owner(nil) == :none
  end

  test "resolves keyed browser test sandbox owner and can allow another process" do
    previous_owner = Application.get_env(:cadence_web, :browser_test_sandbox_owner)
    owner = self()
    client = spawn(fn -> Process.sleep(:infinity) end)

    Application.put_env(:cadence_web, :browser_test_sandbox_owner, %{
      owner: owner,
      key: "browser-key"
    })

    on_exit(fn ->
      Process.exit(client, :kill)

      case previous_owner do
        nil -> Application.delete_env(:cadence_web, :browser_test_sandbox_owner)
        owner -> Application.put_env(:cadence_web, :browser_test_sandbox_owner, owner)
      end
    end)

    assert ScopeLoader.browser_test_sandbox_owner("browser-key") == {:ok, owner}
    assert ScopeLoader.allow_browser_test_sandbox_owner("browser-key", client) == :ok
  end

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
