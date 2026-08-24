defmodule CadenceWeb.CatalogDatabaseNewLiveTest do
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

  test "renders the new database form" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    assert has_element?(view, "#catalog-database-new-component")

    vue = catalog_database_new_vue(view)

    assert vue.component == "CatalogDatabaseNew"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props == %{
             "page" => %{
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
           }

    assert Map.has_key?(vue.slots, "upload_form")

    upload_form = LazyHTML.query(upload_form_slot(vue), "#catalog-upload-form")

    assert upload_form
    assert ["validate"] = LazyHTML.attribute(upload_form, "phx-change")
    assert ["save"] = LazyHTML.attribute(upload_form, "phx-submit")
  end

  test "shows a friendly banner when no importer matches the file" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-upload-form", :artifact, [
        %{
          name: "mission.bin",
          content: "anything",
          type: "application/octet-stream",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.bin")

    upload_form_text = view |> upload_form_slot() |> LazyHTML.text()

    assert upload_form_text =~ "No importer supports"
    assert upload_form_text =~ "mission.bin"
  end

  test "discovers packaged built-ins through the extension catalog" do
    {conn, _org, mission} = signed_in_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-upload-form", :artifact, [
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

    assert view |> upload_form_slot() |> LazyHTML.text() =~ "Cadence YAML Database"

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
      file_input(view, "#catalog-upload-form", :artifact, [
        %{
          name: "mission.yaml",
          content: yaml,
          type: "application/yaml",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.yaml")

    assert view |> upload_form_slot() |> LazyHTML.text() =~ "Cadence YAML Database"

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

  defp catalog_database_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "catalog-database-new-component")
  end

  defp upload_form_slot(%{slots: slots}) do
    slots
    |> Map.fetch!("upload_form")
    |> LazyHTML.from_fragment()
  end

  defp upload_form_slot(view) do
    view
    |> catalog_database_new_vue()
    |> upload_form_slot()
  end
end
