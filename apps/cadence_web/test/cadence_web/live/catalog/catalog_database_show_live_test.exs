defmodule CadenceWeb.CatalogDatabaseShowLiveTest do
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

  test "renders database metadata, revision history, and import attempts" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")
    run = TestFixtures.start_catalog_revision_import!(database, revision_label: "Payload 7")
    completed = TestFixtures.complete_catalog_import_run!(run)
    _revision = TestFixtures.fetch_catalog_revision_for_run!(completed)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    assert html =~ "Payload Catalog"
    assert html =~ "Payload 7"
    assert html =~ "Completed"
    assert html =~ "No runtime bindings yet"
    refute html =~ ">Family<"
    refute html =~ "Combined"
  end

  test "missing database redirects to catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/databases/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end

  test "add-revision form is hidden by default and shown on toggle" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")

    {:ok, view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    refute html =~ "catalog-revision-upload-form"
    assert html =~ "id=\"add-revision-toggle\""
    assert html =~ "Add revision"

    html_after_open =
      view
      |> element("#add-revision-toggle")
      |> render_click()

    assert html_after_open =~ "catalog-revision-upload-form"
    assert html_after_open =~ "Cancel"
  end

  test "cancelling the add-revision reveal hides the form" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    _ = view |> element("#add-revision-toggle") |> render_click()
    assert render(view) =~ "catalog-revision-upload-form"

    html_after_cancel =
      view
      |> element("#add-revision-toggle")
      |> render_click()

    refute html_after_cancel =~ "catalog-revision-upload-form"
    assert html_after_cancel =~ "Add revision"
  end
end
