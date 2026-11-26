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

  # §11c B: the catalog index, database, revision and import pages redirect to the console's
  # Setup catalog; the artifact page (L18) is the host's last Catalog page.
  test "the artifact page loads without installations or releases and satisfies its consumer validator",
       %{conn: conn, mission: mission} do
    database = TestFixtures.persist_catalog_database!(mission)
    run = TestFixtures.start_catalog_revision_import!(database)
    run = TestFixtures.complete_catalog_import_run!(run)
    path = "/missions/#{mission.mission_id}/catalog/artifacts/#{run.artifact_id}"
    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#application-shell")
    assert_page(view, "catalog_artifact_show", "artifacts", "assertArtifact")

    render_hook(view, "host:context", %{"path" => "/missions/#{mission.mission_id}/ops"})
    assert snapshot(view)["catalog"] == nil
  end

  test "matched path identity defeats query overrides and cross-mission artifact reads", %{
    conn: conn,
    mission: mission
  } do
    other_org = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_org)
    other = TestFixtures.persist_catalog_artifact!(other_mission)
    base = "/missions/#{mission.mission_id}/catalog/artifacts"

    {:ok, view, _} =
      live(conn, base <> "/#{other.artifact_id}?mission_id=#{other_mission.mission_id}")

    assert %{"status" => "unavailable"} = snapshot(view)["catalog"]
    refute Map.has_key?(snapshot(view)["catalog"], "data")

    own = TestFixtures.persist_catalog_artifact!(mission)

    render_hook(view, "host:context", %{
      "path" => base <> "/#{own.artifact_id}?artifact_id=#{other.artifact_id}"
    })

    href =
      get_in(snapshot(view), [
        "catalog",
        "data",
        "presentation",
        "artifact_show",
        "artifact",
        "download_href"
      ])

    assert href == base <> "/#{own.artifact_id}/download"
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

    render_hook(view, "host:context", %{"path" => "/missions/#{mission.mission_id}/ops"})
    render_hook(view, "host:catalog", %{"event" => "reimport", "path" => path})
    assert length(Catalog.list_import_runs(mission.organization_id, mission.mission_id)) == 1
  end

  test "refresh reauthorizes a revoked user session", %{conn: conn, mission: mission} do
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    path = "/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
    {:ok, view, _} = live(conn, path)
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => path})
    assert_redirect(view, "/console/sign-in")
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
