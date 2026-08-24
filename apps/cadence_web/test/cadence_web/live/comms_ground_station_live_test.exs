defmodule CadenceWeb.CommsGroundStationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.GroundStationStore

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
    test "renders the empty state when the mission has no ground stations" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations")

      assert has_element?(view, "#comms-ground-stations-page", "No ground stations")
      assert has_element?(view, "#new-ground-station-link")
      refute has_element?(view, "#ground-stations-list-component")
    end

    test "lists and shows configured ground stations" do
      {conn, org, mission} = signed_in_org_and_mission()
      ground_station = persist_ground_station!(org.organization_id, mission.mission_id)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations")

      assert has_element?(view, "#comms-ground-stations-page")
      assert has_element?(view, "#new-ground-station-link")
      assert has_element?(view, "#ground-stations-list-component")
      assert has_element?(view, "details[open] a", "Ground Stations")
      assert has_element?(view, "#comms-ground-stations-page", "Mission-owned antenna")

      vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")

      assert vue.component == "CommsGroundStationList"

      assert vue.props == %{
               "rows" => [
                 %{
                   "id" => "ground-station-#{ground_station.ground_station_id}",
                   "display_name" => ground_station.display_name,
                   "provider" => "DSN",
                   "region" => "goldstone",
                   "ground_station_id" => ground_station.ground_station_id,
                   "href" =>
                     "/missions/#{mission.mission_id}/comms/ground-stations/#{ground_station.ground_station_id}"
                 }
               ],
               "search" => nil,
               "sort" => "display_name",
               "sort_dir" => "asc",
               "page" => 1,
               "page_size" => 50,
               "total_count" => 1
             }

      render_hook(view, "search", %{"q" => "goldstone"})

      assert_patch(
        view,
        "/missions/#{mission.mission_id}/comms/ground-stations?q=goldstone"
      )

      searched_vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")
      assert searched_vue.props["search"] == "goldstone"
      assert searched_vue.props["rows"] == vue.props["rows"]

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

    test "searches and sorts through LiveView-owned list events" do
      {conn, org, mission} = signed_in_org_and_mission()

      alpha =
        persist_ground_station!(org.organization_id, mission.mission_id,
          ground_station_id: "alpha",
          display_name: "Alpha Station",
          provider: nil,
          region: nil
        )

      zulu =
        persist_ground_station!(org.organization_id, mission.mission_id,
          ground_station_id: "zulu",
          display_name: "Zulu Station"
        )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations")

      vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")
      alpha_row = Enum.find(vue.props["rows"], &(&1["ground_station_id"] == "alpha"))

      assert Enum.map(vue.props["rows"], & &1["ground_station_id"]) == [
               alpha.ground_station_id,
               zulu.ground_station_id
             ]

      assert alpha_row["provider"] == "UNSPECIFIED"
      assert alpha_row["region"] == "none"

      render_hook(view, "sort", %{"sort" => "display_name"})

      assert_patch(
        view,
        "/missions/#{mission.mission_id}/comms/ground-stations?sort=display_name&dir=desc"
      )

      sorted_vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")
      assert sorted_vue.props["sort_dir"] == "desc"

      assert Enum.map(sorted_vue.props["rows"], & &1["ground_station_id"]) == [
               zulu.ground_station_id,
               alpha.ground_station_id
             ]

      render_hook(view, "search", %{"q" => "alpha"})

      assert_patch(
        view,
        "/missions/#{mission.mission_id}/comms/ground-stations?q=alpha&sort=display_name&dir=desc"
      )

      searched_vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")
      assert searched_vue.props["search"] == "alpha"
      assert searched_vue.props["total_count"] == 1
      assert searched_vue.props["rows"] == [alpha_row]

      render_hook(view, "search", %{"q" => "no-such-station"})

      assert_patch(
        view,
        "/missions/#{mission.mission_id}/comms/ground-stations?q=no-such-station&sort=display_name&dir=desc"
      )

      no_matches_vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")
      assert no_matches_vue.props["search"] == "no-such-station"
      assert no_matches_vue.props["total_count"] == 0
      assert no_matches_vue.props["rows"] == []
    end

    test "paginates through the LiveView event and keeps visible rows in props" do
      {conn, org, mission} = signed_in_org_and_mission()

      for station_number <- 1..51 do
        suffix = station_number |> Integer.to_string() |> String.pad_leading(2, "0")

        persist_ground_station!(org.organization_id, mission.mission_id,
          ground_station_id: "station-#{suffix}",
          display_name: "Station #{suffix}"
        )
      end

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/ground-stations")

      first_page_vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")
      assert first_page_vue.props["page"] == 1
      assert first_page_vue.props["total_count"] == 51
      assert length(first_page_vue.props["rows"]) == 50

      render_hook(view, "paginate", %{"page" => "2"})

      assert_patch(
        view,
        "/missions/#{mission.mission_id}/comms/ground-stations?page=2"
      )

      second_page_vue = LiveVue.Test.get_vue(view, id: "ground-stations-list-component")
      assert second_page_vue.props["page"] == 2
      assert second_page_vue.props["total_count"] == 51
      assert Enum.map(second_page_vue.props["rows"], & &1["ground_station_id"]) == ["station-51"]
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
               GroundStationStore.fetch_ground_station(
                 org.organization_id,
                 mission.mission_id,
                 "dss-25"
               )

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
               GroundStationStore.fetch_ground_station(
                 org.organization_id,
                 mission.mission_id,
                 "dss-25"
               )

      assert updated.display_name == "Goldstone DSS-25 Prime"
      assert updated.region == "california"
      assert updated.metadata["azimuth_drive"] == "upgraded"

      {:ok, show_view, _show_html} = live(conn, show_path)

      assert {:error, {:live_redirect, %{to: list_path}}} =
               show_view
               |> element("#archive-ground-station-button")
               |> render_click()

      assert list_path == "/missions/#{mission.mission_id}/comms/ground-stations"

      assert [] =
               GroundStationStore.list_ground_stations(
                 org.organization_id,
                 mission.mission_id
               )
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

      assert [] =
               GroundStationStore.list_ground_stations(
                 org.organization_id,
                 mission.mission_id
               )
    end
  end

  defp persist_ground_station!(organization_id, mission_id, attributes \\ []) do
    attributes =
      Map.merge(
        %{
          mission_id: mission_id,
          ground_station_id: "dss-14",
          display_name: "Goldstone DSS-14",
          provider: "DSN",
          region: "goldstone",
          metadata: %{"antenna_diameter_m" => 70}
        },
        Map.new(attributes)
      )

    ground_station =
      GroundStation.new(attributes)

    assert {:ok, persisted} =
             GroundStationStore.persist_ground_station(
               organization_id,
               ground_station
             )

    persisted
  end
end
