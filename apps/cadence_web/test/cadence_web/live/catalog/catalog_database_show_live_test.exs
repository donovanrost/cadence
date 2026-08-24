defmodule CadenceWeb.CatalogDatabaseShowLiveTest do
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

    mission =
      TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")

    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders JSON-safe database details, navigation, revisions, imports, and status semantics" do
    {conn, _org, mission} = signed_in_org_and_mission()

    database =
      TestFixtures.persist_catalog_database!(mission,
        name: "Payload Catalog",
        slug: "payload-catalog",
        description: "Payload telemetry and command definitions."
      )

    run = TestFixtures.start_catalog_revision_import!(database, revision_label: "Payload 7")
    completed = TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(completed)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    assert has_element?(view, "#catalog-database-show-page")
    assert has_element?(view, "#catalog-database-show-component")

    vue = catalog_database_vue(view)

    assert vue.component == "CatalogDatabaseShow"
    assert vue.ssr == false
    assert is_binary(Jason.encode!(vue.props))

    assert Map.take(vue.props, [
             "database",
             "import_runs",
             "navigation",
             "revision_form_open",
             "revisions"
           ]) == %{
             "database" => %{
               "description" => "Payload telemetry and command definitions.",
               "id" => database.catalog_database_id,
               "name" => "Payload Catalog",
               "runtime_usage_summary" => "No runtime bindings yet.",
               "slug" => "payload-catalog"
             },
             "import_runs" => [
               %{
                 "href" =>
                   "/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}",
                 "id" => "catalog-import-run-row-#{completed.import_run_id}",
                 "run_id" => completed.import_run_id,
                 "status" => %{
                   "label" => "Completed",
                   "tone" => "ready",
                   "value" => "completed"
                 }
               }
             ],
             "navigation" => %{
               "catalog" => %{
                 "href" => "/missions/#{mission.mission_id}/catalog",
                 "label" => "Catalog"
               },
               "current" => %{"label" => "Payload Catalog"},
               "mission" => %{
                 "href" => "/missions/#{mission.mission_id}",
                 "label" => "Primary Mission"
               }
             },
             "revision_form_open" => false,
             "revisions" => [
               %{
                 "href" =>
                   "/missions/#{mission.mission_id}/catalog/revisions/#{revision.catalog_revision_id}",
                 "id" => "catalog-revision-row-#{revision.catalog_revision_id}",
                 "label" => "Payload 7",
                 "mission_model_revision_id" => revision.mission_model_revision_id,
                 "number" => revision.revision_number,
                 "revision_id" => revision.catalog_revision_id
               }
             ]
           }

    revision_form = vue.props["revision_form"]

    assert revision_form["id"] == "catalog-revision-upload-form"
    assert revision_form["name"] == "catalog_revision"

    assert revision_form["card"] == %{
             "body_class" => "card-body p-6",
             "class" => "card bg-base-200 border border-base-300",
             "id" => "catalog-revision-upload-card",
             "title" => "Add revision",
             "title_class" => "hud-label"
           }

    assert Enum.map(revision_form["primary_fields"], fn field ->
             Map.take(field, ["id", "key", "name", "type", "value"])
           end) == [
             %{
               "id" => "catalog_revision_revision_label",
               "key" => "revision_label",
               "name" => "catalog_revision[revision_label]",
               "type" => "text",
               "value" => ""
             },
             %{
               "id" => "catalog_revision_revision_notes",
               "key" => "revision_notes",
               "name" => "catalog_revision[revision_notes]",
               "type" => "text",
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
             "toggle-revision-form" => JS.push("toggle_revision_form"),
             "validate" => JS.push("validate")
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

    initial_vue = catalog_database_vue(view)

    assert initial_vue.props["revision_form_open"] == false
    assert initial_vue.props["revisions"] == []
    assert initial_vue.props["import_runs"] == []

    assert initial_vue.props["database"]["description"] ==
             "Mission catalog library entry. Add immutable revisions here, then choose runtime usage separately."

    assert initial_vue.props["revision_form"]["id"] == "catalog-revision-upload-form"

    assert initial_vue.props["revision_form"]["submit"]["id"] ==
             "catalog-revision-upload-submit"

    render_click(view, "toggle_revision_form", %{})

    open_vue = catalog_database_vue(view)

    assert open_vue.props["revision_form_open"] == true
    assert open_vue.props["revision_form"]["card"]["id"] == "catalog-revision-upload-card"

    assert open_vue.props["revision_form"]["submit"] == %{
             "class" => "btn btn-primary",
             "id" => "catalog-revision-upload-submit",
             "label" => "Upload revision"
           }

    assert open_vue.handlers["validate"] == JS.push("validate")
    assert open_vue.handlers["cancel-upload"] == JS.push("cancel_upload")
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

    open_vue = catalog_database_vue(view)
    assert open_vue.props["revision_form_open"] == true

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

    assert [%{"client_name" => "mission.bin"}] =
             catalog_database_vue(view).props["upload"]["entries"]
             |> Enum.map(&Map.take(&1, ["client_name"]))

    render_click(view, "toggle_revision_form", %{})

    closed_vue = catalog_database_vue(view)
    assert closed_vue.props["revision_form_open"] == false
    assert closed_vue.props["upload"]["entries"] == []
    assert closed_vue.props["detected_importer"]["status"] == "empty"
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

    vue = catalog_database_vue(view)

    assert vue.props["detected_importer"] == %{
             "display_name" => "Cadence YAML Database",
             "status" => "detected"
           }

    assert vue.props["submit_disabled"] == false

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

    initial_run = import_run_prop(view, run.import_run_id)

    assert initial_run["status"] == %{
             "label" => "Running",
             "tone" => "info",
             "value" => "running"
           }

    assert catalog_database_vue(view).props["revisions"] == []

    completed = TestFixtures.complete_catalog_import_run!(run)
    send(view.pid, {:import_run_completed, completed})
    _ = render(view)

    completed_run = import_run_prop(view, run.import_run_id)

    assert completed_run["status"] == %{
             "label" => "Completed",
             "tone" => "ready",
             "value" => "completed"
           }

    assert [%{"label" => "Live 2"}] =
             catalog_database_vue(view).props["revisions"]
             |> Enum.map(&Map.take(&1, ["label"]))
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

  defp import_run_prop(view, import_run_id) do
    view
    |> catalog_database_vue()
    |> get_in([:props, "import_runs"])
    |> Enum.find(&(&1["run_id"] == import_run_id))
  end
end
