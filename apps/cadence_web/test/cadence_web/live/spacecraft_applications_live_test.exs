defmodule CadenceWeb.SpacecraftApplicationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp setup_session do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "lists applications from the pinned spacecraft profile" do
    {conn, _org, mission} = setup_session()
    profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
      )

    assert has_element?(view, "#spacecraft-applications-page")
    assert has_element?(view, "#spacecraft-application-telemetry_decom")
    assert html =~ "Applications"
    assert html =~ "Telemetry Decom"
    assert html =~ "Packet claims"

    assert html =~
             ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
  end

  test "shows a profile setup gap when no profile is pinned" do
    {conn, _org, mission} = setup_session()
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

    {:ok, view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
      )

    assert has_element?(view, "#spacecraft-applications-no-profile")
    assert html =~ "No profile selected"
  end

  test "unknown application detail redirects back to the applications list" do
    {conn, _org, mission} = setup_session()
    profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    assert {:error, {:live_redirect, %{to: path, flash: %{"error" => "Application not found."}}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/not_real"
             )

    assert path ==
             ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
  end
end
