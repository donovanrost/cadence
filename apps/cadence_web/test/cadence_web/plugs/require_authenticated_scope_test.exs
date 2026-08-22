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
          request_path: "/missions/mission-1/ops/explore",
          query_string: "point_id=HK.temp&time_mode=historical"
      }

      conn = RequireAuthenticatedScope.call(conn, [])

      assert conn.halted
      assert redirected_to(conn) == "/sign-in"

      assert get_session(conn, :user_return_to) ==
               "/missions/mission-1/ops/explore?point_id=HK.temp&time_mode=historical"
    end

    test "redirects an unauthenticated non-GET without storing a return path" do
      conn = build_conn()
      conn = conn |> init_test_session(%{}) |> then(&%{&1 | method: "POST"})
      conn = RequireAuthenticatedScope.call(conn, [])

      assert conn.halted
      assert redirected_to(conn) == "/sign-in"
      refute get_session(conn, :user_return_to)
    end
  end
end
