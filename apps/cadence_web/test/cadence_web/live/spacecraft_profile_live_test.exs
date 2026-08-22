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

  describe "profile routes" do
    test "spacecraft management page exposes vehicle and profile cards with scoped actions" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Aurora-1", scid: 42)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert has_element?(view, "#spacecraft-management-page")
      assert has_element?(view, "#spacecraft-vehicles-card")
      assert has_element?(view, "#spacecraft-profiles-card")

      assert has_element?(
               view,
               "#spacecraft-vehicles-card a[href='/missions/#{mission.mission_id}/spacecraft/new']",
               "New spacecraft"
             )

      assert has_element?(
               view,
               "#spacecraft-profiles-card a[href='/missions/#{mission.mission_id}/spacecraft/profiles/new']",
               "New profile"
             )

      assert has_element?(view, "#spacecraft-vehicles-card td", spacecraft.display_name)
      assert has_element?(view, "#spacecraft-profiles-card td", profile.display_name)

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

    test "lists spacecraft profiles using profile vocabulary" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

      assert has_element?(
               view,
               "a[href='/missions/#{mission.mission_id}/spacecraft/profiles/new']"
             )

      assert has_element?(view, "td", profile.display_name)

      page = render(view)
      assert page =~ "Spacecraft Profiles"
      refute page =~ "Spacecraft Types"
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

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
        )

      assert has_element?(view, "a[href='/missions/#{mission.mission_id}/spacecraft/profiles']")
      assert html =~ "Aurora Bus"
      assert html =~ "Byte Interpretation"
      refute html =~ "Spacecraft Type"
    end
  end
end
