defmodule CadenceWeb.SpacecraftEditLiveTest do
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
    test "renders the Vue-owned edit form with exact JSON-safe presentation props" do
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

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          scid: 42,
          spacecraft_type_id: alpha.spacecraft_type_id,
          spacecraft_type_version: alpha.version
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      assert has_element?(view, "#spacecraft-edit-component")
      refute has_element?(view, "#spacecraft-edit-page")
      refute has_element?(view, "#spacecraft-edit-form")

      assert spacecraft_edit_vue(view).props == %{
               "page" => %{
                 "id" => "spacecraft-edit-page",
                 "heading" => "Spacecraft Identity",
                 "subtitle" =>
                   "SCID identifies this spacecraft. The optional profile pins its byte-interpretation contract.",
                 "breadcrumbs" => [
                   %{
                     "id" => "spacecraft-edit-mission-link",
                     "label" => "Primary Mission",
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   %{
                     "id" => "spacecraft-edit-list-link",
                     "label" => "Spacecraft",
                     "href" => "/missions/#{mission.mission_id}/spacecraft"
                   },
                   %{
                     "id" => "spacecraft-edit-show-link",
                     "label" => "Nova-1",
                     "href" =>
                       "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                   },
                   %{
                     "id" => "spacecraft-edit-current-breadcrumb",
                     "label" => "Identity",
                     "href" => nil
                   }
                 ]
               },
               "form" => %{
                 "id" => "spacecraft-edit-form",
                 "sections" => %{
                   "identity" => %{
                     "id" => "spacecraft-edit-identity-section",
                     "number" => "01",
                     "title" => "Identity"
                   },
                   "profile" => %{
                     "id" => "spacecraft-edit-profile-section",
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
                     "value" => "Nova-1"
                   },
                   "scid" => %{
                     "id" => "spacecraft_scid",
                     "name" => "spacecraft[scid]",
                     "type" => "text",
                     "label" => "SCID",
                     "required" => false,
                     "value" => "42"
                   },
                   "spacecraft_type_id" => %{
                     "id" => "spacecraft_spacecraft_type_id",
                     "name" => "spacecraft[spacecraft_type_id]",
                     "type" => "select",
                     "label" => "Spacecraft Profile",
                     "required" => false,
                     "value" => alpha.spacecraft_type_id
                   }
                 },
                 "actions" => %{
                   "submit" => %{
                     "id" => "save-spacecraft-identity-button",
                     "label" => "Save Identity"
                   },
                   "cancel" => %{
                     "id" => "cancel-spacecraft-identity-link",
                     "label" => "Cancel",
                     "href" =>
                       "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                   }
                 }
               },
               "profile_options" => %{
                 "options" => [
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
               }
             }
    end

    test "renders the same Vue-owned form through the spacecraft identity route" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
        )

      vue = spacecraft_edit_vue(view)

      assert vue.props["page"]["heading"] == "Spacecraft Identity"
      assert vue.props["form"]["id"] == "spacecraft-edit-form"
      assert vue.props["form"]["fields"]["scid"]["label"] == "SCID"
      assert vue.props["form"]["actions"]["submit"]["label"] == "Save Identity"
    end
  end

  describe "validate" do
    test "resyncs all current form values from the nested spacecraft payload" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      render_hook(view, "validate", %{
        "spacecraft" => %{
          "display_name" => "Nova-1 Prime",
          "scid" => "51",
          "spacecraft_type_id" => profile.spacecraft_type_id
        }
      })

      assert %{
               "display_name" => %{"value" => "Nova-1 Prime"},
               "scid" => %{"value" => "51"},
               "spacecraft_type_id" => %{"value" => profile_id}
             } = spacecraft_edit_vue(view).props["form"]["fields"]

      assert profile_id == profile.spacecraft_type_id
    end
  end

  describe "save" do
    test "updates spacecraft identity and creates the managed source endpoint" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Nova-1 Prime",
          "scid" => "51",
          "spacecraft_type_id" => ""
        }
      })

      {target, flash} = assert_redirect(view)

      assert target == ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
      assert flash["info"] == "Spacecraft updated."

      assert {:ok, updated_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert updated_spacecraft.display_name == "Nova-1 Prime"
      assert updated_spacecraft.scid == 51

      assert [endpoint] =
               Cadence.SourceEndpoints.list_source_endpoints(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft_id: spacecraft.spacecraft_id
               )

      assert endpoint.source_endpoint_id == "spacecraft_runtime:" <> spacecraft.spacecraft_id
      assert endpoint.display_name == "Nova-1 Prime"
      assert endpoint.scid == 51
      assert endpoint.metadata["managed_by"] == "spacecraft"
    end

    test "clearing SCID updates an existing managed source endpoint instead of leaving stale identity" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      assert {:ok, _endpoint} =
               Cadence.SourceEndpoints.ensure_managed_source_endpoint(
                 org.organization_id,
                 spacecraft
               )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Nova-1",
          "scid" => "",
          "spacecraft_type_id" => ""
        }
      })

      {_target, _flash} = assert_redirect(view)

      assert {:ok, updated_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert updated_spacecraft.scid == nil

      assert {:ok, endpoint} =
               Cadence.SourceEndpoints.fetch_source_endpoint(
                 org.organization_id,
                 mission.mission_id,
                 "spacecraft_runtime:" <> spacecraft.spacecraft_id
               )

      assert endpoint.scid == nil
    end

    test "resolves a selected in-scope profile to its latest version at save time" do
      {conn, org, mission} = signed_in_org_and_mission()
      profile_v1 = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      profile_v2 = %Cadence.SpacecraftType{profile_v1 | version: 2}

      assert {:ok, _persisted_v2} =
               Cadence.SpacecraftTypeStore.persist_spacecraft_type(
                 org.organization_id,
                 profile_v2
               )

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Nova-1",
          "scid" => "",
          "spacecraft_type_id" => profile_v1.spacecraft_type_id
        }
      })

      {_target, _flash} = assert_redirect(view)

      assert {:ok, updated_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert updated_spacecraft.spacecraft_type_id == profile_v1.spacecraft_type_id
      assert updated_spacecraft.spacecraft_type_version == 2
    end

    test "rejects a profile outside the authenticated mission scope and preserves values" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      other_mission =
        TestFixtures.persist_mission!(org,
          slug: "secondary",
          display_name: "Secondary Mission"
        )

      foreign_profile =
        TestFixtures.persist_spacecraft_profile!(other_mission, display_name: "Foreign Bus")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Nova-1 Pending",
          "scid" => "43",
          "spacecraft_type_id" => foreign_profile.spacecraft_type_id
        }
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Selected spacecraft profile is not available."
             )

      fields = spacecraft_edit_vue(view).props["form"]["fields"]
      assert fields["display_name"]["value"] == "Nova-1 Pending"
      assert fields["scid"]["value"] == "43"
      assert fields["spacecraft_type_id"]["value"] == foreign_profile.spacecraft_type_id

      assert {:ok, unchanged_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert unchanged_spacecraft.display_name == "Nova-1"
      assert unchanged_spacecraft.scid == 42
      assert unchanged_spacecraft.spacecraft_type_id == nil
    end

    test "blank display name shows the exact error and preserves submitted values" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "   ",
          "scid" => "43",
          "spacecraft_type_id" => ""
        }
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Display name is required."
             )

      fields = spacecraft_edit_vue(view).props["form"]["fields"]
      assert fields["display_name"]["value"] == "   "
      assert fields["scid"]["value"] == "43"

      assert {:ok, unchanged_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert unchanged_spacecraft.display_name == "Nova-1"
      assert unchanged_spacecraft.scid == 42
    end

    test "invalid SCID stays on page with the exact validation message and submitted values" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      render_hook(view, "save", %{
        "spacecraft" => %{
          "display_name" => "Nova-1 Invalid",
          "scid" => "2048",
          "spacecraft_type_id" => ""
        }
      })

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "SCID must be an integer from 0 to 1023."
             )

      fields = spacecraft_edit_vue(view).props["form"]["fields"]
      assert fields["display_name"]["value"] == "Nova-1 Invalid"
      assert fields["scid"]["value"] == "2048"

      assert {:ok, unchanged_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert unchanged_spacecraft.display_name == "Nova-1"
      assert unchanged_spacecraft.scid == 42
    end
  end

  defp spacecraft_edit_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-edit-component")

    assert vue.component == "SpacecraftEdit"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.handlers == %{
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
           }

    vue
  end
end
