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

  test "authenticated mount exposes the catalog database new federated descriptor" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    assert has_element?(view, "#catalog-database-new-component.contents")
    assert has_element?(view, "#catalog-upload-live-form")
    assert has_element?(view, "#catalog-upload-live-form input[type=file]")

    vue = catalog_database_new_vue(view)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "mission_catalog",
             "surface_id" => "catalog_database_new",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => %{"mission_id" => mission.mission_id}
           }
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/mission-test/catalog/new")
  end

  test "shows a friendly banner when no importer matches the file" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-upload-live-form", :artifact, [
        %{
          name: "mission.bin",
          content: "anything",
          type: "application/octet-stream",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.bin")

    render_submit(view, "save", %{"catalog_database" => %{}})

    assert has_element?(view, "#catalog-upload-live-form input[type=file]")

    assert has_element?(
             view,
             "#flash-error[role='alert']",
             "Pick a file with a supported format before uploading."
           )
  end

  test "discovers packaged built-ins through the extension catalog" do
    {conn, _org, mission} = signed_in_org_and_mission()
    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-upload-live-form", :artifact, [
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
      file_input(view, "#catalog-upload-live-form", :artifact, [
        %{
          name: "mission.yaml",
          content: yaml,
          type: "application/yaml",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.yaml")

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
      file_input(view, "#catalog-upload-live-form", :artifact, [
        %{
          name: "mission.bin",
          content: "anything",
          type: "application/octet-stream",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.bin")

    [entry] = uploads.entries
    render_hook(view, "cancel_upload", %{"ref" => entry["ref"]})

    assert has_element?(view, "#catalog-upload-live-form input[type=file]")
  end

  defp catalog_database_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "catalog-database-new-component")
  end
end
