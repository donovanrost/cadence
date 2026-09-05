defmodule CadenceWeb.CatalogArtifactShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated mission members mount the catalog artifact show surface" do
    {conn, mission} = signed_in_org_and_mission()
    artifact_id = "catalog-artifact-test"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact_id}")

    assert_surface(
      view,
      "catalog-artifact-show-page-component",
      "catalog_artifact_show",
      mission,
      %{
        "artifact_id" => artifact_id
      }
    )
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/mission-test/catalog/artifacts/catalog-artifact-test")
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")

    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
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
