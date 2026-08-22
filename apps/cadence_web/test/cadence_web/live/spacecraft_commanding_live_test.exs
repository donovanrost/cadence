defmodule CadenceWeb.SpacecraftCommandingLiveTest do
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
    test "renders command interpretation placeholder for a spacecraft" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/commanding"
        )

      assert has_element?(view, "#spacecraft-commanding-page")
      assert has_element?(view, "#spacecraft-commanding-encoding")
      assert has_element?(view, "#spacecraft-commanding-tc-framing")
      assert has_element?(view, "#spacecraft-commanding-uplink")
      assert html =~ "Command Interpretation"
      assert html =~ "Commanding for Nova-1"
      assert html =~ "Not tracked"
    end
  end
end
