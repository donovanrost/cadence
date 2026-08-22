defmodule CadenceWeb.OpsDashboardPlaylistsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Management
  alias CadenceWeb.TestFixtures

  test "playlist stores ordered dashboard references and presents without hiding health posture" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    power = TestFixtures.persist_dashboard_document!(mission, name: "Power")
    thermal = TestFixtures.persist_dashboard_document!(mission, name: "Thermal")

    assert {:ok, playlist} =
             Management.create_playlist(
               org.organization_id,
               mission.mission_id,
               %{
                 "name" => "Flight wallboard",
                 "dashboard_ids" => [power.dashboard_id, thermal.dashboard_id],
                 "dwell_seconds" => 30,
                 "wallboard_mode" => true
               },
               created_by: user.user_id
             )

    assert playlist.dashboard_ids == [power.dashboard_id, thermal.dashboard_id]
    refute Map.has_key?(Map.from_struct(playlist), :documents)

    {:ok, present, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"
      )

    assert has_element?(present, "#ops-context-rail")
    assert has_element?(present, ~s(#dashboard-playlist-present-page[data-wallboard-mode="true"]))

    assert has_element?(
             present,
             ~s(#dashboard-playlist-freshness-signal[data-freshness-visible="true"])
           )

    assert has_element?(
             present,
             ~s(#dashboard-playlist-frame[data-dashboard-id="#{power.dashboard_id}"])
           )

    present |> element("#dashboard-playlist-next") |> render_click()

    assert_patch(
      present,
      ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present?index=1"
    )

    assert has_element?(
             present,
             ~s(#dashboard-playlist-frame[data-dashboard-id="#{thermal.dashboard_id}"])
           )
  end

  test "author page creates playlists through the dashboard-author session" do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    power = TestFixtures.persist_dashboard_document!(mission, name: "Power")

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists")

    assert has_element?(view, "#ops-context-rail")

    view
    |> form("#dashboard-playlist-form",
      playlist: %{
        name: "Console rotation",
        description: "Primary display",
        dashboard_ids: [power.dashboard_id],
        dwell_seconds: "15",
        wallboard_mode: "true"
      }
    )
    |> render_submit()

    assert [playlist] = Management.list_playlists(org.organization_id, mission.mission_id)
    assert has_element?(view, "#dashboard-playlist-#{playlist.dashboard_playlist_id}")
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-playlists")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
