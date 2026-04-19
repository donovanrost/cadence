defmodule CadenceWeb.NoOrganizationControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  test "renders for authenticated user with no membership" do
    user = TestFixtures.persist_user!()
    conn = TestFixtures.member_conn(user)

    html =
      conn
      |> get("/no-organization")
      |> html_response(200)

    assert html =~ "don&#39;t have access"
    assert html =~ "Sign out"
  end

  test "redirects to /sign-in when unauthenticated", %{conn: conn} do
    conn = get(conn, "/no-organization")
    assert redirected_to(conn) == "/sign-in"
  end
end
