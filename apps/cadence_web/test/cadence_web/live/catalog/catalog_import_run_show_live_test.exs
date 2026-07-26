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

    {:ok, view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    assert html =~ "Running"
    refute html =~ "Telemetry snapshot"
    assert has_element?(view, "#catalog-importer-version", "cadence_yaml v1")
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

  test "renders resolved catalog diagnostic details from telemetry snapshot metadata" do
    {conn, _org, mission} = signed_in_org_and_mission()

    artifact =
      TestFixtures.persist_catalog_artifact!(mission,
        source_artifact: """
        packets:
          - name: HEALTH
            items:
              - name: label
                data_type: string
                bit_offset: 0
                bit_size: 32
        commands: []
        """
      )

    run = TestFixtures.persist_catalog_import_run!(artifact)
    completed = TestFixtures.complete_catalog_import_run!(run)

    {:ok, _view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}")

    assert html =~ "telemetry_compiler.type_unsupported"
    assert html =~ "Packet: HEALTH"
    assert html =~ "Entry: label"
    assert html =~ "Point: label"
    assert html =~ "Type: HEALTH_label_type"
    assert html =~ "Base type: string"
  end

  test "shows packets preserved for custom application binding in the runtime summary" do
    {conn, _org, mission} = signed_in_org_and_mission()

    artifact =
      TestFixtures.persist_catalog_artifact!(mission,
        catalog_family: :combined,
        source_artifact: """
        packets:
          - name: SCIENCE_FRAME
            apid: 42
            items:
              - name: data_block
                bit_offset: 96
                bit_size: 32672
                data_type: binary
                description: "Raw science data (~4KB)"
        """
      )

    run = TestFixtures.persist_catalog_import_run!(artifact, importer_key: "cadence_yaml")
    completed = TestFixtures.complete_catalog_import_run!(run)

    {:ok, _view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}")

    assert html =~ "Built-in telemetry runtime"
    assert html =~ "Available for custom applications"
    assert html =~ "SCIENCE_FRAME"
    assert html =~ "binary_payload_field"
    assert html =~ "Preserved in catalog, not compiled into built-in telemetry"
    assert html =~ "available_for_custom_application_binding"
  end
end
