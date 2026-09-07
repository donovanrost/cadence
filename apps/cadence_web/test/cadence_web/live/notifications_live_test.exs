defmodule CadenceWeb.NotificationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated users mount the notifications surface" do
    user = TestFixtures.persist_user!()

    {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/notifications")

    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "organization_admin",
      "surface_id" => "notifications",
      "host_scope" => "user",
      "query_params" => %{},
      "user_id" => user.user_id
    })
  end

  test "unauthenticated requests redirect to /sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/notifications")
  end
end
