defmodule CadenceWeb.CatalogDatabaseShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated mission members mount the catalog database show surface" do
    {conn, mission} = signed_in_org_and_mission()
    database_id = "catalog-database-test"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/databases/#{database_id}")

    assert has_element?(view, "#catalog-database-show-page")

    assert_surface(view, "catalog-database-show-component", "catalog_database_show", mission, %{
      "catalog_database_id" => database_id
    })
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/mission-test/catalog/databases/catalog-database-test")
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}")

    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == ""
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "mission_catalog",
             "surface_id" => surface_id,
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => Map.put(query_params, "mission_id", mission.mission_id)
           }
  end
end
