defmodule CadenceWeb.CatalogDatabaseShowLiveTest do
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

    mission =
      TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")

    {TestFixtures.member_conn(user), org, mission}
  end

  test "authenticated mount exposes the catalog database show federated descriptor" do
    {conn, _org, mission} = signed_in_org_and_mission()

    database =
      TestFixtures.persist_catalog_database!(mission,
        name: "Payload Catalog",
        slug: "payload-catalog",
        description: "Payload telemetry and command definitions."
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    assert has_element?(view, "#catalog-database-show-page")
    assert has_element?(view, "#catalog-database-show-component")

    vue = catalog_database_vue(view)

    assert vue.component == "FederatedFullPageSurface"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "mission_catalog",
             "surface_id" => "catalog_database_show",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => %{
               "mission_id" => mission.mission_id,
               "catalog_database_id" => database.catalog_database_id
             }
           }
  end

  test "missing database redirects to catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/databases/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end

  test "add-revision form is hidden by default and shown on toggle" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    refute has_element?(view, "#catalog-revision-upload-live-form")

    render_click(view, "toggle_revision_form", %{})

    assert has_element?(view, "#catalog-revision-upload-live-form")
    assert has_element?(view, "#catalog-revision-upload-live-form input[type=file]")
  end

  test "cancelling the add-revision reveal hides the form" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    render_click(view, "toggle_revision_form", %{})

    assert has_element?(view, "#catalog-revision-upload-live-form")

    uploads =
      file_input(view, "#catalog-revision-upload-live-form", :artifact, [
        %{
          name: "mission.bin",
          content: "anything",
          type: "application/octet-stream",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.bin")

    render_click(view, "toggle_revision_form", %{})

    refute has_element?(view, "#catalog-revision-upload-live-form")
  end

  test "uploads a supported file as a new revision and navigates to the import run" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    render_click(view, "toggle_revision_form", %{})

    uploads =
      file_input(view, "#catalog-revision-upload-live-form", :artifact, [
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
        "catalog_revision" => %{
          "revision_label" => "Payload 2",
          "revision_notes" => "Updated payload definitions"
        }
      })

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert to =~ ~r"/missions/.+/catalog/imports/"

    assert [_run] =
             Cadence.Catalog.list_import_runs(
               mission.organization_id,
               mission.mission_id,
               catalog_database_id: database.catalog_database_id
             )
  end

  test "refreshes matching import and revision DTOs when an import completes" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Live Catalog")
    run = TestFixtures.start_catalog_revision_import!(database, revision_label: "Live 2")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    assert has_element?(view, "#catalog-database-show-component")

    completed = TestFixtures.complete_catalog_import_run!(run)
    send(view.pid, {:import_run_completed, completed})
    _ = render(view)

    assert has_element?(view, "#catalog-database-show-component")

    assert [_revision] =
             Cadence.Catalog.list_revisions(
               mission.organization_id,
               mission.mission_id,
               database.catalog_database_id
             )
  end

  test "does not expose a catalog database outside the current organization scope" do
    {conn, _org, mission} = signed_in_org_and_mission()
    other_org = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_org, slug: "other")
    other_database = TestFixtures.persist_catalog_database!(other_mission, name: "Other Catalog")

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/catalog/databases/#{other_database.catalog_database_id}"
             )

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    mission_id = "mission-test"
    database_id = "catalog-database-test"

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(
               conn,
               ~p"/missions/#{mission_id}/catalog/databases/#{database_id}"
             )
  end

  defp catalog_database_vue(view) do
    LiveVue.Test.get_vue(view, id: "catalog-database-show-component")
  end
end
