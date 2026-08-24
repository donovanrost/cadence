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

    present_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"

    {:ok, present, _html} = live(conn, present_path)

    assert has_element?(present, "#ops-context-rail")
    assert has_element?(present, "#dashboard-playlist-present-component.contents")

    initial_vue = LiveVue.Test.get_vue(present, id: "dashboard-playlist-present-component")

    assert initial_vue.component == "OpsDashboardPlaylistPresent"
    assert initial_vue.ssr == false
    assert initial_vue.props == Jason.decode!(Jason.encode!(initial_vue.props))
    assert initial_vue.handlers == %{
             "next-dashboard" => Phoenix.LiveView.JS.push("next_dashboard")
           }

    initial_props = %{
      "page" => %{
        "id" => "dashboard-playlist-present-page",
        "wallboard_mode" => true,
        "mode_label" => "Wallboard",
        "playlist_name" => "Flight wallboard",
        "freshness_signal" => %{
          "id" => "dashboard-playlist-freshness-signal",
          "visible" => true,
          "icon" => "hero-signal",
          "copy" =>
            "Live freshness, stale, partial, disconnected, and unsupported states remain visible in the canvas and context rail."
        },
        "position" => %{
          "id" => "dashboard-playlist-position",
          "current" => 1,
          "total" => 2
        },
        "next_action" => %{
          "id" => "dashboard-playlist-next",
          "label" => "Next"
        },
        "unavailable" => %{
          "id" => "dashboard-playlist-unavailable",
          "state" => "unsupported",
          "icon" => "hero-exclamation-triangle",
          "title" => "Referenced dashboard is unavailable",
          "copy" =>
            "The playlist reference is preserved, but presentation cannot silently skip or mask a missing or archived dashboard."
        }
      },
      "current_dashboard" => %{
        "dashboard_id" => power.dashboard_id,
        "name" => "Power",
        "available" => true,
        "path" =>
          "/missions/#{mission.mission_id}/ops/dashboards/#{power.dashboard_id}?presentation=playlist",
        "frame_id" => "dashboard-playlist-frame"
      }
    }

    assert initial_vue.props == initial_props

    # One-to-one preservation of the original presentation assertions now carried by Vue props.
    assert initial_vue.props["page"]["id"] == "dashboard-playlist-present-page"
    assert initial_vue.props["page"]["wallboard_mode"] == true

    assert initial_vue.props["page"]["freshness_signal"]["id"] ==
             "dashboard-playlist-freshness-signal"

    assert initial_vue.props["page"]["freshness_signal"]["visible"] == true
    assert initial_vue.props["current_dashboard"]["frame_id"] == "dashboard-playlist-frame"
    assert initial_vue.props["current_dashboard"]["dashboard_id"] == power.dashboard_id

    render_hook(present, "next_dashboard", %{})

    assert_patch(present, present_path <> "?index=1")
    render_patch(present, present_path <> "?index=1")

    rotated_vue = LiveVue.Test.get_vue(present, id: "dashboard-playlist-present-component")

    rotated_props =
      initial_props
      |> put_in(["page", "position", "current"], 2)
      |> put_in(["current_dashboard"], %{
        "dashboard_id" => thermal.dashboard_id,
        "name" => "Thermal",
        "available" => true,
        "path" =>
          "/missions/#{mission.mission_id}/ops/dashboards/#{thermal.dashboard_id}?presentation=playlist",
        "frame_id" => "dashboard-playlist-frame"
      })

    assert rotated_vue.props == rotated_props
    assert rotated_vue.props == Jason.decode!(Jason.encode!(rotated_vue.props))
    assert rotated_vue.props["current_dashboard"]["frame_id"] == "dashboard-playlist-frame"
    assert rotated_vue.props["current_dashboard"]["dashboard_id"] == thermal.dashboard_id

    send(present.pid, :rotate_playlist)
    assert_patch(present, present_path <> "?index=0")
    render_patch(present, present_path <> "?index=0")

    timer_rotated_vue = LiveVue.Test.get_vue(present, id: "dashboard-playlist-present-component")

    assert timer_rotated_vue.props == initial_props

    assert :ok =
             Cadence.Dashboards.archive_document(
               org.organization_id,
               mission.mission_id,
               thermal.dashboard_id,
               expected_version: 1,
               actor_id: user.user_id
             )

    render_patch(present, present_path <> "?index=3")

    unavailable_vue = LiveVue.Test.get_vue(present, id: "dashboard-playlist-present-component")

    unavailable_props =
      rotated_props
      |> put_in(["current_dashboard"], %{
        "dashboard_id" => thermal.dashboard_id,
        "name" => "Unavailable dashboard",
        "available" => false,
        "path" =>
          "/missions/#{mission.mission_id}/ops/dashboards/#{thermal.dashboard_id}?presentation=playlist",
        "frame_id" => "dashboard-playlist-frame"
      })

    assert unavailable_vue.props == unavailable_props
    assert unavailable_vue.props["page"]["position"] == %{
             "id" => "dashboard-playlist-position",
             "current" => 2,
             "total" => 2
           }

    assert unavailable_vue.props["page"]["unavailable"] == %{
             "id" => "dashboard-playlist-unavailable",
             "state" => "unsupported",
             "icon" => "hero-exclamation-triangle",
             "title" => "Referenced dashboard is unavailable",
             "copy" =>
               "The playlist reference is preserved, but presentation cannot silently skip or mask a missing or archived dashboard."
           }

    dashboard_list_path = ~p"/missions/#{mission.mission_id}/ops/dashboards"

    assert {:error,
            {:live_redirect,
             %{
               to: ^dashboard_list_path,
               flash: %{
                 "error" =>
                   "Dashboard playlist is unavailable: :dashboard_playlist_not_found"
               }
             }}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists/missing-dashboard-playlist/present"
             )

    sibling_mission = TestFixtures.persist_mission!(org, slug: "dashboard-playlists-sibling")
    sibling_dashboard_list_path = ~p"/missions/#{sibling_mission.mission_id}/ops/dashboards"

    assert {:error,
            {:live_redirect,
             %{
               to: ^sibling_dashboard_list_path,
               flash: %{
                 "error" =>
                   "Dashboard playlist is unavailable: :dashboard_playlist_not_found"
               }
             }}}} =
             live(
               conn,
               ~p"/missions/#{sibling_mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"
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
