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
  alias LiveVue.Test

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
      assert_admin_surface(
        conn,
        ~p"/admin",
        "admin-home-component",
        "admin_home",
        page_id: "admin-home-page"
      )

      assert_admin_surface(
        conn,
        ~p"/admin/runtime",
        "admin-runtime-component",
        "admin_runtime",
        class: "contents"
      )

      assert_admin_surface(
        conn,
        ~p"/admin/organizations",
        "admin-organization-list-page-component",
        "admin_organizations"
      )

      assert_admin_surface(
        conn,
        ~p"/admin/organizations/new",
        "admin-organization-new-component",
        "admin_organization_new"
      )

      organization_id = "organization-admin-test"

      assert_admin_surface(
        conn,
        ~p"/admin/organizations/#{organization_id}",
        "admin-organization-show-component",
        "admin_organization_show",
        page_id: "admin-organization-show-page",
        query_params: %{"organization_id" => organization_id}
      )

      assert_admin_surface(
        conn,
        ~p"/admin/organizations/#{organization_id}/invite",
        "admin-organization-invite-component",
        "admin_organization_invite",
        query_params: %{"organization_id" => organization_id}
      )
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

  defp assert_admin_surface(conn, path, id, surface_id, opts \\ []) do
    {:ok, view, _html} = live(conn, path)

    if page_id = Keyword.get(opts, :page_id) do
      assert has_element?(view, "##{page_id}")
    end

    assert has_element?(view, "##{id}")
    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.ssr == false
    assert vue.handlers == %{}

    if class = Keyword.get(opts, :class) do
      assert vue.class == class
    end

    expected_props = %{
      "application_key" => "organization_admin",
      "surface_id" => surface_id,
      "host_scope" => "admin"
    }

    assert vue.props ==
             Map.merge(expected_props, query_props(Keyword.get(opts, :query_params, %{})))
  end

  defp query_props(%{} = query_params) when map_size(query_params) == 0, do: %{}

  defp query_props(query_params), do: %{"query_params" => query_params}

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
