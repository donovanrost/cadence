defmodule CadenceWeb.OrganizationHomeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated organization members mount the host-owned organization home" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)

    {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/")

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "administration",
        "host_scope" => "organization",
        "organization_id" => organization.organization_id,
        "query_params" => %{}
      })

    assert snapshot["administration_page"]["page"] == "organization_home"
    assert snapshot["administration_page"]["status"] == "ready"

    assert snapshot["administration_page"]["data"]["organization"]["id"] ==
             organization.organization_id
  end

  test "active admin mode redirects to /admin even from /" do
    user =
      TestFixtures.persist_user!(
        email: "elevated-admin-root@example.com",
        capabilities: [:platform_admin]
      )

    token = TestFixtures.member_session_token!(user)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        user_session_token: token,
        admin_mode_expires_at: CadenceWeb.AdminMode.expires_at()
      })

    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/")
  end
end
