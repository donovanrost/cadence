defmodule CadenceWeb.CatalogArtifactShowLiveTest do
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
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders artifact metadata and its import runs" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")
    run = TestFixtures.persist_catalog_import_run!(artifact)
    _ = TestFixtures.complete_catalog_import_run!(run)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    assert html =~ "mission.yaml"
    assert html =~ artifact.format_key
    assert html =~ "Completed"
  end

  test "re-import action starts a new run and navigates to it" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission, artifact_name: "mission.yaml")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}"
      )

    result = view |> element("button", "Re-import") |> render_click()

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert to =~ ~r"/catalog/imports/"
  end

  test "missing artifact redirects to the catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/artifacts/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end
end
