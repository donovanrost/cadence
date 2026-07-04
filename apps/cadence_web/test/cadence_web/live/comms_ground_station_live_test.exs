defmodule CadenceWeb.CommsGroundStationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.GroundStation
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "ground station routes" do
    test "lists and shows configured ground stations" do
      {conn, org, mission} = signed_in_org_and_mission()
      ground_station = persist_ground_station!(org.organization_id, mission.mission_id)

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations")

      assert has_element?(view, "#comms-ground-stations-page")
      assert has_element?(view, "#new-ground-station-link")
      assert has_element?(view, "#ground-stations[phx-update='stream']")
      assert has_element?(view, "td", ground_station.display_name)
      assert has_element?(view, "details[open] a", "Ground Stations")
      assert html =~ "Mission-owned antenna"

      html =
        view
        |> element("#ground-stations-toolbar form")
        |> render_change(%{"q" => "goldstone"})

      assert html =~ "Goldstone DSS-14"

      {:ok, show_view, show_html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/ground-stations/#{ground_station.ground_station_id}"
        )

      assert has_element?(show_view, "#comms-ground-station-show-page")
      assert has_element?(show_view, "#edit-ground-station-link")
      assert has_element?(show_view, "#archive-ground-station-button")
      assert show_html =~ "Ground Station"
      assert show_html =~ "DSN"
      assert show_html =~ "Runtime contact and RF state are observed separately."
    end

    test "creates, edits, and archives ground stations" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations/new")

      assert has_element?(view, "#comms-ground-station-form-page")
      assert has_element?(view, "#ground-station-form")
      assert html =~ "New Ground Station"

      assert {:error, {:live_redirect, %{to: show_path}}} =
               view
               |> form("#ground-station-form",
                 ground_station: %{
                   ground_station_id: "dss-25",
                   display_name: "Goldstone DSS-25",
                   provider: "DSN",
                   region: "goldstone",
                   metadata_json: ~s({"antenna_diameter_m":34})
                 }
               )
               |> render_submit()

      assert show_path ==
               "/missions/#{mission.mission_id}/comms/ground-stations/dss-25"

      assert {:ok, persisted} =
               Cadence.fetch_ground_station(org.organization_id, mission.mission_id, "dss-25")

      assert persisted.display_name == "Goldstone DSS-25"
      assert persisted.metadata["antenna_diameter_m"] == 34

      {:ok, edit_view, edit_html} = live(conn, "#{show_path}/edit")

      assert has_element?(edit_view, "#ground-station-form")
      assert edit_html =~ "Edit Ground Station"

      assert {:error, {:live_redirect, %{to: ^show_path}}} =
               edit_view
               |> form("#ground-station-form",
                 ground_station: %{
                   display_name: "Goldstone DSS-25 Prime",
                   provider: "DSN",
                   region: "california",
                   metadata_json: ~s({"antenna_diameter_m":34,"azimuth_drive":"upgraded"})
                 }
               )
               |> render_submit()

      assert {:ok, updated} =
               Cadence.fetch_ground_station(org.organization_id, mission.mission_id, "dss-25")

      assert updated.display_name == "Goldstone DSS-25 Prime"
      assert updated.region == "california"
      assert updated.metadata["azimuth_drive"] == "upgraded"

      {:ok, show_view, _show_html} = live(conn, show_path)

      assert {:error, {:live_redirect, %{to: list_path}}} =
               show_view
               |> element("#archive-ground-station-button")
               |> render_click()

      assert list_path == "/missions/#{mission.mission_id}/comms/ground-stations"
      assert [] = Cadence.list_ground_stations(org.organization_id, mission.mission_id)
    end

    test "rejects invalid metadata JSON" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations/new")

      html =
        view
        |> form("#ground-station-form",
          ground_station: %{
            ground_station_id: "dss-26",
            display_name: "Goldstone DSS-26",
            provider: "DSN",
            region: "goldstone",
            metadata_json: "not json"
          }
        )
        |> render_submit()

      assert html =~ "Metadata JSON must be an object."
      assert [] = Cadence.list_ground_stations(org.organization_id, mission.mission_id)
    end

    test "unauthenticated requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/comms/ground-stations")
    end
  end

  defp persist_ground_station!(organization_id, mission_id) do
    ground_station =
      GroundStation.new(%{
        mission_id: mission_id,
        ground_station_id: "dss-14",
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "goldstone",
        metadata: %{"antenna_diameter_m" => 70}
      })

    assert {:ok, persisted} = Cadence.persist_ground_station(organization_id, ground_station)
    persisted
  end
end
