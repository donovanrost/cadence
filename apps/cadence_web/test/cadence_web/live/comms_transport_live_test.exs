defmodule CadenceWeb.CommsTransportLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated transport list mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/transports")

    assert_surface(view, "comms-transport-list-page-component", "transports", mission, %{},
      class: "contents"
    )
  end

  test "authenticated transport new mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/new")

    assert_surface(view, "comms-transport-new-component", "transport_new", mission, %{},
      class: "contents"
    )
  end

  test "authenticated transport show forwards only its mission and transport subject" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    transport_id = "transport-test"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/transports/#{transport_id}")

    assert_surface(
      view,
      "comms-transport-show-component",
      "transport",
      mission,
      %{"transport_id" => transport_id}
    )
  end

  test "transport routes redirect unauthenticated users to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, "/missions/mission-test/comms/transports")
  end

  defp assert_surface(view, _id, surface_id, mission, query_params, _opts \\ []) do
    HostTransportTestSupport.assert_context(view, %{
      "application_key" => nil,
      "surface_id" => nil,
      "kind" => "mission_module",
      "contribution" => "comms." <> String.replace(surface_id, "_", "-"),
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
