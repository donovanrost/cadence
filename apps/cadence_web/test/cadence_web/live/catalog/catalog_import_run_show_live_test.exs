defmodule CadenceWeb.CatalogImportRunShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog.Events
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders running status for a freshly inserted run" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, _view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    assert html =~ "Running"
    refute html =~ "Telemetry snapshot"
  end

  test "re-renders snapshot summary after an async completion broadcast" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    completed = TestFixtures.complete_catalog_import_run!(run)

    html = render(view)
    assert html =~ "Completed"

    if completed.snapshot_id do
      assert html =~ "Telemetry snapshot"
    end
  end

  test "missing run redirects to the catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end

  test "failure reason renders when a run fails" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    failed_run = %{run | status: :failed, failure_reason: {:exception, "boom"}}
    Events.broadcast_failed(failed_run)

    html = render(view)
    assert html =~ "Failed"
    assert html =~ "boom"
  end
end
