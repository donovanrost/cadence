defmodule CadenceWeb.CommsProviderLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated provider list mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers")

    assert_surface(view, "comms-provider-list-component", "provider_list", mission, %{},
      class: "contents"
    )
  end

  test "authenticated provider new mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/new")

    assert_surface(view, "comms-provider-new-component", "provider_new", mission, %{},
      class: "max-w-3xl space-y-6"
    )
  end

  test "authenticated provider show forwards its bounded subject" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    provider_id = "provider-test"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/providers/#{provider_id}")

    assert_surface(
      view,
      "comms-provider-show-component",
      "provider_show",
      mission,
      %{"provider_id" => provider_id},
      class: "contents"
    )
  end

  test "provider routes redirect unauthenticated users to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, "/missions/mission-test/comms/providers/provider-test")
  end

  defp assert_surface(view, id, surface_id, mission, query_params, opts) do
    assert has_element?(view, "##{id}")

    vue = Test.get_vue(view, id: id)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.ssr == false
    assert vue.handlers == %{}

    if class = Keyword.get(opts, :class) do
      assert vue.class == class
    end

    assert vue.props == %{
             "application_key" => "comms",
             "surface_id" => surface_id,
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params
           }
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    {TestFixtures.member_conn(user), organization, mission}
  end
end
