defmodule CadenceWeb.CatalogIndexLiveTest do
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

  describe "catalog database list" do
    test "shows empty state with a new-database CTA when no catalog databases exist" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "No catalog databases"
      assert html =~ "id=\"new-database-link\""
      assert html =~ ~p"/missions/#{mission.mission_id}/catalog/new"
      refute html =~ "catalog-upload-form"
      refute html =~ "Create catalog database revision"
    end

    test "renders a + New database CTA in the page header" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _database = TestFixtures.persist_catalog_database!(mission, name: "Existing Catalog")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "id=\"new-database-link\""
      assert html =~ "New database"
      assert html =~ ~p"/missions/#{mission.mission_id}/catalog/new"
      refute html =~ "catalog-upload-form"
    end

    test "lists persisted catalog databases with latest revision and import status" do
      {conn, _org, mission} = signed_in_org_and_mission()
      database = TestFixtures.persist_catalog_database!(mission, name: "Bus Catalog")
      run = TestFixtures.start_catalog_revision_import!(database, revision_label: "FSW 3.7")
      completed = TestFixtures.complete_catalog_import_run!(run)
      _revision = TestFixtures.fetch_catalog_revision_for_run!(completed)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "Bus Catalog"
      assert html =~ "FSW 3.7"
      assert html =~ "Completed"
      refute html =~ ">Family<"
      refute html =~ "Combined"
    end

    test "only shows databases in this mission" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "other", display_name: "Other Mission")

      _mine = TestFixtures.persist_catalog_database!(mission, name: "Mine Catalog")
      _theirs = TestFixtures.persist_catalog_database!(other_mission, name: "Theirs Catalog")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "Mine Catalog"
      refute html =~ "Theirs Catalog"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/any/catalog")
    end
  end

  describe "sidebar" do
    test "marks Catalog as the active nav item" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "hero-circle-stack"
      assert html =~ "bg-primary/10"
    end
  end

  describe "pubsub updates" do
    test "re-renders latest run status when a revision import completes" do
      {conn, _org, mission} = signed_in_org_and_mission()
      database = TestFixtures.persist_catalog_database!(mission, name: "Live Catalog")
      run = TestFixtures.start_catalog_revision_import!(database)

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "Running"

      _completed = TestFixtures.complete_catalog_import_run!(run)

      assert render(view) =~ "Completed"
    end
  end
end
