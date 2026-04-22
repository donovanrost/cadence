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
    test "shows empty state when no catalog databases exist" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "No catalog databases"
      assert html =~ "Create catalog database revision"
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

  describe "upload flow" do
    test "shows a friendly banner when no importer matches the file" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

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

      html = render(view)
      assert html =~ "No importer supports"
      assert html =~ "mission.bin"
    end

    test "uploading a valid YAML file creates a database revision import and navigates to the run" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

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

      assert render(view) =~ "Cadence YAML Database"

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
  end
end
