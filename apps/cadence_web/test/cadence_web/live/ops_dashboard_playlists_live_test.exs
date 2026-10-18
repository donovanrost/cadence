defmodule CadenceWeb.OpsDashboardPlaylistsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "playlist routes forward only their bounded subject" do
    {conn, mission} = signed_in()

    {:ok, present, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists/playlist-1/present")

    assert_surface(
      present,
      "dashboard-playlist-present-component",
      "dashboard_playlist_present",
      mission,
      %{
        "playlist_id" => "playlist-1"
      }
    )

    {:ok, index, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists")
    assert_surface(index, "dashboard-playlists-component", "dashboard_playlists", mission, %{})
  end

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    page = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]
    assert page["slot"] == "ops.page"
    assert page["context"]["missionId"] == mission.mission_id

    if surface_id == "dashboard_playlist_present" do
      assert page["id"] == "dashboards.playlist-present"
      assert page["context"]["resourceId"] == query_params["playlist_id"]
      assert page["status"] == "unavailable"
    else
      assert page["id"] == "dashboards.playlists"
      assert page["status"] == "ready"
    end
  end
end
