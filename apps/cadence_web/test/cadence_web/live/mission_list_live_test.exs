defmodule CadenceWeb.MissionListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated organization members mount the mission list surface" do
    {conn, organization} = signed_in_org()

    {:ok, view, _html} = live(conn, ~p"/missions")

    assert has_element?(view, "#mission-list-component")

    vue = Test.get_vue(view, id: "mission-list-component")

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "mission-list-component"
    assert vue.class == ""
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "mission_catalog",
             "surface_id" => "mission_list",
             "host_scope" => "organization",
             "organization_id" => organization.organization_id,
             "query_params" => %{"organization_id" => organization.organization_id}
           }
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/missions")
  end

  defp signed_in_org do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    {TestFixtures.member_conn(user), organization}
  end
end
