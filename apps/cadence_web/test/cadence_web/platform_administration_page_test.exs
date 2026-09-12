defmodule CadenceWeb.PlatformAdministrationPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Accounts.UserRow
  alias Cadence.{Organizations, Repo}
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!(capabilities: [:platform_admin])

    conn =
      user
      |> TestFixtures.member_conn()
      |> put_session(:admin_mode_expires_at, CadenceWeb.AdminMode.expires_at())

    %{user: user, conn: conn}
  end

  test "overview, directory and creation are authorized core reads with refreshed counts", c do
    {:ok, view, _} = live(c.conn, "/admin")
    assert page(view)["page"] == "platform_overview"
    assert page(view)["status"] == "ready"
    assert snapshot(view)["context"]["admin_mode"] == true
    render_hook(view, "host:context", %{"path" => "/admin/organizations?user_id=foreign"})
    assert page(view)["page"] == "organization_directory"
    assert page(view)["user_id"] == c.user.user_id
    render_hook(view, "host:context", %{"path" => "/admin/organizations/new"})
    assert page(view)["data"]["created"] == nil
    act(view, page(view)["action_token"])
    created = page(view)["data"]["created"]
    assert {:ok, org} = Organizations.fetch_organization(created["id"])
    assert org.display_name == "Created organization"
    render_hook(view, "host:context", %{"path" => "/admin/organizations/new"})
    assert page(view)["data"]["created"]["id"] == org.organization_id
    render_hook(view, "host:context", %{"path" => "/admin"})
    assert page(view)["data"]["counts"]["organizations"] == 1
    assert has_element?(view, "#application-shell")
  end

  test "successful visit is consumed, stale or foreign tokens and departed forms cannot create",
       c do
    {:ok, view, _} = live(c.conn, "/admin/organizations/new")
    token = page(view)["action_token"]
    act(view, "foreign")
    assert Organizations.count_organizations() == 0
    act(view, token)
    act(view, token, "second")
    assert Organizations.count_organizations() == 1
    render_hook(view, "host:context", %{"path" => "/admin/organizations"})
    act(view, token, "departed")
    render_hook(view, "host:context", %{"path" => "/admin/organizations/new"})
    refute page(view)["action_token"] == token
    act(view, token, "stale")
    assert Organizations.count_organizations() == 1
  end

  test "revoked sessions and freshly revoked platform privilege cannot submit", c do
    {:ok, view, _} = live(c.conn, "/admin/organizations/new")
    token = page(view)["action_token"]

    Repo.get!(UserRow, c.user.user_id)
    |> Ecto.Changeset.change(capabilities: [])
    |> Repo.update!()

    act(view, token)
    assert_redirect(view, "/")
    assert Organizations.count_organizations() == 0

    other = TestFixtures.persist_user!(capabilities: [:platform_admin])

    conn =
      other
      |> TestFixtures.member_conn()
      |> put_session(:admin_mode_expires_at, CadenceWeb.AdminMode.expires_at())

    {:ok, second, _} = live(conn, "/admin/organizations/new")
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    act(second, page(second)["action_token"])
    assert_redirect(second, "/sign-in")
    assert Organizations.count_organizations() == 0
  end

  test "all three URLs require active admin mode; invalid paging remains unavailable", c do
    without_mode = delete_session(c.conn, :admin_mode_expires_at)
    expired = put_session(c.conn, :admin_mode_expires_at, 0)
    member = TestFixtures.persist_user!() |> TestFixtures.member_conn()

    for path <- ["/admin", "/admin/organizations", "/admin/organizations/new"] do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path)
      assert {:error, {:redirect, %{to: "/admin-mode"}}} = live(without_mode, path)
      assert {:error, {:redirect, %{to: "/admin-mode"}}} = live(expired, path)
      assert {:error, {:redirect, %{to: "/"}}} = live(member, path)
    end

    {:ok, view, _} = live(c.conn, "/admin/organizations?after_id=missing")
    assert page(view)["status"] == "unavailable"
    render_hook(view, "host:context", %{"path" => "/admin/organizations"})
    assert page(view)["status"] == "ready"
  end

  defp snapshot(view), do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
  defp page(view), do: snapshot(view)["platform_administration_page"]

  defp act(view, token, slug \\ "created-org") do
    render_hook(view, "host:platform-administration", %{
      "path" => "/admin/organizations/new",
      "token" => token,
      "event" => "create",
      "input" => %{"display_name" => "Created organization", "slug" => slug}
    })
  end
end
