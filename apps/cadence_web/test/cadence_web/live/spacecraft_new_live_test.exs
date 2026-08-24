defmodule CadenceWeb.SpacecraftNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders the Vue-owned form with exact JSON-safe presentation props" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      assert has_element?(view, "#spacecraft-new-component")
      refute has_element?(view, "#spacecraft-new-page")
      refute has_element?(view, "#spacecraft-form")

      vue = spacecraft_new_vue(view)

      assert vue.props == %{
               "page" => %{
                 "id" => "spacecraft-new-page",
                 "heading" => "New Spacecraft",
                 "subtitle" =>
                   "Register a spacecraft for this mission. Optionally select a profile to pin its byte-interpretation contract.",
                 "breadcrumbs" => [
                   %{
                     "label" => "Primary Mission",
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   %{
                     "label" => "Spacecraft",
                     "href" => "/missions/#{mission.mission_id}/spacecraft"
                   },
                   %{"label" => "New Spacecraft", "href" => nil}
                 ]
               },
               "form" => %{
                 "id" => "spacecraft-form",
                 "sections" => %{
                   "identity" => %{
                     "id" => "spacecraft-identity-section",
                     "number" => "01",
                     "title" => "Identity"
                   },
                   "profile" => %{
                     "id" => "spacecraft-profile-section",
                     "number" => "02",
                     "title" => "Profile"
                   }
                 },
                 "fields" => %{
                   "display_name" => %{
                     "id" => "spacecraft_display_name",
                     "name" => "spacecraft[display_name]",
                     "type" => "text",
                     "label" => "Display Name",
                     "required" => true,
                     "value" => ""
                   },
                   "scid" => %{
                     "id" => "spacecraft_scid",
                     "name" => "spacecraft[scid]",
                     "type" => "text",
                     "label" => "SCID",
                     "required" => false,
                     "value" => ""
                   },
                   "spacecraft_type_id" => %{
                     "id" => "spacecraft_spacecraft_type_id",
                     "name" => "spacecraft[spacecraft_type_id]",
                     "type" => "select",
                     "label" => "Spacecraft Profile",
                     "required" => false,
                     "value" => ""
                   }
                 },
                 "actions" => %{
                   "submit" => %{
                     "id" => "create-spacecraft-button",
                     "label" => "Create Spacecraft"
                   },
                   "cancel" => %{
                     "id" => "cancel-spacecraft-link",
                     "label" => "Cancel",
                     "href" => "/missions/#{mission.mission_id}/spacecraft"
                   }
                 }
               },
               "profile_options" => %{
                 "options" => [%{"label" => "None", "value" => ""}],
                 "empty" => true,
                 "empty_state" => %{
                   "message" => "No spacecraft profiles defined yet.",
                   "action" => %{
                     "id" => "create-spacecraft-profile-link",
                     "label" => "Create one",
                     "href" =>
                       "/missions/#{mission.mission_id}/spacecraft/profiles/new"
                   },
                   "suffix" =>
                     "to give this spacecraft a reusable interpretation profile."
                 }
               }
             }

      props_json = Jason.encode!(vue.props)

      for excluded <- ["Transport", "Routing", "Contact", "Provider", "Path", "Link"] do
        refute props_json =~ excluded
      end
    end

    test "keeps available profiles in server-provided display-name order" do
      {conn, org, mission} = signed_in_org_and_mission()
      zulu = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Zulu Bus")
      alpha = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Alpha Bus")

      other_mission =
        TestFixtures.persist_mission!(org,
          slug: "secondary",
          display_name: "Secondary Mission"
        )

      _foreign =
        TestFixtures.persist_spacecraft_profile!(other_mission, display_name: "Foreign Bus")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      assert spacecraft_new_vue(view).props["profile_options"]["options"] == [
               %{"label" => "None", "value" => ""},
               %{
                 "label" => "Alpha Bus (v1)",
                 "value" => alpha.spacecraft_type_id
               },
               %{
                 "label" => "Zulu Bus (v1)",
                 "value" => zulu.spacecraft_type_id
               }
             ]

      refute spacecraft_new_vue(view).props["profile_options"]["empty"]
    end
  end

  describe "validate" do
    test "resyncs all current form values from the nested spacecraft payload" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      render_hook(view, "validate", %{
        "spacecraft" => %{
          "display_name" => "Orbital-7",
          "scid" => "7",
          "spacecraft_type_id" => profile.spacecraft_type_id
        }
      })

      fields = spacecraft_new_vue(view).props["form"]["fields"]

      assert %{
               "display_name" => %{"value" => "Orbital-7"},
               "scid" => %{"value" => "7"},
               "spacecraft_type_id" => %{"value" => profile.spacecraft_type_id}
             } = fields
    end
  end

  describe "save" do
    test "creating with valid data trims, persists, and redirects to the show page" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "  Orbital-1  ",
          "scid" => "",
          "spacecraft_type_id" => ""
        }
      })

      {[persisted], {target, _flash}} =
        {Cadence.SpacecraftStore.list_spacecraft(org.organization_id, mission.mission_id),
         assert_redirect(view)}

      assert persisted.display_name == "Orbital-1"
      assert persisted.scid == nil
      assert persisted.spacecraft_type_id == nil

      assert target ==
               "/missions/#{mission.mission_id}/spacecraft/#{persisted.spacecraft_id}"

      assert [] ==
               Cadence.SourceEndpoints.list_source_endpoints(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft_id: persisted.spacecraft_id
               )
    end

    test "creating with SCID persists spacecraft identity and creates a managed source endpoint" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Orbital-42",
          "scid" => " 42 ",
          "spacecraft_type_id" => ""
        }
      })

      {_target, _flash} = assert_redirect(view)

      [persisted] =
        Cadence.SpacecraftStore.list_spacecraft(org.organization_id, mission.mission_id)

      assert persisted.scid == 42

      assert [endpoint] =
               Cadence.SourceEndpoints.list_source_endpoints(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft_id: persisted.spacecraft_id
               )

      assert endpoint.scid == 42
      assert endpoint.metadata["managed_by"] == "spacecraft"
    end

    test "resolves a selected profile to its latest version at save time" do
      {conn, org, mission} = signed_in_org_and_mission()
      profile_v1 = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      profile_v2 = %Cadence.SpacecraftType{profile_v1 | version: 2}

      assert {:ok, _persisted_v2} =
               Cadence.SpacecraftTypeStore.persist_spacecraft_type(
                 org.organization_id,
                 profile_v2
               )

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Profiled Orbiter",
          "scid" => "",
          "spacecraft_type_id" => profile_v1.spacecraft_type_id
        }
      })

      {_target, _flash} = assert_redirect(view)

      assert [persisted] =
               Cadence.SpacecraftStore.list_spacecraft(
                 org.organization_id,
                 mission.mission_id
               )

      assert persisted.spacecraft_type_id == profile_v1.spacecraft_type_id
      assert persisted.spacecraft_type_version == 2
    end

    test "blank display_name shows the exact flash error and stays on the page" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "   ",
          "scid" => "",
          "spacecraft_type_id" => ""
        }
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Display name is required."
             )

      assert spacecraft_new_vue(view).props["form"]["fields"]["display_name"]["value"] ==
               "   "
    end

    test "invalid SCID shows the exact range error without persisting" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Orbital-1024",
          "scid" => "1024",
          "spacecraft_type_id" => ""
        }
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "SCID must be an integer from 0 to 1023."
             )

      assert Cadence.SpacecraftStore.list_spacecraft(org.organization_id, mission.mission_id) == []
    end

    test "unavailable profile selection shows the exact error without persisting" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other Organization", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org,
          slug: "foreign",
          display_name: "Foreign Mission"
        )

      foreign_profile =
        TestFixtures.persist_spacecraft_profile!(other_mission, display_name: "Foreign Bus")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Orphaned Orbiter",
          "scid" => "",
          "spacecraft_type_id" => foreign_profile.spacecraft_type_id
        }
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Selected spacecraft profile is not available."
             )

      assert Cadence.SpacecraftStore.list_spacecraft(org.organization_id, mission.mission_id) == []
    end
  end

  defp spacecraft_new_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-new-component")

    assert vue.component == "SpacecraftNew"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.handlers == %{
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
           }

    vue
  end
end
