defmodule CadenceWeb.CatalogArtifactDownloadControllerTest do
  use CadenceWeb.ConnCase, async: true

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "downloads the raw artifact bytes with content-disposition" do
    {conn, _org, mission} = signed_in_org_and_mission()

    artifact =
      TestFixtures.persist_catalog_artifact!(mission,
        artifact_name: "mission.yaml",
        source_artifact: "hello: world\n"
      )

    conn =
      get(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}/download"
      )

    assert response(conn, 200) == "hello: world\n"
    assert [content_type | _] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/yaml"
    assert [disposition | _] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(attachment; filename=)
    assert disposition =~ "mission.yaml"
  end

  test "returns 404 for unknown artifact" do
    {conn, _org, mission} = signed_in_org_and_mission()

    conn =
      get(conn, ~p"/missions/#{mission.mission_id}/catalog/artifacts/missing/download")

    assert conn.status == 404
  end

  test "redirects to /sign-in when the user is not authenticated", %{conn: conn} do
    conn = get(conn, "/missions/any-mission/catalog/artifacts/any-artifact/download")

    assert redirected_to(conn) == "/sign-in"
  end
end
