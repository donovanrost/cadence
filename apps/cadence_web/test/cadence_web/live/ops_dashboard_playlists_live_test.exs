defmodule CadenceWeb.OpsDashboardPlaylistsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Management
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

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

    assert has_element?(present, "#ops-context-rail-component")
    assert has_element?(present, "#dashboard-playlist-present-component.contents")

    initial_vue = LiveVue.Test.get_vue(present, id: "dashboard-playlist-present-component")

    assert initial_vue.component == "OpsDashboardPlaylistPresent"
    assert initial_vue.ssr == false
    assert initial_vue.props == Jason.decode!(Jason.encode!(initial_vue.props))

    assert initial_vue.handlers == %{
             "next-dashboard" => JS.push("next_dashboard")
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
                 "error" => "Dashboard playlist is unavailable: :dashboard_playlist_not_found"
               }
             }}} =
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
                 "error" => "Dashboard playlist is unavailable: :dashboard_playlist_not_found"
               }
             }}} =
             live(
               conn,
               ~p"/missions/#{sibling_mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"
             )
  end

  test "author page creates playlists through the dashboard-author session" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    power = TestFixtures.persist_dashboard_document!(mission, name: "Power")
    thermal = TestFixtures.persist_dashboard_document!(mission, name: "Thermal")

    sibling_mission =
      TestFixtures.persist_mission!(org, slug: "dashboard-playlists-sibling-author")

    sibling_dashboard = TestFixtures.persist_dashboard_document!(sibling_mission, name: "Sibling")

    assert {:ok, sibling_playlist} =
             Management.create_playlist(
               org.organization_id,
               sibling_mission.mission_id,
               %{
                 "name" => "Sibling rotation",
                 "dashboard_ids" => [sibling_dashboard.dashboard_id]
               },
               created_by: user.user_id
             )

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/playlists")

    assert has_element?(view, "#ops-context-rail-component")
    assert has_element?(view, "#dashboard-playlists-component.contents")

    initial_vue = LiveVue.Test.get_vue(view, id: "dashboard-playlists-component")

    assert initial_vue.component == "OpsDashboardPlaylists"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false

    assert initial_vue.handlers == %{
             "create-playlist" => JS.push("create_playlist")
           }

    initial_props = %{
      "page" => %{
        "id" => "dashboard-playlists-page",
        "eyebrow" => "Dashboards / Playlists",
        "heading" => "Operations display rotation",
        "copy" =>
          "Playlists keep ordered dashboard references; the canonical documents and live health remain independent.",
        "list" => %{
          "id" => "dashboard-playlist-list",
          "empty" => %{
            "id" => "dashboard-playlist-empty",
            "copy" => "No playlists yet."
          }
        },
        "form_eyebrow" => "New playlist",
        "present_action" => %{
          "label" => "Present",
          "icon" => "hero-play"
        }
      },
      "form" => %{
        "id" => "dashboard-playlist-form",
        "reset_revision" => 0,
        "name" => %{
          "id" => "playlist_name",
          "name" => "playlist[name]",
          "type" => "text",
          "label" => "Name",
          "value" => "",
          "required" => true
        },
        "description" => %{
          "id" => "playlist_description",
          "name" => "playlist[description]",
          "type" => "textarea",
          "label" => "Description",
          "value" => "",
          "required" => false
        },
        "dashboard_ids" => %{
          "id" => "playlist_dashboard_ids",
          "name" => "playlist[dashboard_ids][]",
          "type" => "select",
          "label" => "Dashboards in order",
          "value" => [],
          "required" => false,
          "multiple" => true
        },
        "dwell_seconds" => %{
          "id" => "playlist_dwell_seconds",
          "name" => "playlist[dwell_seconds]",
          "type" => "number",
          "label" => "Dwell seconds",
          "value" => "30",
          "required" => false,
          "min" => 5,
          "max" => 900
        },
        "wallboard_mode" => %{
          "id" => "playlist_wallboard_mode",
          "name" => "playlist[wallboard_mode]",
          "type" => "checkbox",
          "label" => "Wallboard mode",
          "value" => false,
          "required" => false
        },
        "submit" => %{
          "id" => "dashboard-playlist-create",
          "label" => "Create playlist"
        }
      },
      "options" => [
        %{"label" => "Power", "value" => power.dashboard_id},
        %{"label" => "Thermal", "value" => thermal.dashboard_id}
      ]
    }

    assert initial_vue.props == initial_props
    assert initial_vue.props == Jason.decode!(Jason.encode!(initial_vue.props))
    assert dashboard_playlist_rows(initial_vue) == []

    render_hook(view, "create_playlist", %{
      "playlist" => %{
        "name" => "Rejected rotation",
        "description" => "Wrong mission",
        "dashboard_ids" => [sibling_dashboard.dashboard_id],
        "dwell_seconds" => "15",
        "wallboard_mode" => "on"
      }
    })

    assert Management.list_playlists(org.organization_id, mission.mission_id) == []

    assert has_element?(
             view,
             "#flash-error",
             "Failed to create playlist: :playlist_contains_unknown_dashboard"
           )

    error_vue = LiveVue.Test.get_vue(view, id: "dashboard-playlists-component")
    assert error_vue.props == initial_props
    assert dashboard_playlist_rows(error_vue) == []

    render_hook(view, "create_playlist", %{
      "playlist" => %{
        "name" => "Console rotation",
        "description" => "Primary display",
        "dashboard_ids" => [power.dashboard_id, thermal.dashboard_id],
        "dwell_seconds" => "15",
        "wallboard_mode" => true
      }
    })

    assert [playlist] = Management.list_playlists(org.organization_id, mission.mission_id)
    assert playlist.organization_id == org.organization_id
    assert playlist.mission_id == mission.mission_id
    assert playlist.name == "Console rotation"
    assert playlist.description == "Primary display"
    assert playlist.dashboard_ids == [power.dashboard_id, thermal.dashboard_id]
    assert playlist.dwell_seconds == 15
    assert playlist.wallboard_mode == true
    assert playlist.created_by == user.user_id

    assert [^sibling_playlist] =
             Management.list_playlists(org.organization_id, sibling_mission.mission_id)

    assert has_element?(
             view,
             "#flash-info",
             "Playlist created with dashboard references."
           )

    created_vue = LiveVue.Test.get_vue(view, id: "dashboard-playlists-component")
    created_props = put_in(initial_props, ["form", "reset_revision"], 1)

    assert created_vue.props == created_props
    assert created_vue.props == Jason.decode!(Jason.encode!(created_vue.props))

    assert dashboard_playlist_rows(created_vue) == [
             %{
               "__dom_id" => "dashboard-playlist-#{playlist.dashboard_playlist_id}",
               "dashboard_playlist_id" => playlist.dashboard_playlist_id,
               "name" => "Console rotation",
               "description" => "Primary display",
               "dashboard_ids" => [power.dashboard_id, thermal.dashboard_id],
               "dashboard_count" => 2,
               "dwell_seconds" => 15,
               "wallboard_mode" => true,
               "mode_label" => "wallboard",
               "present" => %{
                 "id" => "dashboard-playlist-present-#{playlist.dashboard_playlist_id}",
                 "href" =>
                   "/missions/#{mission.mission_id}/ops/dashboards/playlists/#{playlist.dashboard_playlist_id}/present"
               }
             }
           ]
  end

  defp dashboard_playlist_rows(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/dashboard_playlists/" <> _index, _playlist] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, playlist] -> playlist end)
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-playlists")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
