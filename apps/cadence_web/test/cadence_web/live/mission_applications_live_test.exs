defmodule CadenceWeb.MissionApplicationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "authenticated mission members mount the mission applications surface" do
    {conn, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/applications")

    assert_surface(
      view,
      "mission-applications-page-component",
      "mission_applications",
      mission,
      %{}
    )
  end

  test "host-owned management installs, disables, and uninstalls only optional capabilities" do
    {conn, mission} = signed_in_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/applications")

    for {event, state} <- [
          {"install", "installed"},
          {"disable", "disabled"},
          {"uninstall", "uninstalled"}
        ] do
      render_hook(view, "host:manage", %{
        "event" => event,
        "key" => "limits",
        "path" => Test.get_vue(view, id: "application-shell").props["snapshot"]["path"]
      })

      applications =
        Test.get_vue(view, id: "application-shell").props["snapshot"]["presentation"][
          "applications_component"
        ]["props"]["applications"]

      assert Enum.find(applications, &(&1["application_key"] == "limits"))["lifecycle_state"] ==
               state
    end

    render_hook(view, "host:manage", %{
      "event" => "install",
      "key" => "mission_catalog",
      "path" => Test.get_vue(view, id: "application-shell").props["snapshot"]["path"]
    })

    refute Cadence.Repo.get_by(Cadence.Applications.ApplicationInstallations.InstallationRow,
             mission_id: mission.mission_id,
             application_key: "mission_catalog"
           )
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/mission-test/applications")
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, _id, _surface_id, _mission, _query_params) do
    assert has_element?(view, "#application-shell")

    vue = Test.get_vue(view, id: "application-shell")

    assert vue.component == "BrowserHost"
    assert vue.id == "application-shell"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert is_map(vue.props["snapshot"]["presentation"])

    applications =
      get_in(vue.props, [
        "snapshot",
        "presentation",
        "applications_component",
        "props",
        "applications"
      ])

    assert Enum.map(applications, & &1["application_key"]) == ["derived_telemetry", "limits"]
  end
end
