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

    {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    assert html =~ "New catalog database"
    assert html =~ "catalog-upload-form"
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

    html = render(view)
    assert html =~ "No importer supports"
    assert html =~ "mission.bin"
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

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/any/catalog/new")
    end
  end
end
