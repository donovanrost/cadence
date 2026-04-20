defmodule CadenceWeb.CatalogTelemetrySnapshotShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary")
    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders summary counts and provenance back-links" do
    {conn, org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)
    _ = TestFixtures.complete_catalog_import_run!(run)

    [snapshot | _] =
      Catalog.list_telemetry_snapshots(
        org.organization_id,
        mission.mission_id,
        import_run_id: run.import_run_id
      )

    {:ok, _view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/telemetry_snapshots/#{snapshot.snapshot_id}"
      )

    assert html =~ "Telemetry snapshot"
    assert html =~ "Packets"
    assert html =~ "Points"
    assert html =~ artifact.artifact_name
  end

  test "missing snapshot redirects to catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error, {:redirect, %{to: to, flash: _}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/catalog/telemetry_snapshots/missing"
             )

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end
end
