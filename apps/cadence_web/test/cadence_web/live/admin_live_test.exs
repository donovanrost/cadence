defmodule CadenceWeb.AdminLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

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

  describe "authorization" do
    test "unauthenticated access redirects to /sign-in" do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), ~p"/admin")
    end

    test "non-admin user is redirected to /" do
      durable_password = "durable-password-123"

      persist_durable_user!(
        email: "regular@example.com",
        password: durable_password,
        capabilities: []
      )

      {:ok, session} = Cadence.sign_in("regular@example.com", durable_password)
      conn = build_conn() |> init_test_session(%{user_session_token: session.session_token})

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
    end

    test "platform admin can access the dashboard" do
      {:ok, _view, html} = live(admin_conn(), ~p"/admin")
      assert html =~ "Platform Administration"
    end
  end

  describe "organization management" do
    test "admin dashboard shows organization and user counts" do
      {:ok, _view, html} = live(admin_conn(), ~p"/admin")
      assert html =~ "Organizations"
      assert html =~ "Users"
    end

    test "organization list shows empty state when no orgs exist" do
      {:ok, _view, html} = live(admin_conn(), ~p"/admin/organizations")
      assert html =~ "No organizations yet"
    end

    test "admin can create an organization" do
      {:ok, view, _html} = live(admin_conn(), ~p"/admin/organizations/new")

      view
      |> form("#org-form", organization: %{display_name: "Test Org", slug: "test-org"})
      |> render_submit()

      assert_redirect(view, ~p"/admin/organizations")

      # Verify the org appears in the list
      {:ok, _view, html} = live(admin_conn(), ~p"/admin/organizations")
      assert html =~ "Test Org"
      assert html =~ "test-org"
    end

    test "admin can view organization detail with no members" do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      {:ok, _view, html} = live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}")
      assert html =~ "Cadence Ops"
      assert html =~ "No members yet"
    end
  end

  describe "invitation" do
    test "admin can invite a new user and invitation email is delivered" do
      org = create_test_org!("Cadence Ops", "cadence-ops")

      {:ok, view, _html} =
        live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}/invite")

      view
      |> form("#invite-form",
        invite: %{
          email: "new-user@example.com",
          display_name: "New User",
          membership_role: "organization_admin"
        }
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/organizations/#{org.organization_id}")

      # Verify invitation email was delivered
      assert_received {:email, email}
      assert email.to == [{"", "new-user@example.com"}]
    end

    test "admin can grant an existing durable user directly" do
      org = create_test_org!("Cadence Ops", "cadence-ops")
      persist_durable_user!(email: "existing@example.com", password: "password-123456")

      {:ok, view, _html} =
        live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}/invite")

      view
      |> form("#invite-form",
        invite: %{
          email: "existing@example.com",
          membership_role: "member"
        }
      )
      |> render_submit()

      # Should redirect back to org detail
      assert_redirect(view, ~p"/admin/organizations/#{org.organization_id}")

      # Verify the member appears on the org detail page
      {:ok, _view, html} = live(admin_conn(), ~p"/admin/organizations/#{org.organization_id}")
      assert html =~ "existing@example.com"
    end
  end

  ## Helpers

  defp admin_conn do
    token = bootstrap_admin_session_token()
    build_conn() |> init_test_session(%{user_session_token: token})
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

  defp create_test_org!(display_name, slug) do
    org = Organization.new(%{display_name: display_name, slug: slug})
    assert {:ok, persisted} = Cadence.persist_organization(org)
    persisted
  end

  defp flush_mailbox do
    receive do
      {:email, _email} -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
