defmodule CadenceWeb.BrowserShellTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Accounts.EnvironmentAdminPolicy
  alias Cadence.Organizations.Organization

  @environment_admin_email "environment-admin@example.com"
  @environment_admin_password "environment-admin-password-123"

  setup do
    assert {:ok, _user} =
             Cadence.Auth.reconcile_environment_admin(environment_admin_policy())

    flush_mailbox()

    on_exit(fn ->
      flush_mailbox()
    end)

    :ok
  end

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

  test "environment admin in admin mode can open any organization without membership",
       %{conn: conn} do
    organization =
      Organization.new(%{display_name: "Admin Selected Org", slug: "admin-selected-org"})

    assert {:ok, organization} = Cadence.Organizations.persist_organization(organization)

    selected_conn =
      conn
      |> environment_admin_conn()
      |> put("/session/organization", %{"organization_id" => organization.organization_id})

    assert redirected_to(selected_conn) == "/"
    assert get_session(selected_conn, :current_organization_id) == organization.organization_id

    assert {:ok, scope} =
             Cadence.Auth.authenticate_browser_session(
               get_session(selected_conn, :user_session_token),
               current_organization_id: organization.organization_id,
               admin_mode?: true
             )

    assert scope.organization.organization_id == organization.organization_id
    assert scope.organization_membership == nil
  end

  test "logout revokes the issued environment-admin browser session", %{conn: conn} do
    issued_session = environment_admin_session()
    session_token = issued_session.session_token

    conn =
      conn
      |> init_test_session(%{
        user_session_token: session_token,
        admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
      })
      |> delete("/session")

    assert redirected_to(conn) == "/console/sign-in"

    copied_conn =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/console/")

    assert redirected_to(copied_conn) == "/console/sign-in"
    assert {:error, :unauthenticated} = Cadence.Auth.authenticate_browser_session(session_token)
    assert {:error, :unauthenticated} = Cadence.Auth.authenticate_api_token(session_token)
  end

  defp environment_admin_session do
    assert {:ok, issued_session} =
             Cadence.Auth.login_environment_admin(
               @environment_admin_email,
               @environment_admin_password
             )

    issued_session
  end

  defp environment_admin_policy do
    EnvironmentAdminPolicy.from_config(
      enabled: true,
      email: @environment_admin_email,
      display_name: "Environment Admin",
      password: @environment_admin_password
    )
  end

  defp environment_admin_conn(conn) do
    issued_session = environment_admin_session()

    init_test_session(conn, %{
      user_session_token: issued_session.session_token,
      admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
    })
  end

  defp flush_mailbox do
    receive do
      {:email, _email} -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
