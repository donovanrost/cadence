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
    assert html =~ "Workspace"

    assert has_element?(view, "#install-spacecraft-application-telemetry_decom", "Install")

    refute has_element?(
             view,
             "#spacecraft-application-telemetry_decom a[href='/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom']"
           )

    view
    |> element("#install-spacecraft-application-telemetry_decom")
    |> render_click()

    assert has_element?(
             view,
             "#spacecraft-application-telemetry_decom a[href='/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom']",
             "Manage"
           )

    assert has_element?(
             view,
             "#disable-spacecraft-application-telemetry_decom[data-application-lifecycle-action='disable'][data-confirmation-required='true'][data-confirmation-tone='attention']",
             "Disable workspace"
           )

    assert has_element?(
             view,
             "#uninstall-spacecraft-application-telemetry_decom[data-application-lifecycle-action='uninstall'][data-confirmation-required='true'][data-confirmation-tone='danger']",
             "Uninstall"
           )
  end

  test "lists custom application keys from the pinned spacecraft profile" do
    {conn, _org, mission} = setup_session()

    profile =
      TestFixtures.persist_spacecraft_profile!(mission,
        display_name: "Aurora Bus",
        applications: %{
          "custom:thermal-alerting" => %{
            "display_name" => "Thermal Alerting",
            "description" => "Mission-owned temperature monitoring."
          }
        }
      )

    spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
      )

    assert has_element?(view, "#spacecraft-application-custom-thermal-alerting")

    assert has_element?(
             view,
             "#spacecraft-application-custom-thermal-alerting",
             "Thermal Alerting"
           )

    refute has_element?(view, "#spacecraft-application-custom-thermal-alerting a", "Manage")
  end

  test "manages retained workspace lifecycle for a spacecraft application" do
    {conn, _org, mission} = setup_session()
    profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
      )

    view
    |> element("#install-spacecraft-application-telemetry_decom")
    |> render_click()

    view
    |> element("#disable-spacecraft-application-telemetry_decom")
    |> render_click()

    assert has_element?(view, "#install-spacecraft-application-telemetry_decom", "Enable")

    view
    |> element("#uninstall-spacecraft-application-telemetry_decom")
    |> render_click()

    assert has_element?(view, "#install-spacecraft-application-telemetry_decom", "Reinstall")

    view
    |> element("#install-spacecraft-application-telemetry_decom")
    |> render_click()

    assert has_element?(view, "#disable-spacecraft-application-telemetry_decom")
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

  test "known but uninstalled application detail redirects to the inventory" do
    {conn, _org, mission} = setup_session()
    profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

    spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        display_name: "Nova-1",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    assert {:error,
            {:live_redirect,
             %{
               to: path,
               flash: %{"error" => "Install the application before opening it."}
             }}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"
             )

    assert path ==
             ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
  end
end
