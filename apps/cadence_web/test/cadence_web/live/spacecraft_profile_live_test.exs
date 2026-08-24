defmodule CadenceWeb.SpacecraftProfileLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore
  alias CadenceWeb.SpacecraftTypeListLive
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test
  alias Phoenix.LiveView.JS

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp spacecraft_profile_list_vue(view) do
    vue = Test.get_vue(view, id: "spacecraft-type-list-page-component")

    assert vue.component == "SpacecraftTypeListPage"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert Map.keys(vue.props) == ["presentation"]
    assert is_binary(Jason.encode!(vue.props))
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue
  end

  defp spacecraft_profile_show_vue(view) do
    vue = Test.get_vue(view, id: "spacecraft-profile-show-component")

    assert vue.component == "SpacecraftTypeShow"
    assert vue.ssr == false
    assert is_binary(Jason.encode!(vue.props))

    vue
  end

  defp spacecraft_profile_new_vue(view) do
    vue = Test.get_vue(view, id: "spacecraft-profile-new-component")

    assert vue.component == "SpacecraftTypeNew"
    assert vue.class == "space-y-6 max-w-2xl"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.handlers == %{
             "save" => JS.push("save"),
             "validate" => JS.push("validate")
           }

    vue
  end

  defp spacecraft_profile_form_values(view) do
    view
    |> spacecraft_profile_new_vue()
    |> Map.fetch!(:props)
    |> get_in(["form", "fields"])
    |> Map.new(fn {name, field} -> {name, field["value"]} end)
  end

  defp valid_spacecraft_profile_params(overrides) do
    Map.merge(
      %{
        "display_name" => "Lab TM/TC",
        "downlink_protocol" => "tm",
        "uplink_protocol" => "tc",
        "frame_size" => "1024",
        "secondary_header_length" => "0",
        "insert_zone_length" => "0",
        "truncated_primary_header" => "false",
        "ocf_length" => "0",
        "applications" => %{"telemetry_decom" => "1"}
      },
      overrides
    )
  end

  describe "profile routes" do
    test "spacecraft management page exposes vehicle and profile cards with scoped actions" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Aurora-1", scid: 42)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert has_element?(view, "#spacecraft-list-component")

      vue = Test.get_vue(view, id: "spacecraft-list-component")
      assert vue.component == "SpacecraftListPage"
      presentation = vue.props["presentation"]

      assert presentation["root"]["attrs"]["id"] == "spacecraft-management-page"

      assert presentation["roster"]["new_spacecraft_href"] ==
               "/missions/#{mission.mission_id}/spacecraft/new"

      assert presentation["profiles"]["new_profile_href"] ==
               "/missions/#{mission.mission_id}/spacecraft/profiles/new"

      assert Enum.any?(
               presentation["roster"]["rows"],
               &(&1["id"] == "spacecraft-#{spacecraft.spacecraft_id}" and
                   &1["display_name"] == spacecraft.display_name)
             )

      assert Enum.any?(
               presentation["profiles"]["rows"],
               &(&1["id"] == "spacecraft-profile-preview-#{profile.spacecraft_type_id}" and
                   &1["display_name"] == profile.display_name)
             )

      page_header = Jason.encode!(presentation["header"])

      refute page_header =~ "New spacecraft"
      refute page_header =~ "New profile"
    end

    test "mission sidebar keeps profiles under the spacecraft area" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      sidebar = Test.get_vue(view, id: "mission-sidebar-navigation")
      navigation = sidebar.props["presentation"]["navigation"]["items"]

      links =
        Enum.flat_map(navigation, fn
          %{"kind" => "link"} = item -> [item]
          %{"kind" => "section", "children" => children} -> children
        end)

      refute Enum.any?(
               links,
               &(&1["attrs"]["href"] ==
                   "/missions/#{mission.mission_id}/spacecraft/profiles")
             )

      assert Enum.any?(links, fn link ->
               link["attrs"]["href"] == "/missions/#{mission.mission_id}/spacecraft" and
                 link["label"] == "Spacecraft"
             end)
    end

    test "renders the server-owned empty state when no profiles are defined" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

      assert has_element?(view, "#spacecraft-type-list-page-component")

      presentation = spacecraft_profile_list_vue(view).props["presentation"]

      assert presentation["root"] == %{
               "attrs" => %{"class" => "space-y-6", "id" => "spacecraft-profiles-page"}
             }

      assert presentation["empty_state"]["title"]["text"] == "No profiles yet"

      assert presentation["header"]["actions"]["new_profile"]["attrs"] == %{
               "class" => "btn btn-primary btn-sm gap-1",
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push",
               "href" => "/missions/#{mission.mission_id}/spacecraft/profiles/new",
               "id" => "new-spacecraft-profile-link"
             }

      assert presentation["card"] == nil
      refute Jason.encode!(presentation) =~ "spacecraft-profiles-list-component"
    end

    test "lists spacecraft profiles using profile vocabulary and JSON-safe row props" do
      {conn, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Aurora Bus",
          downlink_protocol: :aos,
          uplink_protocol: :uslp,
          applications: %{
            "telemetry_decom" => %{},
            "command_dispatch" => %{}
          }
        )

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

      assert has_element?(view, "#spacecraft-type-list-page-component")

      vue = spacecraft_profile_list_vue(view)
      presentation = vue.props["presentation"]

      assert presentation["header"]["actions"]["new_profile"]["attrs"]["href"] ==
               "/missions/#{mission.mission_id}/spacecraft/profiles/new"

      assert presentation["card"]["list_component"] == %{
               "attrs" => %{"id" => "spacecraft-profiles-list-component"}
             }

      assert presentation["header"]["title"]["suffix"]["text"] == "1 defined"

      assert presentation["card"]["rows"] == [
               %{
                 "id" => "spacecraft-profile-#{profile.spacecraft_type_id}",
                 "display_name" => profile.display_name,
                 "version" => "v1",
                 "downlink_protocol" => "AOS",
                 "uplink_protocol" => "USLP",
                 "applications" => "Command Dispatch, Telemetry Decom",
                 "href" =>
                   "/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
               }
             ]

      assert presentation["header"]["title"]["text"] == "Spacecraft Profiles"
      refute Jason.encode!(presentation) =~ "Spacecraft Types"
    end

    test "spacecraft profile list raw attrs preserve HEEx omission boolean string and number semantics" do
      attrs =
        SpacecraftTypeListLive.presentation_attrs(%{
          "nil" => nil,
          "false" => false,
          "true" => true,
          "empty" => "",
          "string" => "retained",
          "number" => 7
        })

      assert attrs == %{
               "true" => "",
               "empty" => "",
               "string" => "retained",
               "number" => "7"
             }
    end

    test "lists only profiles belonging to the current mission and organization" do
      {conn, org, mission} = signed_in_org_and_mission()
      mine = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Mine")

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      same_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_mission, display_name: "Same Org Foreign")

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_org_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      other_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_org_mission,
          display_name: "Other Org Foreign"
        )

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles")

      rows = spacecraft_profile_list_vue(view).props["presentation"]["card"]["rows"]

      assert Enum.map(rows, & &1["id"]) == ["spacecraft-profile-#{mine.spacecraft_type_id}"]

      refute Enum.any?(
               rows,
               &(&1["id"] == "spacecraft-profile-#{same_org_foreign.spacecraft_type_id}")
             )

      refute Enum.any?(
               rows,
               &(&1["id"] == "spacecraft-profile-#{other_org_foreign.spacecraft_type_id}")
             )
    end

    test "creates a spacecraft profile and redirects to the profile show page" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org,
          slug: "secondary",
          display_name: "Secondary Mission"
        )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles/new")

      assert has_element?(view, "#spacecraft-profile-new-component")
      refute has_element?(view, "#spacecraft-profile-new-page")
      refute has_element?(view, "#spacecraft-profile-form")

      vue = spacecraft_profile_new_vue(view)

      assert vue.props == %{
               "page" => %{
                 "id" => "spacecraft-profile-new-page",
                 "title" => "New Spacecraft Profile",
                 "subtitle" =>
                   "Captures the byte-interpretation contract shared across spacecraft of the same kind — downlink and uplink protocols, frame parameters, and which platform applications run.",
                 "breadcrumbs" => [
                   %{
                     "label" => mission.display_name,
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   %{
                     "label" => "Spacecraft",
                     "href" => "/missions/#{mission.mission_id}/spacecraft"
                   },
                   %{
                     "label" => "Spacecraft Profiles",
                     "href" => "/missions/#{mission.mission_id}/spacecraft/profiles"
                   },
                   %{"label" => "New Spacecraft Profile", "href" => nil}
                 ]
               },
               "form" => %{
                 "id" => "spacecraft-profile-form",
                 "sections" => %{
                   "identity" => %{
                     "id" => "spacecraft-profile-identity-section",
                     "number" => "01",
                     "title" => "Identity",
                     "description" => nil
                   },
                   "protocols" => %{
                     "id" => "spacecraft-profile-protocols-section",
                     "number" => "02",
                     "title" => "Data Link Protocols",
                     "description" => nil
                   },
                   "frame_parameters" => %{
                     "id" => "spacecraft-profile-frame-parameters-section",
                     "number" => "03",
                     "title" => "Downlink Frame Parameters",
                     "description" =>
                       "How the spacecraft frames the bytes it transmits. Fields adapt to the selected downlink protocol."
                   },
                   "applications" => %{
                     "id" => "spacecraft-profile-applications-section",
                     "number" => "04",
                     "title" => "Applications",
                     "description" =>
                       "Which platform applications run for spacecraft using this profile. Per-application configuration is set on each spacecraft."
                   }
                 },
                 "fields" => %{
                   "display_name" => %{
                     "id" => "spacecraft_type_display_name",
                     "name" => "spacecraft_type[display_name]",
                     "type" => "text",
                     "label" => "Display Name",
                     "required" => true,
                     "value" => ""
                   },
                   "downlink_protocol" => %{
                     "id" => "spacecraft_type_downlink_protocol",
                     "name" => "spacecraft_type[downlink_protocol]",
                     "type" => "select",
                     "label" => "Downlink Protocol",
                     "required" => true,
                     "value" => "tm"
                   },
                   "uplink_protocol" => %{
                     "id" => "spacecraft_type_uplink_protocol",
                     "name" => "spacecraft_type[uplink_protocol]",
                     "type" => "select",
                     "label" => "Uplink Protocol",
                     "required" => true,
                     "value" => "tc"
                   },
                   "frame_size" => %{
                     "id" => "spacecraft_type_frame_size",
                     "name" => "spacecraft_type[frame_size]",
                     "type" => "number",
                     "label" => "Transfer Frame Size (bytes)",
                     "required" => true,
                     "value" => ""
                   },
                   "secondary_header_length" => %{
                     "id" => "spacecraft_type_secondary_header_length",
                     "name" => "spacecraft_type[secondary_header_length]",
                     "type" => "number",
                     "label" => "Secondary Header Length (bytes, 0 if absent)",
                     "required" => false,
                     "value" => "0"
                   },
                   "insert_zone_length" => %{
                     "id" => "spacecraft_type_insert_zone_length",
                     "name" => "spacecraft_type[insert_zone_length]",
                     "type" => "number",
                     "label" => "Insert Zone Length (bytes, 0 if absent)",
                     "required" => false,
                     "value" => "0"
                   },
                   "truncated_primary_header" => %{
                     "id" => "spacecraft_type_truncated_primary_header",
                     "name" => "spacecraft_type[truncated_primary_header]",
                     "type" => "select",
                     "label" => "Truncated Primary Header",
                     "required" => false,
                     "value" => "false"
                   },
                   "ocf_length" => %{
                     "id" => "spacecraft_type_ocf_length",
                     "name" => "spacecraft_type[ocf_length]",
                     "type" => "select",
                     "label" => "Operational Control Field",
                     "required" => false,
                     "value" => "0"
                   },
                   "applications" => %{
                     "id" => "spacecraft-profile-application-options",
                     "name" => "spacecraft_type[applications]",
                     "value" => %{}
                   }
                 },
                 "actions" => %{
                   "submit" => %{
                     "id" => "create-spacecraft-profile-button",
                     "label" => "Create Profile"
                   },
                   "cancel" => %{
                     "id" => "cancel-spacecraft-profile-link",
                     "label" => "Cancel",
                     "href" => "/missions/#{mission.mission_id}/spacecraft/profiles"
                   }
                 }
               },
               "options" => %{
                 "downlink_protocols" => [
                   %{"label" => "TM", "value" => "tm"},
                   %{"label" => "AOS", "value" => "aos"},
                   %{"label" => "USLP", "value" => "uslp"}
                 ],
                 "uplink_protocols" => [
                   %{"label" => "TC", "value" => "tc"},
                   %{"label" => "USLP", "value" => "uslp"}
                 ],
                 "truncated_primary_headers" => [
                   %{"label" => "No", "value" => "false"},
                   %{"label" => "Yes", "value" => "true"}
                 ],
                 "operational_control_fields" => [
                   %{"label" => "Not present", "value" => "0"},
                   %{"label" => "Present (4 bytes)", "value" => "4"}
                 ],
                 "frame_fields" => %{
                   "secondary_header_length" => ["tm"],
                   "insert_zone_length" => ["aos"],
                   "truncated_primary_header" => ["uslp"]
                 }
               },
               "applications" => [
                 %{
                   "id" => "spacecraft-profile-application-telemetry_decom",
                   "key" => "telemetry_decom",
                   "name" => "spacecraft_type[applications][telemetry_decom]",
                   "value" => "1",
                   "label" => "Telemetry Decom",
                   "description" =>
                     "Bind packet fields and decode selected inputs into named telemetry points.",
                   "available" => true,
                   "availability_label" => nil
                 }
               ]
             }

      assert Enum.any?(
               vue.props["applications"],
               &(&1["id"] == "spacecraft-profile-application-telemetry_decom")
             )

      refute Enum.any?(vue.props["applications"], &(&1["key"] == "cfdp"))

      render_hook(view, "save", %{
        "spacecraft_type" =>
          valid_spacecraft_profile_params(%{"mission_id" => other_mission.mission_id})
      })

      {target, _flash} = assert_redirect(view)

      assert target =~ "/missions/#{mission.mission_id}/spacecraft/profiles/"

      [persisted] =
        SpacecraftTypeStore.list_spacecraft_types(org.organization_id, mission.mission_id)

      assert persisted.display_name == "Lab TM/TC"
      assert persisted.mission_id == mission.mission_id
      assert persisted.downlink_protocol == :tm
      assert persisted.uplink_protocol == :tc
      assert persisted.packet_protocol == :space_packet

      assert persisted.frame_parameters == %{
               "frame_size" => 1024,
               "secondary_header_length" => 0,
               "ocf_length" => 0
             }

      assert persisted.applications == %{"telemetry_decom" => %{}}
      assert target =~ persisted.spacecraft_type_id

      assert SpacecraftTypeStore.list_spacecraft_types(
               org.organization_id,
               other_mission.mission_id
             ) == []
    end

    test "resyncs every conditional frame value and application selection from validate hooks" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles/new")

      aos_params =
        valid_spacecraft_profile_params(%{
          "display_name" => "AOS Lab",
          "downlink_protocol" => "aos",
          "uplink_protocol" => "uslp",
          "frame_size" => "2048",
          "secondary_header_length" => "7",
          "insert_zone_length" => "16",
          "truncated_primary_header" => "true",
          "ocf_length" => "4"
        })

      render_hook(view, "validate", %{"spacecraft_type" => aos_params})
      assert spacecraft_profile_form_values(view) == aos_params

      uslp_params =
        valid_spacecraft_profile_params(%{
          "display_name" => "USLP Lab",
          "downlink_protocol" => "uslp",
          "frame_size" => "4096",
          "secondary_header_length" => "9",
          "insert_zone_length" => "24",
          "truncated_primary_header" => "false",
          "applications" => %{}
        })

      render_hook(view, "validate", %{"spacecraft_type" => uslp_params})
      assert spacecraft_profile_form_values(view) == uslp_params
    end

    test "persists active AOS and USLP frame branches and filters unsupported applications" do
      {conn, org, mission} = signed_in_org_and_mission()

      cases = [
        {"AOS Lab", "aos", :aos,
         %{
           "frame_size" => "2048",
           "secondary_header_length" => "99",
           "insert_zone_length" => "16",
           "truncated_primary_header" => "true",
           "ocf_length" => "4"
         }, %{"frame_size" => 2048, "insert_zone_length" => 16, "ocf_length" => 4}},
        {"USLP Lab", "uslp", :uslp,
         %{
           "frame_size" => "4096",
           "secondary_header_length" => "99",
           "insert_zone_length" => "99",
           "truncated_primary_header" => "true",
           "ocf_length" => "0"
         }, %{"frame_size" => 4096, "truncated_primary_header" => true, "ocf_length" => 0}}
      ]

      for {display_name, protocol, expected_protocol, frame_values, expected_frame_parameters} <-
            cases do
        {:ok, view, _html} =
          live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles/new")

        params =
          valid_spacecraft_profile_params(
            Map.merge(frame_values, %{
              "display_name" => display_name,
              "downlink_protocol" => protocol,
              "applications" => %{
                "telemetry_decom" => "1",
                "cfdp" => "1",
                "unknown_application" => "1"
              }
            })
          )

        render_hook(view, "save", %{"spacecraft_type" => params})
        {_target, _flash} = assert_redirect(view)

        assert %SpacecraftType{} =
                 persisted =
                 SpacecraftTypeStore.list_spacecraft_types(
                   org.organization_id,
                   mission.mission_id
                 )
                 |> Enum.find(&(&1.display_name == display_name))

        assert persisted.downlink_protocol == expected_protocol
        assert persisted.frame_parameters == expected_frame_parameters
        assert persisted.applications == %{"telemetry_decom" => %{}}
      end
    end

    test "preserves exact create errors and submitted form values without persistence" do
      {conn, org, mission} = signed_in_org_and_mission()

      cases = [
        {%{"display_name" => "   "}, "Display name is required."},
        {%{"downlink_protocol" => "invalid"}, "Downlink protocol is invalid."},
        {%{"uplink_protocol" => "invalid"}, "Uplink protocol is invalid."},
        {%{"frame_size" => "0"}, "Frame size must be a positive integer."},
        {%{"secondary_header_length" => "-1"},
         "Secondary header length must be a non-negative integer."},
        {%{"downlink_protocol" => "aos", "insert_zone_length" => "-1"},
         "Insert zone length must be a non-negative integer."},
        {%{"downlink_protocol" => "uslp", "truncated_primary_header" => "sometimes"},
         "Truncated primary header must be Yes or No."},
        {%{"ocf_length" => "2"}, "Operational Control Field must be 0 (absent) or 4 (present)."}
      ]

      for {overrides, message} <- cases do
        {:ok, view, _html} =
          live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/profiles/new")

        params = valid_spacecraft_profile_params(overrides)
        render_hook(view, "save", %{"spacecraft_type" => params})

        assert has_element?(view, "#flash-error[role='alert']", message)
        assert spacecraft_profile_form_values(view) == params
      end

      assert SpacecraftTypeStore.list_spacecraft_types(
               org.organization_id,
               mission.mission_id
             ) == []
    end

    test "shows a spacecraft profile" do
      {conn, _org, mission} = signed_in_org_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
        )

      assert has_element?(view, "#spacecraft-profile-show-page")
      assert has_element?(view, "#spacecraft-profile-show-component")

      vue = spacecraft_profile_show_vue(view)

      assert vue.props["navigation"]["profiles"]["href"] ==
               "/missions/#{mission.mission_id}/spacecraft/profiles"

      assert vue.props["profile"]["display_name"] == "Aurora Bus"
      assert vue.props["labels"]["byte_interpretation"] == "Byte Interpretation"
      refute inspect(vue.props) =~ "Spacecraft Type"
    end

    test "provides exact JSON-safe profile detail and version history props" do
      {conn, org, mission} = signed_in_org_and_mission()

      %SpacecraftType{} =
        profile_v1 =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Aurora Bus",
          downlink_protocol: :aos,
          uplink_protocol: :tc,
          frame_parameters: %{"frame_size" => 1024, "ocf_length" => 0},
          applications: %{"telemetry_decom" => %{}}
        )

      profile_v2 = %SpacecraftType{
        profile_v1
        | version: 2,
          downlink_protocol: :uslp,
          uplink_protocol: :uslp,
          frame_parameters: %{
            "frame_size" => 2048,
            "ocf_length" => 0,
            "secondary_header_enabled" => true,
            "truncated_primary_header" => false
          },
          applications: %{
            "command_dispatch" => %{},
            "telemetry_decom" => %{}
          }
      }

      assert {:ok, persisted_v2} =
               SpacecraftTypeStore.persist_spacecraft_type(
                 org.organization_id,
                 profile_v2
               )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile_v1.spacecraft_type_id}"
        )

      vue = spacecraft_profile_show_vue(view)

      assert vue.props == %{
               "labels" => %{
                 "applications" => "Applications",
                 "byte_interpretation" => "Byte Interpretation",
                 "downlink" => "Downlink",
                 "downlink_protocol" => "Downlink Protocol",
                 "frame_parameters" => "Frame Parameters",
                 "lifecycle" => "Lifecycle",
                 "no_applications" => "No applications enabled.",
                 "packet_protocol" => "Packet Protocol",
                 "uplink" => "Uplink",
                 "uplink_protocol" => "Uplink Protocol",
                 "version" => "Version",
                 "version_history" => "Version History"
               },
               "navigation" => %{
                 "current" => %{"label" => "Aurora Bus"},
                 "mission" => %{
                   "href" => "/missions/#{mission.mission_id}",
                   "label" => "Primary Mission"
                 },
                 "profiles" => %{
                   "href" => "/missions/#{mission.mission_id}/spacecraft/profiles",
                   "label" => "Spacecraft Profiles"
                 },
                 "spacecraft" => %{
                   "href" => "/missions/#{mission.mission_id}/spacecraft",
                   "label" => "Spacecraft"
                 }
               },
               "profile" => %{
                 "applications" => [
                   %{
                     "id" => "spacecraft-profile-application-command_dispatch",
                     "label" => "Command Dispatch"
                   },
                   %{
                     "id" => "spacecraft-profile-application-telemetry_decom",
                     "label" => "Telemetry Decom"
                   }
                 ],
                 "display_name" => "Aurora Bus",
                 "downlink_protocol" => "USLP",
                 "frame_parameters" => [
                   %{
                     "id" => "spacecraft-profile-frame-parameter-frame_size",
                     "label" => "Frame Size",
                     "value" => "2048"
                   },
                   %{
                     "id" => "spacecraft-profile-frame-parameter-ocf_length",
                     "label" => "Ocf Length",
                     "value" => "0"
                   },
                   %{
                     "id" => "spacecraft-profile-frame-parameter-secondary_header_enabled",
                     "label" => "Secondary Header Enabled",
                     "value" => "yes"
                   },
                   %{
                     "id" => "spacecraft-profile-frame-parameter-truncated_primary_header",
                     "label" => "Truncated Primary Header",
                     "value" => "no"
                   }
                 ],
                 "id" => "spacecraft-profile-#{profile_v1.spacecraft_type_id}",
                 "lifecycle" => "active",
                 "packet_protocol" => "space_packet",
                 "profile_id" => profile_v1.spacecraft_type_id,
                 "uplink_protocol" => "USLP",
                 "version" => "v2"
               },
               "versions" => [
                 %{
                   "downlink_protocol" => "USLP",
                   "id" => "spacecraft-profile-version-#{profile_v1.spacecraft_type_id}-2",
                   "lifecycle" => "active",
                   "uplink_protocol" => "USLP",
                   "version" => "v2"
                 },
                 %{
                   "downlink_protocol" => "AOS",
                   "id" => "spacecraft-profile-version-#{profile_v1.spacecraft_type_id}-1",
                   "lifecycle" => "active",
                   "uplink_protocol" => "TC",
                   "version" => "v1"
                 }
               ]
             }

      assert persisted_v2.spacecraft_type_id == profile_v1.spacecraft_type_id
    end

    test "preserves empty frame-parameter and application presentation behavior" do
      {conn, _org, mission} = signed_in_org_and_mission()

      profile =
        TestFixtures.persist_spacecraft_profile!(mission,
          display_name: "Minimal Bus",
          frame_parameters: %{},
          applications: %{}
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
        )

      props = spacecraft_profile_show_vue(view).props

      assert props["profile"]["frame_parameters"] == []
      assert props["profile"]["applications"] == []
      assert props["labels"]["no_applications"] == "No applications enabled."
      assert [%{"version" => "v1"}] = Enum.map(props["versions"], &Map.take(&1, ["version"]))
    end

    test "missing profile redirects to the scoped profile list with the existing error" do
      {conn, _org, mission} = signed_in_org_and_mission()

      assert {:error,
              {:live_redirect,
               %{
                 to: to,
                 flash: %{"error" => "Spacecraft profile not found."}
               }}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/profiles/missing-profile"
               )

      assert to == ~p"/missions/#{mission.mission_id}/spacecraft/profiles"
    end

    test "does not expose profile details outside the current mission or organization scope" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

      same_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_mission, display_name: "Same Org Foreign")

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")
      other_org_mission = TestFixtures.persist_mission!(other_org, slug: "remote")

      other_org_foreign =
        TestFixtures.persist_spacecraft_profile!(other_org_mission,
          display_name: "Other Org Foreign"
        )

      for foreign_profile <- [same_org_foreign, other_org_foreign] do
        assert {:error,
                {:live_redirect,
                 %{
                   to: to,
                   flash: %{"error" => "Spacecraft profile not found."}
                 }}} =
                 live(
                   conn,
                   ~p"/missions/#{mission.mission_id}/spacecraft/profiles/#{foreign_profile.spacecraft_type_id}"
                 )

        assert to == ~p"/missions/#{mission.mission_id}/spacecraft/profiles"
      end
    end

    test "unauthenticated profile detail requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(
                 conn,
                 ~p"/missions/mission-test/spacecraft/profiles/spacecraft-profile-test"
               )
    end
  end
end
