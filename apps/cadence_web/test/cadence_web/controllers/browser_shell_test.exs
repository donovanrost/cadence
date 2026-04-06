defmodule CadenceWeb.BrowserShellTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.SetupWorkflowRow
  alias Cadence.Repo
  alias Cadence.Setup.Workflow

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

    on_exit(fn ->
      Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
    end)

    :ok
  end

  test "unauthenticated root redirects to sign-in", %{conn: conn} do
    conn = get(conn, "/")

    assert redirected_to(conn) == "/sign-in"
    assert get_session(conn, :user_return_to) == "/"
  end

  test "authenticated root redirects to the operator route", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/")

    assert redirected_to(conn) == "/setup"
  end

  test "authenticated sign-in entry redirects setup access to setup", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/sign-in")

    assert redirected_to(conn) == "/setup"
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

    conn =
      conn
      |> recycle()
      |> get("/setup")

    response = html_response(conn, 200)

    assert response =~ "setup-home"
    assert response =~ "first-tenant-form"
    assert response =~ "Bootstrap Admin"
    assert response =~ @bootstrap_admin_email
  end

  test "setup access can create the first tenant and keep setup context active", %{conn: conn} do
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

    setup_conn =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/setup")

    response = html_response(setup_conn, 200)

    assert response =~ "Cadence Operations"
    assert response =~ "setup-active-organization"
    assert response =~ "Durable admin handoff still pending"
    refute response =~ "first-tenant-form"

    root_conn =
      build_conn()
      |> init_test_session(%{user_session_token: session_token})
      |> get("/")

    assert redirected_to(root_conn) == "/setup"
  end

  test "first tenant creation requires both tenant name and slug", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> post("/setup/organizations", %{
        "organization" => %{
          "display_name" => "Cadence Operations"
        }
      })

    response = html_response(conn, 422)

    assert response =~ "Enter both the tenant name and slug."
    assert response =~ "first-tenant-form"
  end

  test "duplicate tenant creation returns a predictable error in partial setup state", %{
    conn: conn
  } do
    persist_first_tenant!(organization_id: "org-existing", slug: "cadence-operations")
    persist_pending_tenant_creation_workflow!()

    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> post("/setup/organizations", %{
        "organization" => %{
          "display_name" => "Cadence Operations Duplicate",
          "slug" => "cadence-operations"
        }
      })

    response = html_response(conn, 422)

    assert response =~ "Tenant slug has already been taken"
    assert response =~ "first-tenant-form"
  end

  test "invalid inferred setup state keeps setup traffic on the setup route", %{conn: conn} do
    persist_first_tenant!(organization_id: "org-alpha", slug: "org-alpha")
    persist_first_tenant!(organization_id: "org-bravo", slug: "org-bravo")

    root_conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/")

    assert redirected_to(root_conn) == "/setup"

    setup_conn =
      build_conn()
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/setup")

    response = html_response(setup_conn, 200)

    assert response =~ "Cadence setup needs operator attention"
    assert response =~ "Cadence found an invalid first-run setup state."
    refute response =~ "first-tenant-form"
  end

  test "legacy single-tenant installs without workflow state route setup access to operator", %{
    conn: conn
  } do
    persist_first_tenant!(organization_id: "org-cadence", slug: "cadence-inc")

    root_conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/")

    assert redirected_to(root_conn) == "/operator"

    setup_conn =
      build_conn()
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/setup")

    assert redirected_to(setup_conn) == "/operator"
  end

  test "setup access is redirected away from the generic operator shell", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/operator")

    assert redirected_to(conn) == "/setup"
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

  test "malformed setup_access_session params re-render the sign-in form", %{conn: conn} do
    conn =
      post(conn, "/sign-in", %{
        "setup_access_session" => "malformed"
      })

    response = html_response(conn, 422)

    assert response =~ "setup-access-sign-in-form"
    assert response =~ "Submit a valid setup access sign-in form."
  end

  test "completed setup sends authenticated root traffic to operator home", %{conn: conn} do
    persist_completed_setup!()

    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/")

    assert redirected_to(conn) == "/operator"
  end

  test "completed setup redirects authenticated sign-in traffic to operator home", %{conn: conn} do
    persist_completed_setup!()

    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/sign-in")

    assert redirected_to(conn) == "/operator"
  end

  test "completed setup allows the bootstrap-backed browser session to reach operator home", %{
    conn: conn
  } do
    persist_completed_setup!()

    conn =
      conn
      |> init_test_session(%{user_session_token: bootstrap_admin_session_token()})
      |> get("/operator")

    response = html_response(conn, 200)

    assert response =~ "operator-home"
    assert response =~ "Bootstrap Admin"
  end

  defp bootstrap_admin_session_token do
    assert {:ok, issued_session} =
             Cadence.login_bootstrap_admin(@bootstrap_admin_email, @bootstrap_admin_password)

    issued_session.session_token
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

  defp persist_pending_tenant_creation_workflow! do
    workflow =
      Workflow.new(%{
        setup_workflow_id: Workflow.initial_workflow_id(),
        current_step: :pending_tenant_creation
      })

    assert {:ok, _row} = Repo.insert(SetupWorkflowRow.changeset(workflow))
  end
end
