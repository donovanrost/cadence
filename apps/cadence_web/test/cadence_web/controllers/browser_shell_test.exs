defmodule CadenceWeb.BrowserShellTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Accounts.{Password, User}
  alias Cadence.Ids
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.{UserLocalCredentialRow, UserRow}
  alias Cadence.Repo

  @bootstrap_admin_email "bootstrap-admin@example.com"
  @bootstrap_admin_password "bootstrap-password-123"

  setup do
    previous_bootstrap_admin = Application.get_env(:cadence, :bootstrap_admin, [])

    Application.put_env(:cadence, :bootstrap_admin,
      enabled: true,
      user_id: "user_bootstrap_admin",
      email: @bootstrap_admin_email,
      display_name: "Bootstrap Admin",
      password: @bootstrap_admin_password,
      session_ttl_seconds: 3600
    )

    assert {:ok, _user} = Cadence.ensure_bootstrap_admin()
    flush_mailbox()

    on_exit(fn ->
      Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
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

  test "bootstrap credentials on /sign-in route to admin dashboard",
       %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @bootstrap_admin_email,
          "password" => @bootstrap_admin_password
        }
      })

    assert redirected_to(conn) == "/admin"
  end

  test "platform admin root redirect routes to admin dashboard", %{conn: conn} do
    root_conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/")

    assert redirected_to(root_conn) == "/admin"
  end

  test "durable user sign-in reaches operator home", %{conn: conn} do
    durable_password = "durable-password-123"
    persist_durable_user!(email: "ops-lead@example.com", password: durable_password)

    org = Organization.new(%{display_name: "Cadence Operations", slug: "cadence-operations"})
    assert {:ok, persisted_org} = Cadence.persist_organization(org)

    assert {:ok, _result} =
             Cadence.Accounts.establish_organization_access(
               "ops-lead@example.com",
               persisted_org.organization_id,
               membership_role: :organization_admin,
               invited_by_user_id: "user_bootstrap_admin"
             )

    durable_conn =
      build_conn()
      |> post("/sign-in", %{
        "user" => %{
          "email" => "ops-lead@example.com",
          "password" => durable_password
        }
      })

    assert redirected_to(durable_conn) == "/operator"

    response =
      durable_conn
      |> recycle()
      |> get("/operator")
      |> html_response(200)

    assert response =~ "operator-home"
    assert response =~ "ops-lead@example.com"
    assert response =~ "Cadence Operations"
  end

  test "invitation acceptance creates a durable session and routes to operator", %{conn: conn} do
    org = Organization.new(%{display_name: "Cadence Operations", slug: "cadence-operations"})
    assert {:ok, persisted_org} = Cadence.persist_organization(org)

    assert {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} =
             Cadence.Accounts.establish_organization_access(
               "new-admin@example.com",
               persisted_org.organization_id,
               membership_role: :organization_admin,
               invited_by_user_id: "user_bootstrap_admin",
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

    assert redirected_to(accepted_conn) == "/operator"

    operator_response =
      accepted_conn
      |> recycle()
      |> get("/operator")
      |> html_response(200)

    assert operator_response =~ "operator-home"
    assert operator_response =~ "New Admin"
    assert operator_response =~ "Cadence Operations"
  end

  test "invalid credentials redirect back to /sign-in with a flash error", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @bootstrap_admin_email,
          "password" => "definitely-wrong"
        }
      })

    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "rejected"
  end

  test "logout revokes the issued bootstrap session token", %{conn: conn} do
    session_token = bootstrap_admin_session_token()

    conn =
      conn
      |> init_test_session(%{user_session_token: session_token})
      |> delete("/session")

    assert redirected_to(conn) == "/sign-in"

    copied_conn =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/")

    assert redirected_to(copied_conn) == "/sign-in"
    assert {:error, :unauthenticated} = Cadence.authenticate_api_token(session_token)
  end

  test "disabled bootstrap config rejects bootstrap credentials",
       %{conn: conn} do
    Application.put_env(:cadence, :bootstrap_admin, enabled: false)

    conn =
      post(conn, "/sign-in", %{
        "user" => %{
          "email" => @bootstrap_admin_email,
          "password" => @bootstrap_admin_password
        }
      })

    assert redirected_to(conn) == "/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "rejected"
  end

  defp bootstrap_admin_session_token do
    assert {:ok, issued_session} =
             Cadence.login_bootstrap_admin(@bootstrap_admin_email, @bootstrap_admin_password)

    issued_session.session_token
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
