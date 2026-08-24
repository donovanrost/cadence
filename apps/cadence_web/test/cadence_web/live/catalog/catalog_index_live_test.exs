defmodule CadenceWeb.CatalogIndexLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.{CatalogIndexLive, TestFixtures}

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "catalog database list" do
    test "shows empty state with a new-database CTA when no catalog databases exist" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")
      presentation = catalog_index_presentation(view)

      assert presentation["empty_state"]["title"]["text"] =~ "No catalog databases"
      assert presentation["header"]["new_database"]["attrs"]["id"] == "new-database-link"

      assert presentation["header"]["new_database"]["attrs"]["href"] ==
               ~p"/missions/#{mission.mission_id}/catalog/new"

      refute has_element?(view, "#catalog-upload-form")
      refute "Create catalog database revision" in presentation_values(presentation)
    end

    test "renders a + New database CTA in the page header" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _database = TestFixtures.persist_catalog_database!(mission, name: "Existing Catalog")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")
      new_database = catalog_index_presentation(view)["header"]["new_database"]

      assert new_database["attrs"]["id"] == "new-database-link"
      assert new_database["text"] == "New database"

      assert new_database["attrs"]["href"] ==
               ~p"/missions/#{mission.mission_id}/catalog/new"

      refute has_element?(view, "#catalog-upload-form")
    end

    test "lists persisted catalog databases with latest revision and import status" do
      {conn, _org, mission} = signed_in_org_and_mission()
      database = TestFixtures.persist_catalog_database!(mission, name: "Bus Catalog")
      run = TestFixtures.start_catalog_revision_import!(database, revision_label: "FSW 3.7")
      completed = TestFixtures.complete_catalog_import_run!(run)
      _revision = TestFixtures.fetch_catalog_revision_for_run!(completed)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")
      presentation = catalog_index_presentation(view)
      row = catalog_database_row(view, database.catalog_database_id)

      assert row["name"] == "Bus Catalog"
      assert row["latest_revision"]["label"] == "FSW 3.7"
      assert row["latest_import"]["status_label"] == "Completed"
      refute Map.has_key?(row, "family")
      refute "Combined" in presentation_values(presentation)
    end

    test "only shows databases in this mission" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "other", display_name: "Other Mission")

      _mine = TestFixtures.persist_catalog_database!(mission, name: "Mine Catalog")
      _theirs = TestFixtures.persist_catalog_database!(other_mission, name: "Theirs Catalog")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")
      names = Enum.map(catalog_database_rows(view), & &1["name"])

      assert "Mine Catalog" in names
      refute "Theirs Catalog" in names
    end
  end

  describe "sidebar" do
    test "marks Catalog as the active nav item" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      sidebar = LiveVue.Test.get_vue(view, id: "mission-sidebar-navigation")

      catalog =
        Enum.find(
          sidebar.props["presentation"]["navigation"]["items"],
          &(&1["key"] == "catalog")
        )

      assert catalog["icon_class"] ==
               "hero-circle-stack h-4 w-4 opacity-80 flex-shrink-0"

      assert catalog["active"]
      assert catalog["class"] =~ "bg-primary/10"
    end
  end

  describe "pubsub updates" do
    test "re-renders latest run status when a revision import completes" do
      {conn, _org, mission} = signed_in_org_and_mission()
      database = TestFixtures.persist_catalog_database!(mission, name: "Live Catalog")
      run = TestFixtures.start_catalog_revision_import!(database)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert catalog_database_row(view, database.catalog_database_id)["latest_import"][
               "status_label"
             ] == "Running"

      _completed = TestFixtures.complete_catalog_import_run!(run)

      _ = render(view)

      assert catalog_database_row(view, database.catalog_database_id)["latest_import"][
               "status_label"
             ] == "Completed"
    end
  end

  describe "presentation contract" do
    test "projects the complete Catalog Index page through one JSON-safe non-SSR parent" do
      {conn, _org, mission} = signed_in_org_and_mission()

      database =
        TestFixtures.persist_catalog_database!(mission,
          name: "Contract Catalog",
          slug: "contract-catalog"
        )

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert has_element?(view, "#catalog-index-component")

      vue = catalog_index_vue(view)
      assert vue.component == "CatalogIndex"
      assert vue.ssr == false
      assert Map.keys(vue.props) == ["presentation"]

      presentation = vue.props["presentation"]
      assert presentation == Jason.decode!(Jason.encode!(presentation))

      assert presentation["root"] == %{"attrs" => %{"class" => "space-y-6"}}

      assert presentation["header"] == %{
               "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
               "body" => %{
                 "attrs" => %{"class" => "flex items-end justify-between gap-4"}
               },
               "content" => %{"attrs" => %{}},
               "breadcrumbs" => %{
                 "attrs" => %{
                   "aria-label" => "Breadcrumb",
                   "class" =>
                     "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
                 },
                 "mission" => %{
                   "attrs" => %{
                     "class" => "hover:text-primary transition-colors",
                     "data-phx-link" => "redirect",
                     "data-phx-link-state" => "push",
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   "text" => "Primary Mission"
                 },
                 "separator" => %{
                   "attrs" => %{
                     "aria-hidden" => "true",
                     "class" => "text-base-content/20"
                   },
                   "text" => "/"
                 },
                 "current" => %{
                   "attrs" => %{"class" => "text-primary/90"},
                   "text" => "Catalog"
                 }
               },
               "title" => %{
                 "attrs" => %{
                   "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
                 },
                 "text" => "Catalog"
               },
               "subtitle" => %{
                 "attrs" => %{
                   "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
                 },
                 "text" =>
                   "Mission database library. Revisions are imported here; runtime usage is selected later."
               },
               "actions" => %{
                 "attrs" => %{"class" => "flex items-center gap-2"}
               },
               "new_database" => %{
                 "attrs" => %{
                   "class" => "btn btn-primary btn-sm gap-1",
                   "data-phx-link" => "redirect",
                   "data-phx-link-state" => "push",
                   "href" => "/missions/#{mission.mission_id}/catalog/new",
                   "id" => "new-database-link"
                 },
                 "icon" => %{"attrs" => %{"class" => "hero-plus h-4 w-4"}},
                 "text" => "New database"
               }
             }

      assert presentation["empty_state"] == %{
               "visible" => false,
               "list" => %{"attrs" => %{"id" => "catalog-database-list"}},
               "root" => %{
                 "attrs" => %{
                   "class" =>
                     "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
                 }
               },
               "title" => %{
                 "attrs" => %{"class" => "hud-label"},
                 "text" => "No catalog databases yet"
               },
               "description" => %{
                 "attrs" => %{
                   "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
                 },
                 "text" => "Use + New database above to import the first revision."
               }
             }

      assert presentation["card"] == %{
               "visible" => true,
               "root" => %{
                 "attrs" => %{
                   "class" => "card bg-base-200 border border-base-300",
                   "id" => "catalog-database-list"
                 }
               },
               "body" => %{"attrs" => %{"class" => "card-body p-0"}},
               "child_wrapper" => %{
                 "attrs" => %{"id" => "catalog-databases-table-component"}
               },
               "rows" => [
                 %{
                   "id" => "catalog-database-row-#{database.catalog_database_id}",
                   "actions_id" => "#{database.catalog_database_id}-actions",
                   "name" => "Contract Catalog",
                   "slug" => "contract-catalog",
                   "href" =>
                     "/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}",
                   "latest_revision" => nil,
                   "latest_import" => nil
                 }
               ]
             }
    end

    test "raw attrs preserve HEEx nil, false, true, string, and number semantics" do
      attrs =
        CatalogIndexLive.presentation_attrs(%{
          "nil" => nil,
          "false" => false,
          "true" => true,
          "string" => "retained",
          "number" => 7
        })

      assert attrs == %{
               "true" => "",
               "string" => "retained",
               "number" => "7"
             }
    end
  end

  defp catalog_index_presentation(view), do: catalog_index_vue(view).props["presentation"]

  defp catalog_index_vue(view) do
    LiveVue.Test.get_vue(view, id: "catalog-index-component")
  end

  defp catalog_database_rows(view) do
    catalog_index_presentation(view)["card"]["rows"]
  end

  defp catalog_database_row(view, database_id) do
    Enum.find(catalog_database_rows(view), &(&1["id"] == "catalog-database-row-#{database_id}"))
  end

  defp presentation_values(value) when is_map(value) do
    value
    |> Map.values()
    |> Enum.flat_map(&presentation_values/1)
  end

  defp presentation_values(value) when is_list(value),
    do: Enum.flat_map(value, &presentation_values/1)

  defp presentation_values(value), do: [value]
end
