defmodule CadenceWeb.AdminLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Accounts.{Authentication, Password, User, UserLocalCredentialRow, UserRow}
  alias Cadence.Ids
  alias Cadence.Repo
  alias CadenceWeb.HostTransportTestSupport

  setup %{conn: conn} do
    issued_session = issue_platform_admin_session!()

    admin_conn =
      init_test_session(conn, %{
        user_session_token: issued_session.session_token,
        admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
      })

    {:ok, admin_conn: admin_conn}
  end

  describe "federated surfaces" do
    test "platform admins can mount the admin routes", %{admin_conn: conn} do
      for {path, page} <- [
            {"/admin", "platform_overview"},
            {"/admin/organizations", "organization_directory"},
            {"/admin/organizations/new", "organization_create"}
          ] do
        {:ok, view, _} = live(conn, path)
        snapshot = HostTransportTestSupport.assert_context(view, %{"host_scope" => "admin"})
        assert snapshot["platform_administration_page"]["page"] == page
        assert snapshot["platform_administration_page"]["status"] == "ready"
      end

      {:ok, diagnostics_view, _html} = live(conn, ~p"/admin/runtime")

      snapshot =
        HostTransportTestSupport.assert_context(diagnostics_view, %{"host_scope" => "admin"})

      assert [%{"id" => "dashboards.runtime-diagnostics", "version" => 1, "status" => "ready"}] =
               snapshot["diagnostics"]

      organization_id = "organization-admin-test"

      for {path, page} <- [
            {"/admin/organizations/#{organization_id}", "organization_detail"},
            {"/admin/organizations/#{organization_id}/invite", "organization_invite"}
          ] do
        {:ok, view, _} = live(conn, path)
        snapshot = HostTransportTestSupport.assert_context(view, %{"host_scope" => "admin"})
        assert snapshot["platform_administration_page"]["page"] == page
        assert snapshot["platform_administration_page"]["organization_id"] == organization_id
        assert snapshot["platform_administration_page"]["status"] == "unavailable"
      end
    end
  end

  describe "authorization" do
    test "non-admin user is redirected to /" do
      durable_password = "durable-password-123"

      persist_durable_user!(
        email: "regular@example.com",
        password: durable_password,
        capabilities: []
      )

      {:ok, session} = Cadence.Auth.sign_in("regular@example.com", durable_password)
      conn = build_conn() |> init_test_session(%{user_session_token: session.session_token})

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/runtime")
    end

    test "admin-eligible durable user without admin mode is redirected to reauthenticate" do
      password = "durable-admin-password-123"

      persist_durable_user!(
        email: "eligible-admin@example.com",
        password: password,
        capabilities: [:platform_admin]
      )

      {:ok, session} = Cadence.Auth.sign_in("eligible-admin@example.com", password)
      conn = build_conn() |> init_test_session(%{user_session_token: session.session_token})

      assert {:error, {:redirect, %{to: "/admin-mode"}}} = live(conn, ~p"/admin")
    end
  end

  defp issue_platform_admin_session! do
    user =
      User.new(%{
        user_id: Ids.new("user"),
        email: "platform-admin-#{System.unique_integer([:positive])}@example.test",
        display_name: "Platform Administrator",
        capabilities: [:platform_admin],
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))
    assert {:ok, issued_session} = Authentication.issue_browser_session(user, nil)
    issued_session
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
end
