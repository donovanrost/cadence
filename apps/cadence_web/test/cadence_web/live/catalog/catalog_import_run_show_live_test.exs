defmodule CadenceWeb.CatalogImportRunShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog.Events
  alias Cadence.Runtime.MissionModelPlanDecoder
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
    refute has_element?(view, "#catalog-import-mission-model")
    assert has_element?(view, "#catalog-importer-version")
  end

  test "re-renders Mission Model summary after an async completion broadcast" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    completed = TestFixtures.complete_catalog_import_run!(run)

    html = render(view)
    assert html =~ "Completed"
    assert has_element?(view, "#catalog-import-mission-model")
    assert html =~ completed.result_document["mission_model"]["revision_id"]
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

  test "renders native Mission Model lowering diagnostics" do
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

    diagnostic_codes = Enum.map(completed.diagnostics, & &1.code)
    assert "MM_TELEMETRY_CONTAINER_NOT_LOWERABLE" in diagnostic_codes
    assert "MM_TELEMETRY_APID_REQUIRED" in diagnostic_codes

    {:ok, _view, html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}")

    assert html =~ "MM_TELEMETRY_APID_REQUIRED"
    assert html =~ "concrete telemetry containers require an APID"
  end

  test "preserves binary packet fields in the native telemetry plan" do
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

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}")

    revision_id = completed.result_document["mission_model"]["revision_id"]

    assert {:ok, plans} =
             Cadence.MissionModels.fetch_runtime_plans(
               completed.organization_id,
               completed.mission_id,
               revision_id
             )

    assert {:ok, [packet]} = MissionModelPlanDecoder.telemetry_packet_definitions(plans)
    assert packet.packet_name == "SCIENCE_FRAME"
    assert [%{name: "data_block", data_type: :binary}] = packet.fields
    assert has_element?(view, "#catalog-import-mission-model")
  end
end
