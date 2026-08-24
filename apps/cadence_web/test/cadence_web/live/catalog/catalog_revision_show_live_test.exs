defmodule CadenceWeb.CatalogRevisionShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog
  alias Cadence.Catalog.RevisionRow
  alias Cadence.MissionModels
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")

    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders exact JSON-safe revision, provenance, runtime, and mission model props" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Bus Catalog")
    run = TestFixtures.start_catalog_revision_import!(database, revision_label: "FSW 3.7")
    completed = TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(completed)

    assert {:ok, artifact} =
             Catalog.fetch_artifact(
               mission.organization_id,
               mission.mission_id,
               revision.artifact_id
             )

    assert {:ok, mission_model} =
             MissionModels.fetch_revision(
               mission.organization_id,
               mission.mission_id,
               revision.mission_model_revision_id
             )

    assert {:ok, runtime_plans} =
             MissionModels.fetch_runtime_plans(
               mission.organization_id,
               mission.mission_id,
               revision.mission_model_revision_id
             )

    ready_plan_count =
      Enum.count(runtime_plans, fn {_target, plan} -> plan.status == :ready end)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
      )

    assert has_element?(view, "#catalog-revision-show-page")
    assert has_element?(view, "#catalog-revision-show-component")

    vue = catalog_revision_vue(view)

    assert vue.component == "CatalogRevisionShow"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert vue.props == %{
             "mission_model" => %{
               "available" => true,
               "empty_message" => "Mission Model unavailable.",
               "id" => "catalog-mission-model",
               "rows" => [
                 %{
                   "href" => nil,
                   "label" => "Revision",
                   "style" => "hash",
                   "value" => revision.mission_model_revision_id
                 },
                 %{
                   "href" => nil,
                   "label" => "Declarations",
                   "style" => "default",
                   "value" => map_size(mission_model.declarations)
                 },
                 %{
                   "href" => nil,
                   "label" => "Space systems",
                   "style" => "default",
                   "value" => map_size(mission_model.space_systems)
                 },
                 %{
                   "href" => nil,
                   "label" => "Ready plans",
                   "style" => "default",
                   "value" => ready_plan_count
                 }
               ],
               "title" => "Mission Model"
             },
             "navigation" => %{
               "breadcrumbs" => [
                 %{
                   "href" => "/missions/#{mission.mission_id}",
                   "label" => "Primary Mission"
                 },
                 %{
                   "href" => "/missions/#{mission.mission_id}/catalog",
                   "label" => "Catalog"
                 },
                 %{
                   "href" =>
                     "/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}",
                   "label" => "Bus Catalog"
                 },
                 %{"href" => nil, "label" => "FSW 3.7"}
               ]
             },
             "provenance" => %{
               "id" => "catalog-revision-provenance",
               "rows" => [
                 %{
                   "href" => nil,
                   "label" => "Database",
                   "style" => "default",
                   "value" => "Bus Catalog"
                 },
                 %{
                   "href" =>
                     "/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}",
                   "label" => "Artifact",
                   "style" => "default",
                   "value" => artifact.artifact_name
                 },
                 %{
                   "href" =>
                     "/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}",
                   "label" => "Import run",
                   "style" => "mono",
                   "value" => completed.import_run_id
                 },
                 %{
                   "href" => nil,
                   "label" => "Content SHA-256",
                   "style" => "hash",
                   "value" => revision.content_sha256
                 }
               ],
               "title" => "Revision provenance"
             },
             "revision" => %{
               "number_label" => "Revision #{revision.revision_number}",
               "title" => "FSW 3.7"
             },
             "runtime_usage" => %{
               "action" => %{
                 "disabled" => true,
                 "id" => "catalog-revision-runtime-action",
                 "label" => "Use this revision in runtime"
               },
               "id" => "catalog-revision-runtime-usage",
               "summary" => "No runtime bindings yet.",
               "summary_id" => "catalog-runtime-usage-summary",
               "title" => "Runtime usage"
             }
           }
  end

  test "missing revision redirects to catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error,
            {:redirect,
             %{
               to: to,
               flash: %{"error" => "Catalog revision not found."}
             }}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/revisions/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end

  test "preserves unavailable related records and Mission Model empty state" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Sparse Catalog")
    run = TestFixtures.start_catalog_revision_import!(database, revision_label: "Sparse 1")
    completed = TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(completed)

    revision.catalog_revision_id
    |> then(&Repo.get!(RevisionRow, &1))
    |> Ecto.Changeset.change(
      catalog_database_id: "missing-database",
      artifact_id: "missing-artifact",
      import_run_id: "missing-import-run",
      mission_model_revision_id: "missing-mission-model"
    )
    |> Repo.update!()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
      )

    props = catalog_revision_vue(view).props
    assert props == Jason.decode!(Jason.encode!(props))

    assert props["navigation"] == %{
             "breadcrumbs" => [
               %{
                 "href" => "/missions/#{mission.mission_id}",
                 "label" => "Primary Mission"
               },
               %{
                 "href" => "/missions/#{mission.mission_id}/catalog",
                 "label" => "Catalog"
               },
               %{"href" => nil, "label" => "Sparse 1"}
             ]
           }

    assert props["provenance"]["rows"] == [
             %{
               "href" => nil,
               "label" => "Database",
               "style" => "default",
               "value" => nil
             },
             %{
               "href" => nil,
               "label" => "Artifact",
               "style" => "default",
               "value" => nil
             },
             %{
               "href" => nil,
               "label" => "Import run",
               "style" => "mono",
               "value" => nil
             },
             %{
               "href" => nil,
               "label" => "Content SHA-256",
               "style" => "hash",
               "value" => revision.content_sha256
             }
           ]

    assert props["mission_model"] == %{
             "available" => false,
             "empty_message" => "Mission Model unavailable.",
             "id" => "catalog-mission-model",
             "rows" => [],
             "title" => "Mission Model"
           }
  end

  test "does not expose revisions outside the current organization or mission scope" do
    {conn, org, mission} = signed_in_org_and_mission()

    other_mission =
      TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

    other_mission_revision = persist_revision!(other_mission, "Secondary 1")

    other_org = TestFixtures.persist_org!(display_name: "Remote Org", slug: "remote-org")
    remote_mission = TestFixtures.persist_mission!(other_org, slug: "remote")
    other_org_revision = persist_revision!(remote_mission, "Remote 1")

    for foreign_revision <- [other_mission_revision, other_org_revision] do
      assert {:error,
              {:redirect,
               %{
                 to: to,
                 flash: %{"error" => "Catalog revision not found."}
               }}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/catalog/revisions/#{foreign_revision.catalog_revision_id}"
               )

      assert to == ~p"/missions/#{mission.mission_id}/catalog"
    end
  end

  test "unauthenticated requests redirect to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(
               conn,
               ~p"/missions/mission-test/catalog/revisions/catalog-revision-test"
             )
  end

  defp catalog_revision_vue(view) do
    LiveVue.Test.get_vue(view, id: "catalog-revision-show-component")
  end

  defp persist_revision!(mission, revision_label) do
    database = TestFixtures.persist_catalog_database!(mission)
    run = TestFixtures.start_catalog_revision_import!(database, revision_label: revision_label)
    completed = TestFixtures.complete_catalog_import_run!(run)
    TestFixtures.fetch_catalog_revision_for_run!(completed)
  end
end
