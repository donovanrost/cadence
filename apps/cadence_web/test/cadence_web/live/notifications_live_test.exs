defmodule CadenceWeb.NotificationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated users mount the notifications surface" do
    user = TestFixtures.persist_user!()

    {:ok, view, _html} = live(TestFixtures.member_conn(user), ~p"/notifications")

    assert has_element?(view, "#notifications-page-component.contents")
    vue = Test.get_vue(view, id: "notifications-page-component")

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "notifications-page-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "organization_admin",
             "surface_id" => "notifications",
             "host_scope" => "user",
             "user_id" => user.user_id
           }
  end

  test "unauthenticated requests redirect to /sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/notifications")
  end
end
