defmodule CadenceWeb.CatalogPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Catalog
  alias CadenceWeb.TestFixtures

  @features Path.expand("../../../../frontend/apps/host/src/catalog/features", __DIR__)

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    {:ok, conn: TestFixtures.member_conn(user), mission: mission}
  end

  test "all six core Catalog pages load without installations or releases and satisfy real consumer validators",
       %{conn: conn, mission: mission} do
    base = "/missions/#{mission.mission_id}/catalog"
    {:ok, view, _} = live(conn, base)
    assert has_element?(view, "#application-shell")
    assert_page(view, "catalog_index", "databases", "assertDatabaseIndex")

    render_hook(view, "host:context", %{"path" => base <> "/new"})
    data = assert_page(view, "catalog_database_new", "databases", "assertDatabaseNew")
    assert data["page"]["cancel"]["href"] == base

    database = TestFixtures.persist_catalog_database!(mission)
    run = TestFixtures.start_catalog_revision_import!(database)
    run = TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(run)

    pages = [
      {base, "catalog_index", "databases", "assertDatabaseIndex"},
      {base <> "/databases/#{database.catalog_database_id}", "catalog_database_show", "databases",
       "assertDatabaseShow"},
      {base <> "/revisions/#{revision.catalog_revision_id}", "catalog_revision_show", "revisions",
       "assertRevision"},
      {base <> "/artifacts/#{run.artifact_id}", "catalog_artifact_show", "artifacts",
       "assertArtifact"},
      {base <> "/imports/#{run.import_run_id}", "catalog_import_run_show", "imports",
       "assertImportRun"}
    ]

    for {path, page, feature, validator} <- pages do
      render_hook(view, "host:context", %{"path" => path})
      assert_page(view, page, feature, validator)
    end

    render_hook(view, "host:context", %{"path" => "/missions"})
    assert snapshot(view)["catalog"] == nil
  end

  test "matched path identity defeats query overrides and cross-mission detail reads", %{
    conn: conn,
    mission: mission
  } do
    other_org = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_org)
    other = TestFixtures.persist_catalog_database!(other_mission, name: "Private database")
    base = "/missions/#{mission.mission_id}/catalog"
    path = base <> "/databases/#{other.catalog_database_id}"
    {:ok, view, _} = live(conn, path <> "?mission_id=#{other_mission.mission_id}")
    assert %{"status" => "unavailable"} = snapshot(view)["catalog"]
    refute Map.has_key?(snapshot(view)["catalog"], "data")

    own = TestFixtures.persist_catalog_database!(mission)

    path =
      base <>
        "/databases/#{own.catalog_database_id}?catalog_database_id=#{other.catalog_database_id}"

    render_hook(view, "host:context", %{"path" => path})
    assert snapshot(view)["catalog"]["data"]["database"]["id"] == own.catalog_database_id
  end

  test "reimport is bound to the displayed artifact path, not input identifiers", %{
    conn: conn,
    mission: mission
  } do
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    other = TestFixtures.persist_catalog_artifact!(mission)
    path = "/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
    {:ok, view, _} = live(conn, path)

    render_hook(view, "host:catalog", %{
      "event" => "reimport",
      "path" => path,
      "artifact_id" => other.artifact_id
    })

    assert [run] = Catalog.list_import_runs(mission.organization_id, mission.mission_id)
    assert run.artifact_id == artifact.artifact_id

    render_hook(view, "host:context", %{"path" => "/missions"})
    render_hook(view, "host:catalog", %{"event" => "reimport", "path" => path})
    assert length(Catalog.list_import_runs(mission.organization_id, mission.mission_id)) == 1
  end

  test "refresh reauthorizes a revoked user session", %{conn: conn, mission: mission} do
    path = "/missions/#{mission.mission_id}/catalog"
    {:ok, view, _} = live(conn, path)
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => path})
    assert_redirect(view, "/sign-in")
  end

  defp snapshot(view), do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]

  defp assert_page(view, page, feature, validator) do
    assert %{"page" => ^page, "version" => 1, "status" => "ready", "data" => data} =
             snapshot(view)["catalog"]

    path = Path.join([@features, feature, "validation.ts"])
    node = System.find_executable("node") || flunk("Node is required for Catalog DTO validation")

    script =
      "import {#{validator}} from #{Jason.encode!(path)}; #{validator}(JSON.parse(process.argv[1]));"

    {output, status} =
      System.cmd(
        node,
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(data)],
        stderr_to_stdout: true
      )

    assert status == 0, output
    data
  end
end
