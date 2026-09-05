defmodule CadenceWeb.MissionNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated organization members mount the mission new surface" do
    {conn, organization} = signed_in_org()

    {:ok, view, _html} = live(conn, ~p"/missions/new")

    assert has_element?(view, "#mission-new-component.space-y-6.max-w-xl")

    vue = Test.get_vue(view, id: "mission-new-component")

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "mission-new-component"
    assert vue.class == "space-y-6 max-w-xl"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "mission_catalog",
             "surface_id" => "mission_new",
             "host_scope" => "organization",
             "organization_id" => organization.organization_id,
             "query_params" => %{}
           }
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/missions/new")
  end

  defp signed_in_org do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    {TestFixtures.member_conn(user), organization}
  end
end
