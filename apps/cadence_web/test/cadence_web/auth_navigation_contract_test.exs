defmodule CadenceWeb.AuthNavigationContractTest do
  use CadenceWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cadence.Auth
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test
  alias Plug.Conn.Query

  # L5 retired the sign-in, no-organization and invitation pages (their GETs go to the console;
  # see user_session_live_test, no_organization_controller_test and the invitation controller
  # test). The admin-mode page and the '/' shell stay until L7's console replaces them.
  test "real native forms drive Phoenix organization, admin mode and sign-out effects", %{
    conn: _conn
  } do
    admin = TestFixtures.persist_user!(capabilities: [:platform_admin])
    first = TestFixtures.persist_org!()
    second = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(admin, first)
    TestFixtures.grant_membership!(admin, second)

    admin_conn =
      admin
      |> TestFixtures.member_conn()
      |> put_session(:current_organization_id, first.organization_id)

    {:ok, mode_view, _} = live(admin_conn, "/admin-mode")
    {:ok, home_view, _} = live(admin_conn, "/")

    document = %{
      admin_mode: Test.get_vue(mode_view, id: "admin-mode-page-component").props["page"],
      snapshot: Test.get_vue(home_view, id: "application-shell").props["snapshot"],
      email: admin.email,
      password: TestFixtures.default_password(),
      other_organization_id: second.organization_id
    }

    probe =
      Path.expand(
        "../../../../frontend/apps/host/src/auth-and-navigation/features/sign-in/producer-consumer-probe.mjs",
        __DIR__
      )

    {output, code} = System.cmd("node", [probe, Jason.encode!(document)], stderr_to_stdout: true)
    assert code == 0, output
    [_, encoded] = Regex.run(~r/AUTH_NATIVE_INPUT=([A-Za-z0-9+\/=]+)/, output)
    forms = encoded |> Base.decode64!() |> Jason.decode!()

    assert Enum.all?(forms, fn {_, form} ->
             form["method"] == "post" and form["fields"]["_csrf_token"] != ""
           end)

    switched = native_post(admin_conn, forms["switch_organization"])
    assert get_session(switched, :current_organization_id) == second.organization_id
    enabled = native_post(recycle(switched), forms["admin_mode"])
    assert redirected_to(enabled) == "/admin"
    assert is_integer(get_session(enabled, :admin_mode_expires_at))
    signed_out = native_post(recycle(enabled), forms["sign_out"])
    refute get_session(signed_out, :user_session_token)

    assert {:error, :unauthenticated} =
             Auth.authenticate_browser_session(get_session(admin_conn, :user_session_token))
  end

  defp native_post(conn, form) do
    fields = form["fields"] |> Query.encode() |> Query.decode()

    case Map.get(fields, "_method", "post") do
      "put" -> put(conn, form["action"], fields)
      "delete" -> delete(conn, form["action"], fields)
      "post" -> post(conn, form["action"], fields)
    end
  end
end
