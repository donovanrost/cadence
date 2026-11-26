defmodule CadenceWeb.BrowserShellTest do
  use CadenceWeb.ConnCase, async: true

  test "the site root opens the console", %{conn: conn} do
    assert redirected_to(get(conn, "/")) == "/console"
  end

  test "signed out, the console sends you to its sign-in and back", %{conn: conn} do
    conn = get(conn, "/console/")

    assert redirected_to(conn) == "/console/sign-in"
    assert get_session(conn, :user_return_to) == "/console/"
  end

  test "the old root sign-in page is gone", %{conn: conn} do
    assert conn |> get("/sign-in") |> response(404)
  end

  # #664: sign-out and organization selection are the console API's (`/api/v1/session`).
  test "the old root session routes are gone", %{conn: conn} do
    assert conn |> delete("/session") |> response(404)
    assert conn |> put("/session/organization", %{"organization_id" => "org"}) |> response(404)
  end
end
