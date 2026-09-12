defmodule CadenceWeb.AuthNavigationContractTest do
  use CadenceWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cadence.Accounts
  alias Cadence.Auth
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test
  alias Plug.Conn.Query

  test "real native forms drive Phoenix session, organization and invitation effects", %{
    conn: conn
  } do
    admin = TestFixtures.persist_user!(capabilities: [:platform_admin])
    first = TestFixtures.persist_org!()
    second = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(admin, first)
    TestFixtures.grant_membership!(admin, second)
    {:ok, signin_view, _} = live(conn, "/sign-in")

    admin_conn =
      admin
      |> TestFixtures.member_conn()
      |> put_session(:current_organization_id, first.organization_id)

    {:ok, mode_view, _} = live(admin_conn, "/admin-mode")
    {:ok, access_view, _} = live(admin_conn, "/no-organization")
    {:ok, home_view, _} = live(admin_conn, "/")
    recipient_email = "native-#{System.unique_integer([:positive])}@example.test"

    assert {:ok, %{invitation_token: token}} =
             Accounts.establish_organization_access(recipient_email, second.organization_id,
               force_invitation: true,
               membership_role: :organization_admin,
               grant_platform_admin: true,
               invited_by_user_id: admin.user_id
             )

    {:ok, invite_view, _} = live(conn, "/invitations/#{token}")

    document = %{
      sign_in: Test.get_vue(signin_view, id: "user-session-component").props["page"],
      admin_mode: Test.get_vue(mode_view, id: "admin-mode-page-component").props["page"],
      organization_access:
        Test.get_vue(access_view, id: "no-organization-page-component").props["page"],
      invitation:
        Test.get_vue(invite_view, id: "organization-invitation-page-component").props["page"],
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

    signin = native_post(conn, forms["sign_in"])
    assert redirected_to(signin) == "/"
    assert {:ok, _} = Auth.authenticate_browser_session(get_session(signin, :user_session_token))
    switched = native_post(recycle(signin), forms["switch_organization"])
    assert get_session(switched, :current_organization_id) == second.organization_id
    enabled = native_post(recycle(switched), forms["admin_mode"])
    assert redirected_to(enabled) == "/admin"
    assert is_integer(get_session(enabled, :admin_mode_expires_at))
    signed_out = native_post(recycle(enabled), forms["sign_out"])
    refute get_session(signed_out, :user_session_token)
    accepted = native_post(conn, forms["invitation"])
    assert is_binary(get_session(accepted, :user_session_token))
    assert get_session(accepted, :current_organization_id) == second.organization_id
    assert {:ok, recipient} = Accounts.fetch_user_by_email(recipient_email)

    assert {:ok, membership} =
             Accounts.fetch_user_membership(recipient.user_id, second.organization_id)

    assert membership.role == :organization_admin
    assert :platform_admin in recipient.capabilities
    refute get_session(accepted, :admin_mode_expires_at)
    removed = native_post(recycle(accepted), forms["organization_access"])
    refute get_session(removed, :user_session_token)
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
