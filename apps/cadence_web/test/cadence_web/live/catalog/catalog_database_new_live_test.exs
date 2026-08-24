defmodule CadenceWeb.CatalogDatabaseNewLiveTest do
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

  test "renders the new database form" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    assert has_element?(view, "#catalog-database-new-component")

    vue = catalog_database_new_vue(view)

    assert vue.component == "CatalogDatabaseNew"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props["page"] == %{
             "id" => "catalog-database-new-page",
             "heading" => "New catalog database",
             "breadcrumbs" => [
               %{
                 "label" => "Primary Mission",
                 "href" => "/missions/#{mission.mission_id}"
               },
               %{
                 "label" => "Catalog",
                 "href" => "/missions/#{mission.mission_id}/catalog"
               },
               %{"label" => "New database", "href" => nil}
             ],
             "cancel" => %{
               "id" => "catalog-database-new-cancel",
               "label" => "Cancel",
               "href" => "/missions/#{mission.mission_id}/catalog"
             }
           }

    form = vue.props["form"]

    assert form["id"] == "catalog-upload-form"
    assert form["name"] == "catalog_database"
    assert form["card"]["title"] == "Create catalog database revision"

    assert form["submit"] == %{
             "class" => "btn btn-primary",
             "id" => nil,
             "label" => "Upload & import"
           }

    assert Enum.map(form["primary_fields"] ++ form["secondary_fields"], fn field ->
             Map.take(field, ["id", "key", "name", "type", "value"])
           end) == [
             %{
               "id" => "catalog_database_name",
               "key" => "name",
               "name" => "catalog_database[name]",
               "type" => "text",
               "value" => ""
             },
             %{
               "id" => "catalog_database_revision_label",
               "key" => "revision_label",
               "name" => "catalog_database[revision_label]",
               "type" => "text",
               "value" => ""
             },
             %{
               "id" => "catalog_database_revision_notes",
               "key" => "revision_notes",
               "name" => "catalog_database[revision_notes]",
               "type" => "textarea",
               "value" => ""
             }
           ]

    upload = vue.props["upload"]

    assert is_binary(upload["ref"])

    assert Map.drop(upload, ["ref"]) == %{
             "accept" => false,
             "auto_upload" => false,
             "entries" => [],
             "errors" => [],
             "max_entries" => 1,
             "max_file_size" => 50 * 1024 * 1024,
             "name" => "artifact"
           }

    assert vue.props["detected_importer"] == %{
             "display_name" => nil,
             "status" => "empty"
           }

    assert vue.props["submit_disabled"] == true

    assert vue.handlers == %{
             "cancel-upload" => JS.push("cancel_upload"),
             "validate" => JS.push("validate")
           }
  end

  test "shows a friendly banner when no importer matches the file" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-database-new-component", :artifact, [
        %{
          name: "mission.bin",
          content: "anything",
          type: "application/octet-stream",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.bin")

    vue = catalog_database_new_vue(view)

    assert vue.props["detected_importer"] == %{
             "display_name" => nil,
             "status" => "unsupported"
           }

    assert [%{"client_name" => "mission.bin", "progress" => 100}] =
             Enum.map(vue.props["upload"]["entries"], &Map.take(&1, ["client_name", "progress"]))

    assert vue.props["submit_disabled"] == true
  end

  test "discovers packaged built-ins through the extension catalog" do
    {conn, _org, mission} = signed_in_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-database-new-component", :artifact, [
        %{
          name: "mission.yaml",
          content: """
          packets:
            - name: HEALTH
              items:
                - name: mode
                  data_type: uint
                  bit_offset: 0
                  bit_size: 8
          commands: []
          """,
          type: "application/yaml",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.yaml")

    vue = catalog_database_new_vue(view)

    assert vue.props["detected_importer"] == %{
             "display_name" => "Cadence YAML Database",
             "status" => "detected"
           }

    assert vue.props["submit_disabled"] == false

    result =
      render_submit(view, "save", %{
        "catalog_database" => %{"name" => "Packaged DB", "revision_label" => "Rev A"}
      })

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert to =~ ~r"/missions/.+/catalog/imports/"
  end

  test "uploading a valid YAML file creates a database revision import and navigates to the run" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    yaml = """
    packets:
      - name: HEALTH
        items:
          - name: mode
            data_type: uint
            bit_offset: 0
            bit_size: 8
    commands: []
    """

    uploads =
      file_input(view, "#catalog-database-new-component", :artifact, [
        %{
          name: "mission.yaml",
          content: yaml,
          type: "application/yaml",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.yaml")

    assert catalog_database_new_vue(view).props["detected_importer"] == %{
             "display_name" => "Cadence YAML Database",
             "status" => "detected"
           }

    result =
      render_submit(view, "save", %{
        "catalog_database" => %{"name" => "Mission DB", "revision_label" => "Rev A"}
      })

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert to =~ ~r"/missions/.+/catalog/imports/"

    assert [database] =
             Cadence.Catalog.list_databases(mission.organization_id, mission.mission_id)

    assert database.name == "Mission DB"
  end

  test "cancels the selected upload through the preserved LiveView event" do
    {conn, _org, mission} = signed_in_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-database-new-component", :artifact, [
        %{
          name: "mission.bin",
          content: "anything",
          type: "application/octet-stream",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.bin")

    [entry] = catalog_database_new_vue(view).props["upload"]["entries"]
    render_hook(view, "cancel_upload", %{"ref" => entry["ref"]})

    vue = catalog_database_new_vue(view)

    assert vue.props["upload"]["entries"] == []
    assert vue.props["detected_importer"]["status"] == "empty"
    assert vue.props["submit_disabled"] == true
  end

  defp catalog_database_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "catalog-database-new-component")
  end
end
