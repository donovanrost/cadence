defmodule CadenceWeb.SpacecraftReadinessLiveTest do
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
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders spacecraft readiness with missing setup state" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"
        )

      assert has_element?(view, "#spacecraft-readiness-page")
      assert has_element?(view, "#spacecraft-readiness-identity")
      assert has_element?(view, "#spacecraft-readiness-profile")
      assert has_element?(view, "#spacecraft-readiness-applications")
      assert has_element?(view, "#spacecraft-readiness-routing")

      assert html =~ "Identity, profile, and application setup"
      assert html =~ "Missing SCID"
      assert html =~ "No profile selected"
      assert html =~ "Profile required"
      assert html =~ "Tracked in Comms"
      refute html =~ "Link Assignments"
      refute html =~ "Needs downlink"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
    end

    test "lists every profile application through generic inventory status" do
      {conn, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          applications: %{
            "custom:thermal-alerting" => %{"display_name" => "Thermal Alerting"},
            "telemetry_decom" => %{}
          }
        )

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          scid: 42,
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"
        )

      assert has_element?(
               view,
               "#spacecraft-readiness-application-custom-thermal-alerting",
               "Unavailable"
             )

      assert has_element?(
               view,
               "#spacecraft-readiness-application-telemetry_decom",
               "Not installed"
             )

      assert has_element?(view, "#spacecraft-readiness-applications", "0 of 2 ready")

      assert has_element?(
               view,
               "#spacecraft-readiness-applications a[href='/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications']"
             )
    end
  end
end
