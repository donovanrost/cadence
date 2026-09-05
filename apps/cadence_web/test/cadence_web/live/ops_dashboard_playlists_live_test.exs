defmodule CadenceWeb.OpsDashboardPlaylistsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Management
  alias CadenceWeb.TestFixtures

  test "playlist presentation mounts with the authenticated playlist subject" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Wallboard")

    assert {:ok, playlist} =
             Management.create_playlist(
               org.organization_id,
               mission.mission_id,
               %{"name" => "Flight wallboard", "dashboard_ids" => [dashboard.dashboard_id]},
               created_by: user.user_id
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"
      )

    assert_surface(
      view,
      "dashboard-playlist-present-component",
      "dashboard_playlist_present",
      mission,
      %{"playlist_id" => playlist.dashboard_playlist_id}
    )
  end

  test "playlist authoring mounts the mission-scoped surface" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists")

    assert_surface(view, "dashboard-playlists-component", "dashboard_playlists", mission, %{})
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-playlists")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
