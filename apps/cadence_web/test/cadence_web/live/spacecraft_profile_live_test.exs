defmodule CadenceWeb.SpacecraftProfileLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp spacecraft_profile_list_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-profiles-list-component")

    assert vue.component == "SpacecraftTypeList"
    assert vue.ssr == false
    assert is_binary(Jason.encode!(vue.props))

    vue
  end

  defp spacecraft_profile_show_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-profile-show-component")

    assert vue.component == "SpacecraftTypeShow"
    assert vue.ssr == false
    assert is_binary(Jason.encode!(vue.props))

    vue
  end

  describe "profile routes" do
    test "spacecraft management page exposes vehicle and profile cards with scoped actions" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Aurora-1", scid: 42)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert has_element?(view, "#spacecraft-management-page")
      assert has_element?(view, "#spacecraft-list-component")

      vue = LiveVue.Test.get_vue(view, id: "spacecraft-list-component")
      assert vue.component == "SpacecraftList"

      assert vue.props["roster"]["new_spacecraft_href"] ==
               "/missions/#{mission.mission_id}/spacecraft/new"

      assert vue.props["profiles"]["new_profile_href"] ==
               "/missions/#{mission.mission_id}/spacecraft/profiles/new"

      assert Enum.any?(
               vue.props["roster"]["rows"],
               &(&1["id"] == "spacecraft-#{spacecraft.spacecraft_id}" and
                   &1["display_name"] == spacecraft.display_name)
             )

      assert Enum.any?(
               vue.props["profiles"]["rows"],
               &(&1["id"] == "spacecraft-profile-preview-#{profile.spacecraft_type_id}" and
                   &1["display_name"] == profile.display_name)
             )

      page_header =
        view
        |> element("#spacecraft-management-page > header:first-child")
        |> render()

      refute page_header =~ "New spacecraft"
      refute page_header =~ "New profile"
    end

    test "mission sidebar keeps profiles under the spacecraft area" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      refute has_element?(
               view,
               "nav a[href='/missions/#{mission.mission_id}/spacecraft/profiles']",
               "Spacecraft Profiles"
             )

      assert has_element?(
               view,
               "nav a[href='/missions/#{mission.mission_id}/spacecraft']",
               "Spacecraft"
             )
    end

    test "renders the server-owned empty state when no profiles are defined" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

      assert has_element?(view, "#spacecraft-profiles-page", "No profiles yet")

      assert has_element?(
               view,
               "#new-spacecraft-profile-link[href='/missions/#{mission.mission_id}/spacecraft/profiles/new']"
             )

      refute has_element?(view, "#spacecraft-profiles-list-component")
    end

    test "lists spacecraft profiles using profile vocabulary and JSON-safe row props" do
      {conn, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Aurora Bus",
          downlink_protocol: :aos,
          uplink_protocol: :uslp,
          applications: %{
            "telemetry_decom" => %{},
            "command_dispatch" => %{}
          }
        )

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

      assert has_element?(
               view,
               "#new-spacecraft-profile-link[href='/missions/#{mission.mission_id}/spacecraft/profiles/new']"
             )

      assert has_element?(view, "#spacecraft-profiles-list-component")
      assert has_element?(view, "#spacecraft-profiles-page", "1 defined")

      vue = spacecraft_profile_list_vue(view)

      assert vue.props == %{
               "rows" => [
                 %{
                   "id" => "spacecraft-profile-#{profile.spacecraft_type_id}",
                   "display_name" => profile.display_name,
                   "version" => "v1",
                   "downlink_protocol" => "AOS",
                   "uplink_protocol" => "USLP",
                   "applications" => "Command Dispatch, Telemetry Decom",
                   "href" =>
                     "/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
                 }
               ]
             }

      assert has_element?(view, "#spacecraft-profiles-page", "Spacecraft Profiles")
      refute has_element?(view, "#spacecraft-profiles-page", "Spacecraft Types")
    end

    test "lists only profiles belonging to the current mission and organization" do
      {conn, org, mission} = signed_in_org_and_mission()
      mine = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Mine")

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      same_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_mission, display_name: "Same Org Foreign")

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_org_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      other_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_org_mission,
          display_name: "Other Org Foreign"
        )

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

      rows = spacecraft_profile_list_vue(view).props["rows"]

      assert Enum.map(rows, & &1["id"]) == ["spacecraft-profile-#{mine.spacecraft_type_id}"]

      refute Enum.any?(
               rows,
               &(&1["id"] == "spacecraft-profile-#{same_org_foreign.spacecraft_type_id}")
             )

      refute Enum.any?(
               rows,
               &(&1["id"] == "spacecraft-profile-#{other_org_foreign.spacecraft_type_id}")
             )
    end

    test "creates a spacecraft profile and redirects to the profile show page" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles/new")

      assert has_element?(view, "#spacecraft-profile-new-page")
      assert has_element?(view, "#spacecraft-profile-form")
      assert has_element?(view, "#spacecraft-profile-application-telemetry_decom")
      refute has_element?(view, "#spacecraft-profile-application-cfdp")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#spacecraft-profile-form",
                 spacecraft_type: %{
                   display_name: "Lab TM/TC",
                   downlink_protocol: "tm",
                   uplink_protocol: "tc",
                   frame_size: "1024",
                   secondary_header_length: "0",
                   ocf_length: "0",
                   applications: %{"telemetry_decom" => "1"}
                 }
               )
               |> render_submit()

      assert target =~ "/missions/#{mission.mission_id}/spacecraft/profiles/"

      [persisted] =
        Cadence.SpacecraftTypeStore.list_spacecraft_types(org.organization_id, mission.mission_id)

      assert persisted.display_name == "Lab TM/TC"
      assert target =~ persisted.spacecraft_type_id
    end

    test "shows a spacecraft profile" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
        )

      assert has_element?(view, "#spacecraft-profile-show-page")
      assert has_element?(view, "#spacecraft-profile-show-component")

      vue = spacecraft_profile_show_vue(view)

      assert vue.props["navigation"]["profiles"]["href"] ==
               "/missions/#{mission.mission_id}/spacecraft/profiles"

      assert vue.props["profile"]["display_name"] == "Aurora Bus"
      assert vue.props["labels"]["byte_interpretation"] == "Byte Interpretation"
      refute inspect(vue.props) =~ "Spacecraft Type"
    end

    test "provides exact JSON-safe profile detail and version history props" do
      {conn, org, mission} = signed_in_org_and_mission()

      profile_v1 =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Aurora Bus",
          downlink_protocol: :aos,
          uplink_protocol: :tc,
          frame_parameters: %{"frame_size" => 1024, "ocf_length" => 0},
          applications: %{"telemetry_decom" => %{}}
        )

      profile_v2 = %Cadence.SpacecraftType{
        profile_v1
        | version: 2,
          downlink_protocol: :uslp,
          uplink_protocol: :uslp,
          frame_parameters: %{
            "frame_size" => 2048,
            "ocf_length" => 0,
            "secondary_header_enabled" => true,
            "truncated_primary_header" => false
          },
          applications: %{
            "command_dispatch" => %{},
            "telemetry_decom" => %{}
          }
      }

      assert {:ok, persisted_v2} =
               Cadence.SpacecraftTypeStore.persist_spacecraft_type(
                 org.organization_id,
                 profile_v2
               )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile_v1.spacecraft_type_id}"
        )

      vue = spacecraft_profile_show_vue(view)

      assert vue.props == %{
               "labels" => %{
                 "applications" => "Applications",
                 "byte_interpretation" => "Byte Interpretation",
                 "downlink" => "Downlink",
                 "downlink_protocol" => "Downlink Protocol",
                 "frame_parameters" => "Frame Parameters",
                 "lifecycle" => "Lifecycle",
                 "no_applications" => "No applications enabled.",
                 "packet_protocol" => "Packet Protocol",
                 "uplink" => "Uplink",
                 "uplink_protocol" => "Uplink Protocol",
                 "version" => "Version",
                 "version_history" => "Version History"
               },
               "navigation" => %{
                 "current" => %{"label" => "Aurora Bus"},
                 "mission" => %{
                   "href" => "/missions/#{mission.mission_id}",
                   "label" => "Primary Mission"
                 },
                 "profiles" => %{
                   "href" => "/missions/#{mission.mission_id}/spacecraft/profiles",
                   "label" => "Spacecraft Profiles"
                 },
                 "spacecraft" => %{
                   "href" => "/missions/#{mission.mission_id}/spacecraft",
                   "label" => "Spacecraft"
                 }
               },
               "profile" => %{
                 "applications" => [
                   %{
                     "id" => "spacecraft-profile-application-command_dispatch",
                     "label" => "Command Dispatch"
                   },
                   %{
                     "id" => "spacecraft-profile-application-telemetry_decom",
                     "label" => "Telemetry Decom"
                   }
                 ],
                 "display_name" => "Aurora Bus",
                 "downlink_protocol" => "USLP",
                 "frame_parameters" => [
                   %{
                     "id" => "spacecraft-profile-frame-parameter-frame_size",
                     "label" => "Frame Size",
                     "value" => "2048"
                   },
                   %{
                     "id" => "spacecraft-profile-frame-parameter-ocf_length",
                     "label" => "Ocf Length",
                     "value" => "0"
                   },
                   %{
                     "id" => "spacecraft-profile-frame-parameter-secondary_header_enabled",
                     "label" => "Secondary Header Enabled",
                     "value" => "yes"
                   },
                   %{
                     "id" => "spacecraft-profile-frame-parameter-truncated_primary_header",
                     "label" => "Truncated Primary Header",
                     "value" => "no"
                   }
                 ],
                 "id" => "spacecraft-profile-#{profile_v1.spacecraft_type_id}",
                 "lifecycle" => "active",
                 "packet_protocol" => "space_packet",
                 "profile_id" => profile_v1.spacecraft_type_id,
                 "uplink_protocol" => "USLP",
                 "version" => "v2"
               },
               "versions" => [
                 %{
                   "downlink_protocol" => "USLP",
                   "id" =>
                     "spacecraft-profile-version-#{profile_v1.spacecraft_type_id}-2",
                   "lifecycle" => "active",
                   "uplink_protocol" => "USLP",
                   "version" => "v2"
                 },
                 %{
                   "downlink_protocol" => "AOS",
                   "id" =>
                     "spacecraft-profile-version-#{profile_v1.spacecraft_type_id}-1",
                   "lifecycle" => "active",
                   "uplink_protocol" => "TC",
                   "version" => "v1"
                 }
               ]
             }

      assert persisted_v2.spacecraft_type_id == profile_v1.spacecraft_type_id
    end

    test "preserves empty frame-parameter and application presentation behavior" do
      {conn, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Minimal Bus",
          frame_parameters: %{},
          applications: %{}
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
        )

      props = spacecraft_profile_show_vue(view).props

      assert props["profile"]["frame_parameters"] == []
      assert props["profile"]["applications"] == []
      assert props["labels"]["no_applications"] == "No applications enabled."
      assert [%{"version" => "v1"}] = Enum.map(props["versions"], &Map.take(&1, ["version"]))
    end

    test "missing profile redirects to the scoped profile list with the existing error" do
      {conn, _org, mission} = signed_in_org_and_mission()

      assert {:error,
              {:live_redirect,
               %{
                 to: to,
                 flash: %{"error" => "Spacecraft profile not found."}
               }}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/profiles/missing-profile"
               )

      assert to == ~p"/missions/#{mission.mission_id}/spacecraft/profiles"
    end

    test "does not expose profile details outside the current mission or organization scope" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

      same_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_mission, display_name: "Same Org Foreign")

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")
      other_org_mission = TestFixtures.persist_mission!(other_org, slug: "remote")

      other_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_org_mission,
          display_name: "Other Org Foreign"
        )

      for foreign_profile <- [same_org_foreign, other_org_foreign] do
        assert {:error,
                {:live_redirect,
                 %{
                   to: to,
                   flash: %{"error" => "Spacecraft profile not found."}
                 }}} =
                 live(
                   conn,
                   ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{foreign_profile.spacecraft_type_id}"
                 )

        assert to == ~p"/missions/#{mission.mission_id}/spacecraft/profiles"
      end
    end

    test "unauthenticated profile detail requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(
                 conn,
                 ~p"/missions/mission-test/spacecraft/profiles/spacecraft-profile-test"
               )
    end
  end
end
