defmodule CadenceWeb.Console.AccountAPITest do
  @moduledoc "The signed-in user's own password and sessions (backlog: Account)."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    %{user: user}
  end

  defp conn_for(token),
    do: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{user_session_token: token})

  defp signed_in?(token),
    do: match?({:ok, _}, Cadence.Auth.authenticate_browser_session(token))

  test "a password change needs the current one and signs out other sessions", c do
    mine = TestFixtures.member_session_token!(c.user)
    other = TestFixtures.member_session_token!(c.user)
    put_password = &(mine |> conn_for() |> put("/api/console/v1/account/password", &1))

    assert %{"error" => %{"code" => "current_password_incorrect"}} =
             put_password.(%{"current_password" => "wrong", "new_password" => "a-new-password-1"})
             |> json_response(422)

    assert %{"error" => %{"details" => %{"new_password" => _}}} =
             put_password.(%{
               "current_password" => TestFixtures.default_password(),
               "new_password" => "short"
             })
             |> json_response(422)

    assert put_password.(%{
             "current_password" => TestFixtures.default_password(),
             "new_password" => "a-new-password-1"
           })
           |> response(204)

    assert signed_in?(mine)
    refute signed_in?(other)
    assert {:ok, _} = Cadence.Auth.sign_in(c.user.email, "a-new-password-1")
  end

  test "sessions are listed with the current one marked; revoke one or all the others", c do
    mine = TestFixtures.member_session_token!(c.user)
    second = TestFixtures.member_session_token!(c.user)
    _third = TestFixtures.member_session_token!(c.user)

    sessions =
      mine
      |> conn_for()
      |> get("/api/console/v1/account/sessions")
      |> json_response(200)
      |> get_in(["data", "sessions"])

    assert length(sessions) == 3
    assert [%{"id" => current_id}] = Enum.filter(sessions, & &1["current"])

    # Revoke one of the others by id.
    second_id =
      second
      |> conn_for()
      |> get("/api/console/v1/account/sessions")
      |> json_response(200)
      |> get_in(["data", "sessions"])
      |> Enum.find(& &1["current"])
      |> Map.fetch!("id")

    assert mine
           |> conn_for()
           |> delete("/api/console/v1/account/sessions/#{second_id}")
           |> response(204)

    refute signed_in?(second)

    assert %{"error" => %{"code" => "session_not_found"}} =
             mine
             |> conn_for()
             |> delete("/api/console/v1/account/sessions/#{second_id}")
             |> json_response(404)

    assert %{"data" => %{"revoked" => 1}} =
             mine
             |> conn_for()
             |> delete("/api/console/v1/account/sessions")
             |> json_response(200)

    assert [%{"id" => ^current_id, "current" => true}] =
             mine
             |> conn_for()
             |> get("/api/console/v1/account/sessions")
             |> json_response(200)
             |> get_in(["data", "sessions"])
  end
end
