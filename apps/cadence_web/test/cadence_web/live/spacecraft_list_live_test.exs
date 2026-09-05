defmodule CadenceWeb.SpacecraftListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated list route mounts the federated mission surface" do
    {conn, mission} = signed_in_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

    assert_surface(view, mission, %{})
  end

  test "list forwards only its bounded query parameters" do
    {conn, mission} = signed_in_mission()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft?q=Bravo&sort=scid&dir=desc&page=2&pageSize=25&filter=missing_scid&ignored=drop"
      )

    assert_surface(view, mission, %{
      "q" => "Bravo",
      "sort" => "scid",
      "dir" => "desc",
      "page" => "2",
      "pageSize" => "25",
      "filter" => "missing_scid"
    })
  end

  test "unauthenticated list requests redirect to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), "/missions/mission-test/spacecraft")
  end

  defp assert_surface(view, mission, query_params) do
    assert has_element?(view, "#spacecraft-list-component.contents")

    vue = Test.get_vue(view, id: "spacecraft-list-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == "spacecraft-list-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "spacecraft",
             "surface_id" => "list",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params
           }
  end

  defp signed_in_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end
end
