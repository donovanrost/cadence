defmodule CadenceWeb.UserSessionControllerTest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  describe "POST /sign-in" do
    test "stores durable authentication state", %{conn: conn} do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _membership = TestFixtures.grant_membership!(user, org)

      conn =
        post(conn, "/sign-in", %{
          "user" => %{
            "email" => user.email,
            "password" => TestFixtures.default_password()
          }
        })

      assert redirected_to(conn) == "/"
      assert is_binary(get_session(conn, :user_session_token))
      assert get_session(conn, :current_organization_id) == org.organization_id
    end
  end

  describe "PUT /session/organization" do
    test "switches the session current_organization_id for an active membership", %{conn: _conn} do
      user = TestFixtures.persist_user!()
      org_a = TestFixtures.persist_org!(display_name: "Org A")
      org_b = TestFixtures.persist_org!(display_name: "Org B")
      _ = TestFixtures.grant_membership!(user, org_a)

      conn =
        user
        |> TestFixtures.member_conn()
        |> Plug.Conn.put_session(:current_organization_id, org_a.organization_id)

      _ = TestFixtures.grant_membership!(user, org_b)

      conn = put(conn, "/session/organization", %{"organization_id" => org_b.organization_id})

      assert redirected_to(conn) == "/"
      assert get_session(conn, :current_organization_id) == org_b.organization_id
    end

    test "rejects the switch when the user is not an active member of the target org", %{
      conn: _conn
    } do
      user = TestFixtures.persist_user!()
      org_a = TestFixtures.persist_org!(display_name: "Org A")
      other_org = TestFixtures.persist_org!(display_name: "Not Mine")
      _ = TestFixtures.grant_membership!(user, org_a)

      conn = TestFixtures.member_conn(user)

      conn =
        put(conn, "/session/organization", %{"organization_id" => other_org.organization_id})

      assert redirected_to(conn) == "/"
      refute get_session(conn, :current_organization_id) == other_org.organization_id

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "organization"
    end

    test "redirects unauthenticated requests to /sign-in", %{conn: conn} do
      conn = put(conn, "/session/organization", %{"organization_id" => "org-anything"})

      assert redirected_to(conn) == "/sign-in"
    end
  end
end
