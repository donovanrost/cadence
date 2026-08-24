defmodule CadenceWeb.SpacecraftShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Spacecraft
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp spacecraft_show_props(view) do
    assert has_element?(view, "#spacecraft-show-component")
    refute has_element?(view, "#spacecraft-show-page")

    vue = LiveVue.Test.get_vue(view, id: "spacecraft-show-component")

    assert vue.component == "SpacecraftShow"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props
  end

  describe "mount" do
    test "renders exact JSON-safe unbound spacecraft detail props through the non-SSR host" do
      {conn, _user, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      identity_href =
        "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

      applications_href =
        "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

      readiness_href =
        "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"

      assert spacecraft_show_props(view) == %{
               "page" => %{
                 "id" => "spacecraft-show-page",
                 "header" => %{
                   "title" => "Nova-1",
                   "breadcrumbs" => [
                     %{
                       "label" => "Primary Mission",
                       "href" => "/missions/#{mission.mission_id}"
                     },
                     %{
                       "label" => "Spacecraft",
                       "href" => "/missions/#{mission.mission_id}/spacecraft"
                     },
                     %{"label" => "Nova-1", "href" => nil}
                   ],
                   "title_suffix" => %{"set" => true, "label" => "SCID 42"}
                 }
               },
               "profile_binding" => %{
                 "id" => "spacecraft-profile-binding",
                 "eyebrow" => "Spacecraft Profile",
                 "bound" => false,
                 "title" => "No profile selected",
                 "description" =>
                   "Select a spacecraft profile to pin a reusable byte-interpretation contract.",
                 "version" => nil,
                 "protocols" => [],
                 "status" => %{"tone" => "attention", "label" => "Unbound"},
                 "view_profile_href" => nil,
                 "profile_action" => %{
                   "label" => "Select profile",
                   "href" => identity_href
                 }
               },
               "applications" => %{
                 "id" => "spacecraft-applications",
                 "list_id" => "spacecraft-profile-applications",
                 "visible" => false,
                 "title" => "Applications",
                 "description" =>
                   "Retained spacecraft installations. Select a profile to restore desired application declarations.",
                 "empty" => true,
                 "empty_state" => "No applications enabled by this profile.",
                 "rows" => [],
                 "view_action" => %{
                   "label" => "View applications",
                   "href" => applications_href
                 }
               },
               "workflow_cards" => [
                 %{
                   "id" => "spacecraft-overview-identity",
                   "title" => "Identity",
                   "value" => "Runtime identity missing",
                   "description" => "Values Cadence uses to recognize incoming bytes.",
                   "status" => %{"tone" => "attention", "label" => "Needs Work"},
                   "action" => %{"label" => "Edit Identity", "href" => identity_href}
                 },
                 %{
                   "id" => "spacecraft-overview-applications",
                   "title" => "Applications",
                   "value" => "Profile required",
                   "description" =>
                     "Select a spacecraft profile before installing product applications.",
                   "status" => %{"tone" => "blocked", "label" => "Missing"},
                   "action" => %{
                     "label" => "Review applications",
                     "href" => applications_href
                   }
                 },
                 %{
                   "id" => "spacecraft-overview-readiness",
                   "title" => "Readiness",
                   "value" => "Needs review",
                   "description" => "Identity and application status at a glance.",
                   "status" => %{"tone" => "attention", "label" => "Needs Work"},
                   "action" => %{"label" => "Review", "href" => readiness_href}
                 }
               ],
               "overview" => %{
                 "title" => "Overview",
                 "scid" => %{"label" => "SCID", "value" => "42"},
                 "display_name" => %{"label" => "Display name", "value" => "Nova-1"},
                 "spacecraft_id" => %{
                   "label" => "Spacecraft ID",
                   "value" => spacecraft.spacecraft_id
                 },
                 "mission" => %{
                   "label" => "Mission",
                   "value" => "Primary Mission",
                   "href" => "/missions/#{mission.mission_id}"
                 },
                 "organization_id" => %{
                   "label" => "Organization ID",
                   "value" => org.organization_id
                 },
                 "metadata_json" => nil
               }
             }
    end

    test "preserves generic application ordering, safe IDs, statuses, and scoped paths" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Extensible Bus",
          applications: %{
            "custom:thermal-alerting" => %{"display_name" => "Thermal Alerting"},
            "telemetry_decom" => %{}
          }
        )

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      props = spacecraft_show_props(view)

      identity_href =
        "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

      assert props["profile_binding"] == %{
               "id" => "spacecraft-profile-binding",
               "eyebrow" => "Spacecraft Profile",
               "bound" => true,
               "title" => "Extensible Bus",
               "description" => nil,
               "version" => "v1",
               "protocols" => [
                 %{"label" => "DOWN", "value" => "tm"},
                 %{"label" => "UP", "value" => "tc"}
               ],
               "status" => %{"tone" => "ready", "label" => "Current"},
               "view_profile_href" =>
                 "/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}",
               "profile_action" => %{"label" => "Change profile", "href" => identity_href}
             }

      assert props["applications"] == %{
               "id" => "spacecraft-applications",
               "list_id" => "spacecraft-profile-applications",
               "visible" => true,
               "title" => "Applications",
               "description" =>
                 "Platform applications enabled by this spacecraft's profile. Per-application configuration is set per spacecraft.",
               "empty" => false,
               "empty_state" => "No applications enabled by this profile.",
               "rows" => [
                 %{
                   "id" => "spacecraft-profile-application-custom-thermal-alerting",
                   "application_key" => "custom:thermal-alerting",
                   "display_name" => "Thermal Alerting",
                   "status" => %{"tone" => "blocked", "label" => "Unavailable"},
                   "manage_href" => nil
                 },
                 %{
                   "id" => "spacecraft-profile-application-telemetry_decom",
                   "application_key" => "telemetry_decom",
                   "display_name" => "Telemetry Decom",
                   "status" => %{"tone" => "info", "label" => "Not installed"},
                   "manage_href" => nil
                 }
               ],
               "view_action" => %{
                 "label" => "View applications",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
               }
             }

      assert Enum.find(props["workflow_cards"], &(&1["id"] == "spacecraft-overview-applications")) ==
               %{
                 "id" => "spacecraft-overview-applications",
                 "title" => "Applications",
                 "value" => "0 of 2 ready",
                 "description" => "0 of 2 ready across 2 profile applications.",
                 "status" => %{"tone" => "blocked", "label" => "Missing"},
                 "action" => %{
                   "label" => "Review applications",
                   "href" =>
                     "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
                 }
               }

      refute Enum.any?(props["applications"]["rows"], & &1["manage_href"])
    end

    test "keeps the conditional profile application empty state and summary semantics" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Minimal Bus",
          applications: %{}
        )

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      props = spacecraft_show_props(view)

      assert props["applications"]["visible"] == true
      assert props["applications"]["empty"] == true
      assert props["applications"]["rows"] == []
      assert props["applications"]["empty_state"] == "No applications enabled by this profile."

      assert props["applications"]["description"] ==
               "Platform applications enabled by this spacecraft's profile. Per-application configuration is set per spacecraft."

      assert Enum.find(props["workflow_cards"], &(&1["id"] == "spacecraft-overview-applications")) ==
               %{
                 "id" => "spacecraft-overview-applications",
                 "title" => "Applications",
                 "value" => "None declared",
                 "description" =>
                   "This spacecraft profile does not declare any product applications.",
                 "status" => %{"tone" => "info", "label" => "Setup"},
                 "action" => %{
                   "label" => "Review applications",
                   "href" =>
                     "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"
                 }
               }
    end

    test "renders the pinned profile and drift badge against the latest profile version" do
      {conn, _user, org, mission} = signed_in_org_and_mission()

      %Cadence.SpacecraftType{} =
        profile_v1 =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Aurora Bus",
          downlink_protocol: :aos,
          uplink_protocol: :tc,
          applications: %{}
        )

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          spacecraft_type_id: profile_v1.spacecraft_type_id,
          spacecraft_type_version: profile_v1.version
        )

      profile_v2 = %Cadence.SpacecraftType{
        profile_v1
        | version: 2,
          downlink_protocol: :uslp,
          uplink_protocol: :uslp
      }

      assert {:ok, _persisted_v2} =
               Cadence.SpacecraftTypeStore.persist_spacecraft_type(
                 org.organization_id,
                 profile_v2
               )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      assert spacecraft_show_props(view)["profile_binding"] == %{
               "id" => "spacecraft-profile-binding",
               "eyebrow" => "Spacecraft Profile",
               "bound" => true,
               "title" => "Aurora Bus",
               "description" => nil,
               "version" => "v1",
               "protocols" => [
                 %{"label" => "DOWN", "value" => "aos"},
                 %{"label" => "UP", "value" => "tc"}
               ],
               "status" => %{"tone" => "attention", "label" => "Drift · latest v2"},
               "view_profile_href" =>
                 "/missions/#{mission.mission_id}/spacecraft/profiles/#{profile_v1.spacecraft_type_id}",
               "profile_action" => %{
                 "label" => "Change profile",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
               }
             }
    end

    test "preserves unset SCID copy and conditional pretty metadata JSON" do
      {conn, _user, org, mission} = signed_in_org_and_mission()
      metadata = %{"agency" => "JAXA", "launch" => %{"year" => 2026}, "tags" => ["poc"]}

      spacecraft =
        Spacecraft.new(%{
          mission_id: mission.mission_id,
          display_name: "Nova-Metadata",
          metadata: metadata
        })

      assert {:ok, spacecraft} =
               Cadence.SpacecraftStore.persist_spacecraft(org.organization_id, spacecraft)

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      props = spacecraft_show_props(view)

      assert props["page"]["header"]["title_suffix"] == %{
               "set" => false,
               "label" => "SCID not set"
             }

      assert props["overview"]["scid"] == %{"label" => "SCID", "value" => "Not set"}
      assert props["overview"]["metadata_json"] == Jason.encode!(metadata, pretty: true)
      assert props["overview"]["metadata_json"] =~ "\n  \""
      assert Jason.decode!(props["overview"]["metadata_json"]) == metadata
    end

    test "keeps retained installation copy and the manageable application path when unbound" do
      {conn, _user, org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        )

      applications_href =
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

      {:ok, applications_view, _html} = live(conn, applications_href)

      render_hook(applications_view, "install_application", %{"key" => "telemetry_decom"})

      unbound_spacecraft = %Spacecraft{
        spacecraft
        | spacecraft_type_id: nil,
          spacecraft_type_version: nil
      }

      assert {:ok, _persisted_unbound} =
               Cadence.SpacecraftStore.update_spacecraft(
                 org.organization_id,
                 unbound_spacecraft
               )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      props = spacecraft_show_props(view)

      assert props["applications"]["visible"] == true
      assert props["applications"]["empty"] == false

      assert props["applications"]["description"] ==
               "Retained spacecraft installations. Select a profile to restore desired application declarations."

      telemetry_decom =
        Enum.find(
          props["applications"]["rows"],
          &(&1["application_key"] == "telemetry_decom")
        )

      assert telemetry_decom["id"] == "spacecraft-profile-application-telemetry_decom"
      assert telemetry_decom["display_name"] == "Telemetry Decom"

      assert telemetry_decom["manage_href"] ==
               "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom"

      application_workflow =
        Enum.find(props["workflow_cards"], &(&1["id"] == "spacecraft-overview-applications"))

      assert application_workflow["description"] ==
               "Retained installations remain available; select a spacecraft profile to restore desired application declarations."

      assert application_workflow["action"] == %{
               "label" => "Review applications",
               "href" => applications_href
             }
    end

    test "unknown spacecraft redirects to the mission's spacecraft list" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/missing-id")

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to a sibling mission is not found" do
      {conn, _user, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Sibling")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to another organization is not found" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Foreign")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "sidebar highlights the Spacecraft nav entry" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nav-Check")
      list_url = ~p"/missions/#{mission.mission_id}/spacecraft"

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      sidebar = LiveVue.Test.get_vue(view, id: "mission-sidebar-navigation")

      spacecraft_nav =
        Enum.find(
          sidebar.props["presentation"]["navigation"]["items"],
          &(&1["key"] == "spacecraft")
        )

      assert spacecraft_nav["attrs"]["href"] == list_url
      assert spacecraft_nav["label"] == "Spacecraft"
      assert spacecraft_nav["class"] =~ "bg-primary/10"
      assert spacecraft_nav["class"] =~ "border-primary"
    end
  end
end
