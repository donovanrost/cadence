defmodule CadenceWeb.Console.AccountAPITest do
  @moduledoc "The signed-in user's own password and sessions (backlog: Account)."
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.Accounts.AttemptLimit
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    %{user: user, org: org}
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

  test "wrong current passwords are held back with 429 and retry_after; an operator can clear it",
       c do
    mine = TestFixtures.member_session_token!(c.user)
    put_password = &(mine |> conn_for() |> put("/api/console/v1/account/password", &1))
    wrong = %{"current_password" => "wrong", "new_password" => "a-new-password-1"}
    right = %{wrong | "current_password" => TestFixtures.default_password()}

    for _ <- 1..6, do: assert(put_password.(wrong) |> json_response(422))

    held = put_password.(right)

    assert %{"error" => %{"code" => "too_many_attempts", "details" => %{"retry_after" => 1}}} =
             json_response(held, 429)

    assert get_resp_header(held, "retry-after") == ["1"]

    # The check is shared with sign-in for the same account.
    assert {:error, {:too_many_attempts, _}} =
             Cadence.Auth.sign_in(c.user.email, TestFixtures.default_password(),
               ip: {127, 0, 0, 1}
             )

    AttemptLimit.clear(c.user.email)
    assert put_password.(right) |> response(204)
  end

  test "password changes and session sign-outs reach the organization audit, without secrets",
       c do
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, c.org, role: :organization_admin)
    mine = TestFixtures.member_session_token!(c.user)
    other = TestFixtures.member_session_token!(c.user)
    _third = TestFixtures.member_session_token!(c.user)

    other_id =
      other
      |> conn_for()
      |> get("/api/console/v1/account/sessions")
      |> json_response(200)
      |> get_in(["data", "sessions"])
      |> Enum.find(& &1["current"])
      |> Map.fetch!("id")

    assert mine
           |> conn_for()
           |> delete("/api/console/v1/account/sessions/#{other_id}")
           |> response(204)

    assert mine
           |> conn_for()
           |> put("/api/console/v1/account/password", %{
             "current_password" => TestFixtures.default_password(),
             "new_password" => "a-new-password-1"
           })
           |> response(204)

    body =
      admin
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/organizations/#{c.org.organization_id}/audit?kinds=account")
      |> response(200)

    events = body |> Jason.decode!() |> get_in(["data", "events"])

    assert [
             %{"action" => "Changed their password and signed out 1 other session"} = changed,
             %{"action" => "Signed out one of their other sessions"}
           ] = events

    assert %{"kind" => "account", "actor" => %{"id" => actor_id}, "target" => nil} = changed
    assert actor_id == c.user.user_id
    refute body =~ "a-new-password-1"
    refute body =~ mine
  end
end
