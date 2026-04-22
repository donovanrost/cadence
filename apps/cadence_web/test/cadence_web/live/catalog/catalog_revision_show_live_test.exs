defmodule CadenceWeb.CatalogRevisionShowLiveTest do
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

  test "renders revision provenance and snapshot summaries" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Bus Catalog")
    run = TestFixtures.start_catalog_revision_import!(database, revision_label: "FSW 3.7")
    completed = TestFixtures.complete_catalog_import_run!(run)
    revision = TestFixtures.fetch_catalog_revision_for_run!(completed)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
      )

    assert html =~ "FSW 3.7"
    assert html =~ "Bus Catalog"
    assert html =~ "Telemetry snapshot"
    assert html =~ "Command snapshot"
    assert html =~ "No runtime bindings yet"
  end

  test "missing revision redirects to catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/revisions/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end
end
