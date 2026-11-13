defmodule CadenceWeb.AuthRedirectControllerTest do
  @moduledoc """
  L5: the old auth pages' GETs go to the console's screens; their legacy POSTs (a form left open in
  an old tab) get a 303 there too, since the pages are gone (DECISIONS #79).
  """
  use CadenceWeb.ConnCase, async: true

  test "GET /sign-in goes to the console's sign-in", %{conn: conn} do
    assert redirected_to(get(conn, "/sign-in")) == "/console/sign-in"
  end

  test "return_to is carried along (the console checks it)", %{conn: conn} do
    conn = get(conn, "/sign-in?return_to=%2Fconsole%2Fm%2Fearendil%2Ffleet")
    assert redirected_to(conn) == "/console/sign-in?return_to=%2Fconsole%2Fm%2Fearendil%2Ffleet"
  end

  test "a legacy sign-in POST gets a 303 to the console's sign-in, with no session", %{conn: conn} do
    conn = post(conn, "/sign-in", %{"user" => %{"email" => "a@b.c", "password" => "x"}})
    assert conn.status == 303
    assert redirected_to(conn, 303) == "/console/sign-in"
    refute get_session(conn, :user_session_token)
  end

  test "a legacy invitation POST gets a 303 to the console's invitation screen", %{conn: conn} do
    conn = post(conn, "/invitations/tok-123", %{})
    assert redirected_to(conn, 303) == "/console/invitations/tok-123"
  end

  test "the old admin-mode page goes to the console (L6; the account menu holds admin mode)" do
    conn = CadenceWeb.TestFixtures.persist_user!() |> CadenceWeb.TestFixtures.member_conn()
    assert redirected_to(get(conn, "/admin-mode")) == "/console"
  end

  test "the old notifications page goes to the console's Account page (L21)" do
    conn = CadenceWeb.TestFixtures.persist_user!() |> CadenceWeb.TestFixtures.member_conn()
    assert redirected_to(get(conn, "/notifications")) == "/console/account"
  end
end
