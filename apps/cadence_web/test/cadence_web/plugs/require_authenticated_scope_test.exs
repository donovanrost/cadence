defmodule CadenceWeb.Plugs.RequireAuthenticatedScopeTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn

  alias CadenceWeb.Plugs.RequireAuthenticatedScope

  describe "call/2" do
    test "continues when the browser pipeline assigned a current scope" do
      conn = build_conn()
      conn = assign(conn, :current_scope, %{user: %{user_id: "user-1"}})

      assert RequireAuthenticatedScope.call(conn, []) == conn
    end

    test "redirects an unauthenticated GET and preserves its complete return path" do
      conn = build_conn()
      conn = init_test_session(conn, %{})

      conn = %{
        conn
        | method: "GET",
          request_path: "/console/acme/apollo/now",
          query_string: "spacecraft_id=sc-1&window=24h"
      }

      conn = RequireAuthenticatedScope.call(conn, [])

      assert conn.halted
      assert redirected_to(conn) == "/console/sign-in"

      assert get_session(conn, :user_return_to) ==
               "/console/acme/apollo/now?spacecraft_id=sc-1&window=24h"
    end

    test "does not store application-host JSON GETs as browser return paths" do
      conn = build_conn()
      conn = init_test_session(conn, %{})

      conn = %{
        conn
        | method: "GET",
          request_path: "/api/cadence/application-host/v1/missions/mission-1/catalog",
          query_string: ""
      }

      conn = RequireAuthenticatedScope.call(conn, [])

      assert conn.halted
      assert redirected_to(conn) == "/console/sign-in"
      refute get_session(conn, :user_return_to)
    end

    test "redirects an unauthenticated non-GET without storing a return path" do
      conn = build_conn()
      conn = conn |> init_test_session(%{}) |> then(&%{&1 | method: "POST"})
      conn = RequireAuthenticatedScope.call(conn, [])

      assert conn.halted
      assert redirected_to(conn) == "/console/sign-in"
      refute get_session(conn, :user_return_to)
    end
  end
end
