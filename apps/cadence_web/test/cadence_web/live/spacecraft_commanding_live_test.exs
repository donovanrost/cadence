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
    test "renders exact JSON-safe command interpretation placeholder props" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, _html} = live(conn, commanding_path(mission, spacecraft.spacecraft_id))

      assert has_element?(view, "#spacecraft-commanding-component")

      vue = spacecraft_commanding_vue(view)

      assert vue.component == "SpacecraftCommanding"
      assert vue.ssr == false
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))

      assert vue.props == %{
               "page" => %{
                 "id" => "spacecraft-commanding-page",
                 "title" => "Commanding for Nova-1",
                 "subtitle" =>
                   "Spacecraft-owned command interpretation will collect command encoding, TC frame defaults, and uplink behavior once command setup is exposed.",
                 "eyebrow" => "Command Interpretation",
                 "breadcrumbs" => [
                   %{
                     "label" => "Primary Mission",
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   %{
                     "label" => "Spacecraft",
                     "href" => "/missions/#{mission.mission_id}/spacecraft"
                   },
                   %{
                     "label" => "Nova-1",
                     "href" =>
                       "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                   },
                   %{"label" => "Commanding", "href" => nil}
                 ],
                 "status" => %{"tone" => "info", "label" => "Not tracked"}
               },
               "panels" => [
                 %{
                   "id" => "spacecraft-commanding-encoding",
                   "title" => "Command Encoding",
                   "value" => "Not tracked",
                   "status" => %{"tone" => "info", "label" => "Setup"},
                   "description" =>
                     "Command catalog binding and encoding defaults will live with this spacecraft."
                 },
                 %{
                   "id" => "spacecraft-commanding-tc-framing",
                   "title" => "TC Framing Defaults",
                   "value" => "Not tracked",
                   "status" => %{"tone" => "info", "label" => "Setup"},
                   "description" =>
                     "SCID, VCID, sequence defaults, and frame settings will be configured here when needed."
                 },
                 %{
                   "id" => "spacecraft-commanding-uplink",
                   "title" => "Uplink Behavior",
                   "value" => "Not tracked",
                   "status" => %{"tone" => "info", "label" => "Setup"},
                   "description" =>
                     "COP-1 and uplink-gateway behavior is configured on the spacecraft's type. Surface here when commanding ships."
                 }
               ],
               "readiness" => %{
                 "eyebrow" => "Readiness Impact",
                 "title" => "Command interpretation is not part of readiness yet",
                 "description" =>
                   "This page keeps the spacecraft-owned command surface visible while command setup matures. Current readiness still focuses on identity, telemetry interpretation, and link assignment.",
                 "status" => %{"tone" => "info", "label" => "Placeholder"}
               }
             }

      # One-to-one preservation of the original seven focused assertions.
      assert vue.props["page"]["id"] == "spacecraft-commanding-page"
      assert Enum.any?(vue.props["panels"], &(&1["id"] == "spacecraft-commanding-encoding"))

      assert Enum.any?(
               vue.props["panels"],
               &(&1["id"] == "spacecraft-commanding-tc-framing")
             )

      assert Enum.any?(vue.props["panels"], &(&1["id"] == "spacecraft-commanding-uplink"))
      assert vue.props["page"]["eyebrow"] == "Command Interpretation"
      assert vue.props["page"]["title"] == "Commanding for Nova-1"
      assert vue.props["page"]["status"]["label"] == "Not tracked"
    end

    test "uses one client-rendered host inside the mission sidebar layout" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nav-Check", scid: 42)

      {:ok, view, _html} = live(conn, commanding_path(mission, spacecraft.spacecraft_id))

      vue = spacecraft_commanding_vue(view)

      assert vue.ssr == false
      assert has_element?(view, "#spacecraft-commanding-component")
      refute has_element?(view, "#spacecraft-commanding-page")
      refute has_element?(view, "#spacecraft-commanding-encoding")
      refute has_element?(view, "#spacecraft-commanding-tc-framing")
      refute has_element?(view, "#spacecraft-commanding-uplink")

      assert has_element?(view, "#sidebar-drawer")
      assert has_element?(view, "[data-sidebar-collapsible]")

      assert has_element?(
               view,
               "nav a[href='/missions/#{mission.mission_id}/spacecraft'][class~='border-primary'][class~='text-primary']",
               "Spacecraft"
             )
    end

    test "does not load missing or out-of-scope spacecraft" do
      {conn, org, mission} = signed_in_org_and_mission()

      sibling_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

      sibling_spacecraft =
        TestFixtures.persist_spacecraft!(sibling_mission, display_name: "Sibling")

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Foreign")
      spacecraft_list_path = ~p"/missions/#{mission.mission_id}/spacecraft"

      for spacecraft_id <- [
            "missing-spacecraft",
            sibling_spacecraft.spacecraft_id,
            other_spacecraft.spacecraft_id
          ] do
        assert {:error,
                {:redirect,
                 %{
                   to: ^spacecraft_list_path,
                   flash: %{"error" => "Spacecraft not found."}
                 }}} = live(conn, commanding_path(mission, spacecraft_id))
      end
    end

    test "unauthenticated requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/mission-test/spacecraft/spacecraft-test/commanding")
    end
  end

  defp spacecraft_commanding_vue(view) do
    LiveVue.Test.get_vue(view, id: "spacecraft-commanding-component")
  end

  defp commanding_path(mission, spacecraft_id) do
    ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft_id}/commanding"
  end
end
