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

  describe "artifacts table" do
    test "shows empty state when no artifacts exist" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "No catalog artifacts"
    end

    test "lists persisted artifacts with their latest run status" do
      {conn, _org, mission} = signed_in_org_and_mission()
      artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
      run = TestFixtures.persist_catalog_import_run!(artifact)
      _ = TestFixtures.complete_catalog_import_run!(run)

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "mission.yaml"
      assert html =~ "Completed"
    end

    test "only shows artifacts in this mission" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "other", display_name: "Other Mission")

      _mine = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mine.yaml")

      _theirs =
        TestFixtures.persist_catalog_artifact!(other_mission, artifact_name: "theirs.yaml")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "mine.yaml"
      refute html =~ "theirs.yaml"
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
    test "re-renders latest run status when an import run completes" do
      {conn, _org, mission} = signed_in_org_and_mission()
      artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
      run = TestFixtures.persist_catalog_import_run!(artifact)

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

    test "uploading a valid YAML file creates an artifact, starts a run, and navigates to the run" do
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

      # After validate: detected importer is shown, submit enabled
      assert render(view) =~ "Cadence YAML Database"

      result = render_submit(view, "save", %{})

      assert {:error, {:live_redirect, %{to: to}}} = result
      assert to =~ ~r"/missions/.+/catalog/imports/"
    end
  end
end
