defmodule CadenceWeb.BrowserShellTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cadence.Accounts.{
    EnvironmentAdminPolicy,
    Password,
    User,
    UserLocalCredentialRow,
    UserRow
  }

  alias Cadence.Ids
  alias Cadence.Organizations.Organization
  alias Cadence.Repo
  alias LiveVue.Test

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

  test "unauthenticated root redirects to sign-in", %{conn: conn} do
    conn = get(conn, "/")

    assert redirected_to(conn) == "/sign-in"
    assert get_session(conn, :user_return_to) == "/"
  end

  # L5: the sign-in page's GET goes to the console's sign-in screen (ecdddab10).
  test "GET /sign-in goes to the console's sign-in", %{conn: conn} do
    assert redirected_to(get(conn, "/sign-in")) == "/console/sign-in"
  end

  test "platform admin root redirect routes to admin dashboard", %{conn: conn} do
    root_conn =
      conn
      |> environment_admin_conn()
      |> get("/")

    assert redirected_to(root_conn) == "/admin"
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

  test "expired admin mode requires reauthentication", %{conn: conn} do
    issued_session = environment_admin_session()

    expired_conn =
      conn
      |> init_test_session(%{
        user_session_token: issued_session.session_token,
        admin_mode_expires_at: 0
      })
      |> get("/admin")

    assert redirected_to(expired_conn) == "/admin-mode"
  end

  test "durable platform administrator must reauthenticate to enter admin mode", %{conn: _conn} do
    password = "durable-admin-password-123"

    persist_durable_user!(
      email: "durable-admin@example.com",
      password: password,
      capabilities: [:platform_admin]
    )

    assert {:ok, session} = Cadence.Auth.sign_in("durable-admin@example.com", password)
    refute session.admin_mode?

    ordinary_session = %{user_session_token: session.session_token}
    ordinary_admin_conn = build_conn() |> init_test_session(ordinary_session)

    assert ordinary_admin_conn |> get("/admin") |> redirected_to() == "/admin-mode"

    {:ok, admin_mode_view, _html} =
      build_conn()
      |> init_test_session(ordinary_session)
      |> live("/admin-mode")

    admin_mode_vue = Test.get_vue(admin_mode_view, id: "admin-mode-page-component")

    assert admin_mode_vue.component == "AdminModePage"
    assert admin_mode_vue.ssr == false
    assert admin_mode_vue.props == Jason.decode!(Jason.encode!(admin_mode_vue.props))
    assert is_binary(admin_mode_vue.props["page"]["csrf_token"])
    assert admin_mode_vue.props["page"]["csrf_token"] != ""

    elevated_conn =
      build_conn()
      |> init_test_session(ordinary_session)
      |> post("/admin-mode", %{"admin_mode" => %{"password" => password}})

    assert redirected_to(elevated_conn) == "/admin"
    admin_mode_expires_at = get_session(elevated_conn, :admin_mode_expires_at)
    assert CadenceWeb.AdminMode.active?(admin_mode_expires_at)

    {:ok, admin_home_view, _html} =
      build_conn()
      |> init_test_session(%{
        user_session_token: session.session_token,
        admin_mode_expires_at: admin_mode_expires_at
      })
      |> live("/admin")

    snapshot = CadenceWeb.HostTransportTestSupport.assert_context(admin_home_view, %{})
    assert snapshot["path"] == "/admin"
    assert snapshot["context"]["admin_mode"]
  end

  test "leaving admin mode removes the durable administrator's elevation", %{conn: _conn} do
    password = "durable-admin-password-123"

    persist_durable_user!(
      email: "durable-admin-exit@example.com",
      password: password,
      capabilities: [:platform_admin]
    )

    assert {:ok, session} = Cadence.Auth.sign_in("durable-admin-exit@example.com", password)

    elevated_conn =
      build_conn()
      |> init_test_session(%{
        user_session_token: session.session_token,
        admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
      })

    exited_conn = delete(elevated_conn, "/admin-mode")
    assert redirected_to(exited_conn) == "/"
    refute get_session(exited_conn, :admin_mode_expires_at)

    assert build_conn()
           |> init_test_session(%{user_session_token: session.session_token})
           |> get("/admin")
           |> redirected_to() == "/admin-mode"
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

    assert redirected_to(conn) == "/sign-in"

    copied_conn =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/")

    assert redirected_to(copied_conn) == "/sign-in"
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

  defp persist_durable_user!(opts) when is_list(opts) do
    password = Keyword.fetch!(opts, :password)
    email = Keyword.fetch!(opts, :email)

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: Keyword.get(opts, :display_name, "Durable User"),
        capabilities: Keyword.get(opts, :capabilities, []),
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  defp flush_mailbox do
    receive do
      {:email, _email} -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
