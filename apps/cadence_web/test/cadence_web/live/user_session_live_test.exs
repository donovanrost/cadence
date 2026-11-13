defmodule CadenceWeb.UserSessionLiveTest do
  @moduledoc "The old sign-in page's GET now goes to the console's sign-in (L5)."
  use CadenceWeb.ConnCase, async: true

  test "GET /sign-in goes to the console's sign-in", %{conn: conn} do
    assert redirected_to(get(conn, "/sign-in")) == "/console/sign-in"
  end

  test "return_to is carried along (the console checks it)", %{conn: conn} do
    conn = get(conn, "/sign-in?return_to=%2Fconsole%2Fm%2Fearendil%2Ffleet")
    assert redirected_to(conn) == "/console/sign-in?return_to=%2Fconsole%2Fm%2Fearendil%2Ffleet"
  end

  test "the legacy POST still signs in a page that was already open", %{conn: conn} do
    user = CadenceWeb.TestFixtures.persist_user!()

    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => user.email,
          "password" => CadenceWeb.TestFixtures.default_password()
        }
      })

    assert is_binary(get_session(conn, :user_session_token))
  end
end
