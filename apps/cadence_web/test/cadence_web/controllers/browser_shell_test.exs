defmodule CadenceWeb.BrowserShellTest do
  use CadenceWeb.ConnCase, async: false

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

  test "sign-in page renders a single unified sign-in form", %{conn: conn} do
    response = conn |> get("/sign-in") |> html_response(200)

    assert response =~ "Sign in"
    assert response =~ ~s(id="sign-in-form")
    refute response =~ "setup-access-sign-in-form"
    refute response =~ "durable-sign-in-form"
  end

  test "environment admin credentials on /sign-in enter admin mode and route to admin dashboard",
       %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @environment_admin_email,
          "password" => @environment_admin_password
        }
      })

    assert redirected_to(conn) == "/admin"
    assert CadenceWeb.AdminMode.active?(get_session(conn, :admin_mode_expires_at))
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

  test "durable user sign-in reaches the organization home", %{conn: _conn} do
    durable_password = "durable-password-123"
    persist_durable_user!(email: "ops-lead@example.com", password: durable_password)

    org = Organization.new(%{display_name: "Cadence Operations", slug: "cadence-operations"})
    assert {:ok, persisted_org} = Cadence.Organizations.persist_organization(org)

    assert {:ok, _result} =
             Cadence.Accounts.establish_organization_access(
               "ops-lead@example.com",
               persisted_org.organization_id,
               membership_role: :organization_admin,
               invited_by_user_id: "user_environment_admin"
             )

    durable_conn =
      build_conn()
      |> post("/sign-in", %{
        "user" => %{
          "email" => "ops-lead@example.com",
          "password" => durable_password
        }
      })

    assert redirected_to(durable_conn) == "/"
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

    admin_mode_page = build_conn() |> init_test_session(ordinary_session) |> get("/admin-mode")
    assert html_response(admin_mode_page, 200) =~ ~s(id="admin-mode-form")

    elevated_conn =
      build_conn()
      |> init_test_session(ordinary_session)
      |> post("/admin-mode", %{"admin_mode" => %{"password" => password}})

    assert redirected_to(elevated_conn) == "/admin"
    admin_mode_expires_at = get_session(elevated_conn, :admin_mode_expires_at)
    assert CadenceWeb.AdminMode.active?(admin_mode_expires_at)

    assert build_conn()
           |> init_test_session(%{
             user_session_token: session.session_token,
             admin_mode_expires_at: admin_mode_expires_at
           })
           |> get("/admin")
           |> html_response(200) =~
             "Platform Administration"
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

  test "invitation acceptance creates a durable session and routes to org home", %{conn: _conn} do
    org = Organization.new(%{display_name: "Cadence Operations", slug: "cadence-operations"})
    assert {:ok, persisted_org} = Cadence.Organizations.persist_organization(org)

    assert {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} =
             Cadence.Accounts.establish_organization_access(
               "new-admin@example.com",
               persisted_org.organization_id,
               membership_role: :organization_admin,
               invited_by_user_id: "user_environment_admin",
               display_name: "New Admin"
             )

    assert {:ok, email} =
             CadenceWeb.UserNotifier.deliver_organization_invitation(
               invitation,
               persisted_org,
               "http://localhost:4002/invitations/#{token}"
             )

    assert email.subject == "Cadence invitation for Cadence Operations"
    assert email.to == [{"", "new-admin@example.com"}]

    invitation_path = "/invitations/#{token}"

    invitation_response =
      build_conn()
      |> get(invitation_path)
      |> html_response(200)

    assert invitation_response =~ "organization-invitation-acceptance-form"
    assert invitation_response =~ "new-admin@example.com"

    accepted_conn =
      build_conn()
      |> post(invitation_path, %{
        "organization_invitation_acceptance" => %{
          "display_name" => "New Admin",
          "password" => "new-admin-password-123",
          "password_confirmation" => "new-admin-password-123"
        }
      })

    assert redirected_to(accepted_conn) == "/"
  end

  test "invalid credentials redirect back to /sign-in with a flash error", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @environment_admin_email,
          "password" => "definitely-wrong"
        }
      })

    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "rejected"
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

  test "disabled environment-admin config rejects environment-admin credentials",
       %{conn: conn} do
    assert {:ok, nil} =
             Cadence.Auth.reconcile_environment_admin(
               EnvironmentAdminPolicy.from_config(enabled: false)
             )

    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @environment_admin_email,
          "password" => @environment_admin_password
        }
      })

    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "rejected"
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
