defmodule CadenceWeb.CommsGroundStationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "authenticated ground-station list mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations")

    assert_surface(
      view,
      "comms-ground-station-list-page-component",
      "ground_stations",
      mission,
      %{},
      class: "contents"
    )
  end

  test "authenticated ground-station new mounts the federated mission surface" do
    {conn, _organization, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations/new")

    assert_surface(
      view,
      "comms-ground-station-form-component",
      "ground_station_new",
      mission,
      %{}
    )
  end

  test "authenticated ground-station edit forwards its bounded subject" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    ground_station_id = "ground-station-test"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{ground_station_id}/edit"
      )

    assert_surface(
      view,
      "comms-ground-station-form-component",
      "ground_station_edit",
      mission,
      %{"ground_station_id" => ground_station_id}
    )
  end

  test "authenticated ground-station show forwards its bounded subject" do
    {conn, _organization, mission} = signed_in_org_and_mission()
    ground_station_id = "ground-station-test"

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{ground_station_id}")

    assert_surface(
      view,
      "comms-ground-station-show-component",
      "ground_station",
      mission,
      %{"ground_station_id" => ground_station_id}
    )
  end

  test "ground-station routes redirect unauthenticated users to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, "/missions/mission-test/comms/ground-stations")
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
