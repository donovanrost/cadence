defmodule CadenceWeb.AuthenticatedEntryTest do
  use ExUnit.Case, async: true

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias CadenceWeb.AuthenticatedEntry

  describe "entry_path/1" do
    test "scope in admin mode routes to /admin" do
      user = %User{capabilities: [:platform_admin]}

      scope = %Scope{
        user: user,
        admin_mode?: true,
        capabilities: MapSet.new([:platform_admin])
      }

      assert AuthenticatedEntry.entry_path(scope) == "/admin"
    end

    test "non-admin scope routes to /" do
      scope = %Scope{capabilities: MapSet.new()}
      assert AuthenticatedEntry.entry_path(scope) == "/"
    end

    test "admin-eligible user without an authenticated scope routes normally" do
      user = %User{capabilities: [:platform_admin]}
      assert AuthenticatedEntry.entry_path(user) == "/"
    end

    test "non-admin user routes to /" do
      user = %User{capabilities: []}
      assert AuthenticatedEntry.entry_path(user) == "/"
    end
  end

  describe "redirect_path/2" do
    test "honors an explicit non-entry return path" do
      user = %User{capabilities: []}
      assert AuthenticatedEntry.redirect_path("/missions/alpha", user) == "/missions/alpha"
    end

    test "falls back to entry path when return_to is an entry route" do
      user = %User{capabilities: []}
      assert AuthenticatedEntry.redirect_path("/", user) == "/"
      assert AuthenticatedEntry.redirect_path("/sign-in", user) == "/"
      assert AuthenticatedEntry.redirect_path("/admin", user) == "/"
    end

    test "falls back to entry path when return_to is nil" do
      user = %User{capabilities: [:platform_admin]}
      assert AuthenticatedEntry.redirect_path(nil, user) == "/"
    end
  end
end
