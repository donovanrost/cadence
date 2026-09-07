defmodule CadenceWeb.CommsRoutingLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated routing list mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing")

    assert_surface(view, "comms-routing-list-page-component", "routing", mission, %{},
      class: "contents"
    )
  end

  test "authenticated routing new mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/new")

    assert_surface(view, "comms-routing-new-component", "routing_new", mission, %{},
      class: "space-y-6 max-w-2xl"
    )
  end

  test "authenticated routing show forwards its bounded subject" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    routing_rule_id = "routing-rule-test"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/#{routing_rule_id}")

    assert_surface(
      view,
      "comms-routing-show-component",
      "routing_detail",
      mission,
      %{"routing_rule_id" => routing_rule_id}
    )
  end

  test "authenticated spacecraft routing mounts its spacecraft-scoped surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
      )

    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "spacecraft",
      "surface_id" => "routing",
      "host_scope" => "spacecraft",
      "mission_id" => mission.mission_id,
      "spacecraft_id" => spacecraft.spacecraft_id,
      "query_params" => %{}
    })
  end

  test "routing routes redirect unauthenticated users to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, "/missions/mission-test/comms/routing")
  end

  defp assert_surface(view, _id, surface_id, mission, query_params, _opts \\ []) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => "comms",
      "surface_id" => surface_id,
      "host_scope" => "mission",
      "mission_id" => mission.mission_id,
      "query_params" => query_params
    })
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    {TestFixtures.member_conn(user), organization, mission}
  end
end
