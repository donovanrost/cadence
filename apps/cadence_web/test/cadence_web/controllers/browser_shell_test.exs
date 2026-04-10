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

  test "sign-in page shows durable and setup access forms while setup is pending", %{conn: conn} do
    response = conn |> get("/sign-in") |> html_response(200)

    assert response =~ "durable-sign-in-form"
    assert response =~ "setup-access-sign-in-form"
  end

  test "setup access can establish a browser session and reach setup home", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "setup_access_session" => %{
          "email" => @bootstrap_admin_email,
          "password" => @bootstrap_admin_password
        }
      })

    assert redirected_to(conn) == "/setup"

    response =
      conn
      |> recycle()
      |> get("/setup")
      |> html_response(200)

    assert response =~ "setup-home"
    assert response =~ "first-tenant-form"
    assert response =~ "Bootstrap Admin"
    assert response =~ @bootstrap_admin_email
  end

  test "creating the first tenant surfaces the durable admin handoff form", %{conn: conn} do
    session_token = bootstrap_admin_session_token()

    conn =
      conn
      |> init_test_session(%{user_session_token: session_token})
      |> post("/setup/organizations", %{
        "organization" => %{
          "display_name" => "Cadence Operations",
          "slug" => "cadence-operations"
        }
      })

    assert redirected_to(conn) == "/setup"

    response =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/setup")
      |> html_response(200)

    assert response =~ "initial-admin-handoff-form"
    assert response =~ "Cadence Operations"
    refute response =~ "first-tenant-form"
  end

  test "setup handoff grants an existing durable user directly and durable sign-in reaches operator home",
       %{conn: conn} do
    durable_password = "durable-password-123"
    persist_durable_user!(email: "ops-lead@example.com", password: durable_password)
    session_token = bootstrap_admin_session_token()

    create_first_tenant_via_setup!(session_token)

    conn =
      conn
      |> init_test_session(%{user_session_token: session_token})
      |> post("/setup/handoff", %{
        "initial_admin_handoff" => %{
          "email" => "ops-lead@example.com",
          "display_name" => "Ops Lead",
          "membership_role" => "organization_admin"
        }
      })

    assert redirected_to(conn) == "/setup"
    refute_received {:email, _email}

    durable_conn =
      build_conn()
      |> post("/sign-in", %{
        "durable_session" => %{
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

    setup_response =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/setup")
      |> html_response(200)

    assert setup_response =~ "Temporary setup retirement still pending"
  end

  test "setup handoff invites a new durable user and invitation acceptance creates the durable session",
       %{conn: conn} do
    session_token = bootstrap_admin_session_token()
    create_first_tenant_via_setup!(session_token)

    conn =
      conn
      |> init_test_session(%{user_session_token: session_token})
      |> post("/setup/handoff", %{
        "initial_admin_handoff" => %{
          "email" => "new-admin@example.com",
          "display_name" => "New Admin",
          "membership_role" => "organization_admin"
        }
      })

    assert redirected_to(conn) == "/setup"

    assert_received {:email, email}
    assert email.subject == "Cadence invitation for Cadence Operations"
    assert email.to == [{"", "new-admin@example.com"}]

    invitation_path = extract_invitation_path!(email.text_body)

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

    assert {:ok, workflow} = Cadence.fetch_initial_setup_workflow()
    assert workflow.current_step == :pending_completion
  end

  test "invalid bootstrap credentials keep the user on the sign-in page", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "setup_access_session" => %{
          "email" => @bootstrap_admin_email,
          "password" => "definitely-wrong"
        }
      })

    response = html_response(conn, 422)

    assert response =~ "setup-access-sign-in-form"
    assert response =~ "The supplied email or password was rejected."
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
      |> get("/setup")

    assert redirected_to(copied_conn) == "/sign-in"
    assert {:error, :unauthenticated} = Cadence.authenticate_api_token(session_token)
  end

  test "completed setup hides the temporary setup sign-in form and keeps durable sign-in available",
       %{conn: conn} do
    persist_completed_setup!()

    response = conn |> get("/sign-in") |> html_response(200)

    assert response =~ "durable-sign-in-form"
    refute response =~ "setup-access-sign-in-form"
  end

  test "invalid inferred setup state keeps setup traffic on the setup route", %{conn: conn} do
    persist_first_tenant!(organization_id: "org-alpha", slug: "org-alpha")
    persist_first_tenant!(organization_id: "org-bravo", slug: "org-bravo")

    root_conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/")

    assert redirected_to(root_conn) == "/setup"

    response =
      build_conn()
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/setup")
      |> html_response(200)

    assert response =~ "Cadence setup needs operator attention"
    assert response =~ "Cadence found an invalid first-run setup state."
    refute response =~ "first-tenant-form"
  end

  defp bootstrap_admin_session_token do
    assert {:ok, issued_session} =
             Cadence.login_bootstrap_admin(@bootstrap_admin_email, @bootstrap_admin_password)

    issued_session.session_token
  end

  defp create_first_tenant_via_setup!(session_token) do
    conn =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> post("/setup/organizations", %{
        "organization" => %{
          "display_name" => "Cadence Operations",
          "slug" => "cadence-operations"
        }
      })

    assert redirected_to(conn) == "/setup"
  end

  defp persist_completed_setup! do
    persisted_organization =
      persist_first_tenant!(organization_id: "org-cadence", slug: "cadence-inc")

    assert {:ok, _workflow} =
             Cadence.complete_initial_setup(persisted_organization.organization_id)
  end

  defp persist_first_tenant!(opts) when is_list(opts) do
    organization =
      Organization.new(%{
        organization_id: Keyword.get(opts, :organization_id, "org-cadence"),
        slug: Keyword.get(opts, :slug, "cadence-inc"),
        display_name: Keyword.get(opts, :display_name, "Cadence Inc.")
      })

    assert {:ok, persisted_organization} = Cadence.persist_organization(organization)
    persisted_organization
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

  defp extract_invitation_path!(body) when is_binary(body) do
    case Regex.run(~r{https?://[^\s]+/invitations/[^\s]+}, body) do
      [url] ->
        url
        |> URI.parse()
        |> Map.fetch!(:path)

      _other ->
        flunk("Expected invitation URL in email body:\n#{body}")
    end
  end

  defp flush_mailbox do
    receive do
      {:email, _email} -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
