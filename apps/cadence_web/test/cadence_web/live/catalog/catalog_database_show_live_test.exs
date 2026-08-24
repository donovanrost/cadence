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

    assert vue.props == %{
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

    assert vue.handlers == %{
             "toggle-revision-form" => JS.push("toggle_revision_form")
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

    assert initial_vue.slots["revision_form"] == ""

    render_click(view, "toggle_revision_form", %{})

    open_vue = catalog_database_vue(view)
    upload_slot = revision_form_slot(open_vue)
    upload_form = LazyHTML.query(upload_slot, "#catalog-revision-upload-form")

    assert open_vue.props["revision_form_open"] == true
    assert LazyHTML.query(upload_slot, "#catalog-revision-upload-card")
    assert upload_form
    assert LazyHTML.query(upload_slot, "#catalog-revision-upload-submit")
    assert ["validate"] = LazyHTML.attribute(upload_form, "phx-change")
    assert ["save"] = LazyHTML.attribute(upload_form, "phx-submit")
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
    assert LazyHTML.query(revision_form_slot(open_vue), "#catalog-revision-upload-form")

    render_click(view, "toggle_revision_form", %{})

    closed_vue = catalog_database_vue(view)
    assert closed_vue.props["revision_form_open"] == false
    assert closed_vue.slots["revision_form"] == ""
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

  defp revision_form_slot(vue) do
    vue.slots
    |> Map.fetch!("revision_form")
    |> LazyHTML.from_fragment()
  end
end
