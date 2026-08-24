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
    test "renders exact JSON-safe spacecraft readiness with missing setup state" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, _html} = live(conn, readiness_path(mission, spacecraft.spacecraft_id))

      assert has_element?(view, "#spacecraft-readiness-component")

      vue = spacecraft_readiness_vue(view)

      assert vue.component == "SpacecraftReadiness"
      assert vue.ssr == false
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))
      assert vue.props == expected_missing_props(mission, spacecraft)

      props = vue.props

      # One-to-one preservation of every original missing-state assertion.
      assert props["page"]["id"] == "spacecraft-readiness-page"
      assert Enum.any?(props["panels"], &(&1["id"] == "spacecraft-readiness-identity"))
      assert Enum.any?(props["panels"], &(&1["id"] == "spacecraft-readiness-profile"))

      assert Enum.any?(
               props["panels"],
               &(&1["id"] == "spacecraft-readiness-applications")
             )

      assert Enum.any?(props["panels"], &(&1["id"] == "spacecraft-readiness-routing"))
      assert props["page"]["subtitle"] =~ "Identity, profile, and application setup"

      assert readiness_panel(props, "spacecraft-readiness-identity")["status"]["label"] ==
               "Missing SCID"

      assert readiness_panel(props, "spacecraft-readiness-profile")["status"]["label"] ==
               "No profile selected"

      assert readiness_panel(props, "spacecraft-readiness-applications")["status"]["label"] ==
               "Profile required"

      assert readiness_panel(props, "spacecraft-readiness-routing")["status"]["label"] ==
               "Tracked in Comms"

      refute inspect(props) =~ "Link Assignments"
      refute inspect(props) =~ "Needs downlink"

      assert readiness_panel(props, "spacecraft-readiness-identity")["action"]["href"] ==
               "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

      assert readiness_panel(props, "spacecraft-readiness-applications")["action"]["href"] ==
               "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

      assert readiness_panel(props, "spacecraft-readiness-routing")["action"]["href"] ==
               "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
    end

    test "lists every profile application in generic inventory order with safe IDs" do
      {conn, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Aurora Bus",
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

      {:ok, view, _html} = live(conn, readiness_path(mission, spacecraft.spacecraft_id))

      vue = spacecraft_readiness_vue(view)
      props = vue.props

      assert props == Jason.decode!(Jason.encode!(props))

      assert props["applications"] == [
               %{
                 "id" => "spacecraft-readiness-application-custom-thermal-alerting",
                 "application_key" => "custom:thermal-alerting",
                 "display_name" => "Thermal Alerting",
                 "status" => %{"tone" => "blocked", "label" => "Unavailable"}
               },
               %{
                 "id" => "spacecraft-readiness-application-telemetry_decom",
                 "application_key" => "telemetry_decom",
                 "display_name" => "Telemetry Decom",
                 "status" => %{"tone" => "info", "label" => "Not installed"}
               }
             ]

      assert readiness_panel(props, "spacecraft-readiness-identity") == %{
               "id" => "spacecraft-readiness-identity",
               "title" => "Identity",
               "status" => %{"tone" => "ready", "label" => "Ready"},
               "description" => "The spacecraft identity is configured.",
               "details" => [%{"label" => "SCID", "value" => "42"}],
               "action" => %{
                 "label" => "Edit Identity",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
               },
               "application_list" => nil
             }

      assert readiness_panel(props, "spacecraft-readiness-profile") == %{
               "id" => "spacecraft-readiness-profile",
               "title" => "Spacecraft Profile",
               "status" => %{"tone" => "ready", "label" => "Current"},
               "description" => "The spacecraft is pinned to a Spacecraft Profile version.",
               "details" => [%{"label" => "Pinned Profile", "value" => "Aurora Bus v1"}],
               "action" => %{
                 "label" => "Change Profile",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
               },
               "application_list" => nil
             }

      assert readiness_panel(props, "spacecraft-readiness-applications") == %{
               "id" => "spacecraft-readiness-applications",
               "title" => "Applications",
               "status" => %{"tone" => "blocked", "label" => "0 of 2 ready"},
               "description" => "0 of 2 ready across 2 profile applications.",
               "details" => [],
               "action" => %{
                 "label" => "Review applications",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
               },
               "application_list" => %{
                 "id" => "spacecraft-readiness-application-list",
                 "empty_state" => %{
                   "id" => "spacecraft-readiness-applications-empty",
                   "description" => "No profile applications declared."
                 }
               }
             }

      assert props["page"]["status"] == %{"tone" => "attention", "label" => "Needs Work"}

      # One-to-one preservation of every original generic-inventory assertion.
      assert Enum.any?(props["applications"], fn application ->
               application["id"] ==
                 "spacecraft-readiness-application-custom-thermal-alerting" and
                 application["status"]["label"] == "Unavailable"
             end)

      assert Enum.any?(props["applications"], fn application ->
               application["id"] == "spacecraft-readiness-application-telemetry_decom" and
                 application["status"]["label"] == "Not installed"
             end)

      assert readiness_panel(props, "spacecraft-readiness-applications")["status"]["label"] ==
               "0 of 2 ready"

      assert readiness_panel(props, "spacecraft-readiness-applications")["action"]["href"] ==
               "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
    end

    test "preserves the current-profile application empty state" do
      {conn, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Empty Bus",
          applications: %{}
        )

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          scid: 21,
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        )

      {:ok, view, _html} = live(conn, readiness_path(mission, spacecraft.spacecraft_id))

      props = spacecraft_readiness_vue(view).props

      assert props == Jason.decode!(Jason.encode!(props))
      assert props["applications"] == []

      assert readiness_panel(props, "spacecraft-readiness-applications") == %{
               "id" => "spacecraft-readiness-applications",
               "title" => "Applications",
               "status" => %{"tone" => "info", "label" => "None declared"},
               "description" =>
                 "This spacecraft profile does not declare any product applications.",
               "details" => [],
               "action" => %{
                 "label" => "Review applications",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
               },
               "application_list" => %{
                 "id" => "spacecraft-readiness-application-list",
                 "empty_state" => %{
                   "id" => "spacecraft-readiness-applications-empty",
                   "description" => "No profile applications declared."
                 }
               }
             }

      assert readiness_panel(props, "spacecraft-readiness-profile")["status"] == %{
               "tone" => "ready",
               "label" => "Current"
             }

      assert props["page"]["status"] == %{"tone" => "attention", "label" => "Needs Work"}
    end

    test "keeps a spacecraft pinned when a newer profile version exists" do
      {conn, org, mission} = signed_in_org_and_mission()

      %Cadence.SpacecraftType{} =
        profile_v1 =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Aurora Bus",
          applications: %{}
        )

      profile_v2 = %Cadence.SpacecraftType{profile_v1 | version: 2}

      assert {:ok, _persisted_v2} =
               Cadence.SpacecraftTypeStore.persist_spacecraft_type(
                 org.organization_id,
                 profile_v2
               )

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          scid: 84,
          spacecraft_type_id: profile_v1.spacecraft_type_id,
          spacecraft_type_version: profile_v1.version
        )

      {:ok, view, _html} = live(conn, readiness_path(mission, spacecraft.spacecraft_id))

      props = spacecraft_readiness_vue(view).props

      assert props == Jason.decode!(Jason.encode!(props))

      assert readiness_panel(props, "spacecraft-readiness-profile") == %{
               "id" => "spacecraft-readiness-profile",
               "title" => "Spacecraft Profile",
               "status" => %{"tone" => "attention", "label" => "Profile drift"},
               "description" =>
                 "A newer Spacecraft Profile version is available; this spacecraft remains pinned.",
               "details" => [%{"label" => "Pinned Profile", "value" => "Aurora Bus v1"}],
               "action" => %{
                 "label" => "Change Profile",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
               },
               "application_list" => nil
             }

      assert props["page"]["status"] == %{"tone" => "attention", "label" => "Needs Work"}
    end

    test "uses one client-rendered host inside the mission sidebar layout" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nav-Check")

      {:ok, view, _html} = live(conn, readiness_path(mission, spacecraft.spacecraft_id))

      vue = spacecraft_readiness_vue(view)

      assert vue.component == "SpacecraftReadiness"
      assert vue.ssr == false
      assert has_element?(view, "#spacecraft-readiness-component")
      refute has_element?(view, "#spacecraft-readiness-page")
      refute has_element?(view, "#spacecraft-readiness-identity")
      refute has_element?(view, "#spacecraft-readiness-profile")
      refute has_element?(view, "#spacecraft-readiness-applications")
      refute has_element?(view, "#spacecraft-readiness-routing")
      refute has_element?(view, "#spacecraft-readiness-application-list")
      refute has_element?(view, "#spacecraft-readiness-applications-empty")

      assert has_element?(view, "#sidebar-drawer")

      sidebar = LiveVue.Test.get_vue(view, id: "mission-sidebar-navigation")

      spacecraft_nav =
        Enum.find(
          sidebar.props["presentation"]["navigation"]["items"],
          &(&1["key"] == "spacecraft")
        )

      assert sidebar.props["presentation"]["root"]["attrs"] == %{
               "data-sidebar-collapsible" => ""
             }

      assert spacecraft_nav["attrs"]["href"] == "/missions/#{mission.mission_id}/spacecraft"
      assert spacecraft_nav["label"] == "Spacecraft"
      assert spacecraft_nav["class"] =~ "border-primary"
      assert spacecraft_nav["class"] =~ "text-primary"
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
                 }}} = live(conn, readiness_path(mission, spacecraft_id))
      end
    end

    test "unauthenticated requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/mission-test/spacecraft/spacecraft-test/readiness")
    end
  end

  defp spacecraft_readiness_vue(view) do
    LiveVue.Test.get_vue(view, id: "spacecraft-readiness-component")
  end

  defp readiness_panel(props, id) do
    Enum.find(props["panels"], &(&1["id"] == id))
  end

  defp readiness_path(mission, spacecraft_id) do
    ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft_id}/readiness"
  end

  defp expected_missing_props(mission, spacecraft) do
    spacecraft_base = "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"

    %{
      "page" => %{
        "id" => "spacecraft-readiness-page",
        "title" => "Readiness",
        "title_suffix" => "· Nova-1",
        "subtitle" => "Identity, profile, and application setup for this spacecraft.",
        "breadcrumbs" => [
          %{"label" => "Primary Mission", "href" => "/missions/#{mission.mission_id}"},
          %{"label" => "Spacecraft", "href" => "/missions/#{mission.mission_id}/spacecraft"},
          %{"label" => "Nova-1", "href" => spacecraft_base},
          %{"label" => "Readiness", "href" => nil}
        ],
        "status" => %{"tone" => "attention", "label" => "Needs Work"}
      },
      "panels" => [
        %{
          "id" => "spacecraft-readiness-identity",
          "title" => "Identity",
          "status" => %{"tone" => "blocked", "label" => "Missing SCID"},
          "description" =>
            "Set SCID so Cadence can identify this spacecraft from TM transfer frames.",
          "details" => [%{"label" => "SCID", "value" => "Not set"}],
          "action" => %{"label" => "Edit Identity", "href" => spacecraft_base <> "/identity"},
          "application_list" => nil
        },
        %{
          "id" => "spacecraft-readiness-profile",
          "title" => "Spacecraft Profile",
          "status" => %{"tone" => "attention", "label" => "No profile selected"},
          "description" =>
            "Select a Spacecraft Profile to pin a reusable byte-interpretation contract.",
          "details" => [%{"label" => "Pinned Profile", "value" => "Not selected"}],
          "action" => %{"label" => "Select Profile", "href" => spacecraft_base <> "/identity"},
          "application_list" => nil
        },
        %{
          "id" => "spacecraft-readiness-applications",
          "title" => "Applications",
          "status" => %{"tone" => "blocked", "label" => "Profile required"},
          "description" => "Select a spacecraft profile before installing product applications.",
          "details" => [],
          "action" => %{
            "label" => "Review applications",
            "href" => spacecraft_base <> "/applications"
          },
          "application_list" => %{
            "id" => "spacecraft-readiness-application-list",
            "empty_state" => %{
              "id" => "spacecraft-readiness-applications-empty",
              "description" => "No profile applications declared."
            }
          }
        },
        %{
          "id" => "spacecraft-readiness-routing",
          "title" => "Routing",
          "status" => %{"tone" => "info", "label" => "Tracked in Comms"},
          "description" => "Routing Rules describe durable spacecraft use of mission transports.",
          "details" => [%{"label" => "Setup Area", "value" => "Routing Rules"}],
          "action" => %{"label" => "Review Routing", "href" => spacecraft_base <> "/routing"},
          "application_list" => nil
        }
      ],
      "applications" => []
    }
  end
end
