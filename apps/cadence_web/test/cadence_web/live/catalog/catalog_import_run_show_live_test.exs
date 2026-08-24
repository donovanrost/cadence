defmodule CadenceWeb.CatalogImportRunShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Catalog.Diagnostic
  alias Cadence.Catalog.Events
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")

    {TestFixtures.member_conn(user), org, mission}
  end

  test "renders a running import through exact JSON-safe presentation props" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    assert has_element?(view, "#catalog-import-run-show-page")
    assert has_element?(view, "#catalog-import-run-show-component")

    vue = catalog_import_run_vue(view)

    assert vue.component == "CatalogImportRunShow"
    assert vue.ssr == false
    assert is_binary(Jason.encode!(vue.props))

    assert vue.props == %{
             "diagnostic_groups" => [],
             "failure_reason" => nil,
             "mission_model" => nil,
             "navigation" => %{
               "breadcrumbs" => [
                 %{
                   "href" => "/missions/#{mission.mission_id}",
                   "label" => "Primary Mission"
                 },
                 %{
                   "href" => "/missions/#{mission.mission_id}/catalog",
                   "label" => "Catalog"
                 },
                 %{
                   "href" =>
                     "/missions/#{mission.mission_id}/catalog/artifacts/#{artifact.artifact_id}",
                   "label" => "Artifact"
                 },
                 %{"href" => nil, "label" => "Import run"}
               ]
             },
             "run_details" => %{
               "completed_at" => nil,
               "importer" => %{
                 "id" => "catalog-importer-version",
                 "label" => "#{run.importer_key} v#{run.importer_version}"
               },
               "started_at" => format_timestamp(run.started_at)
             },
             "status" => %{"label" => "Running", "tone" => "info"}
           }
  end

  test "re-renders Mission Model summary after an async completion broadcast" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    completed = TestFixtures.complete_catalog_import_run!(run)

    _ = render(view)
    props = catalog_import_run_vue(view).props
    summary = completed.result_document["mission_model"]

    assert props["status"] == %{"label" => "Completed", "tone" => "ready"}
    assert props["run_details"]["completed_at"] == format_timestamp(completed.completed_at)

    assert props["mission_model"] == %{
             "declaration_count" => summary["declaration_count"],
             "id" => "catalog-import-mission-model",
             "plan_count" => map_size(summary["plans"] || %{}),
             "revision_id" => summary["revision_id"]
           }
  end

  test "missing run redirects to the catalog index" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:error,
            {:redirect,
             %{
               to: to,
               flash: %{"error" => "Import run not found."}
             }}} =
             live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/missing")

    assert to == ~p"/missions/#{mission.mission_id}/catalog"
  end

  test "does not expose import runs outside the current organization or mission scope" do
    {conn, org, mission} = signed_in_org_and_mission()

    other_mission =
      TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

    other_mission_run =
      other_mission
      |> TestFixtures.persist_catalog_artifact!()
      |> TestFixtures.persist_catalog_import_run!()

    other_org = TestFixtures.persist_org!(display_name: "Remote Org", slug: "remote-org")
    remote_mission = TestFixtures.persist_mission!(other_org, slug: "remote")

    other_org_run =
      remote_mission
      |> TestFixtures.persist_catalog_artifact!()
      |> TestFixtures.persist_catalog_import_run!()

    for foreign_run <- [other_mission_run, other_org_run] do
      assert {:error,
              {:redirect,
               %{
                 to: to,
                 flash: %{"error" => "Import run not found."}
               }}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/catalog/imports/#{foreign_run.import_run_id}"
               )

      assert to == ~p"/missions/#{mission.mission_id}/catalog"
    end
  end

  test "failure reason renders when a run fails" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    failed_run = %{run | status: :failed, failure_reason: {:exception, "boom"}}
    Events.broadcast_failed(failed_run)

    _ = render(view)
    props = catalog_import_run_vue(view).props

    assert props["status"] == %{"label" => "Failed", "tone" => "blocked"}
    assert props["failure_reason"] == "boom"
  end

  test "preserves diagnostic grouping, metadata detail, and path formatting" do
    {conn, _org, mission} = signed_in_org_and_mission()
    artifact = TestFixtures.persist_catalog_artifact!(mission)
    run = TestFixtures.persist_catalog_import_run!(artifact)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}")

    diagnostic =
      Diagnostic.new(%{
        severity: :warning,
        code: "CATALOG_ENTRY_WARNING",
        message: "Entry was retained with importer metadata",
        path: ["packets", "HEALTH", "mode"],
        metadata: %{
          "packet_name" => "HEALTH",
          "entry_name" => "mode",
          "consumption_status" => "retained"
        }
      })

    Events.broadcast_updated(%{run | diagnostics: [diagnostic]})
    _ = render(view)

    assert catalog_import_run_vue(view).props["diagnostic_groups"] == [
             %{
               "items" => [
                 %{
                   "code" => "CATALOG_ENTRY_WARNING",
                   "detail" => "Status: retained | Packet: HEALTH | Entry: mode",
                   "message" => "Entry was retained with importer metadata",
                   "path" => "packets / HEALTH / mode"
                 }
               ],
               "title" => "Warnings (1)"
             }
           ]
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

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/catalog/imports/#{completed.import_run_id}")

    props = catalog_import_run_vue(view).props
    assert is_binary(Jason.encode!(props))

    diagnostic_items =
      props["diagnostic_groups"]
      |> Enum.flat_map(& &1["items"])

    assert %{
             "code" => "MM_TELEMETRY_APID_REQUIRED",
             "message" => "concrete telemetry containers require an APID"
           } =
             Enum.find(
               diagnostic_items,
               &(&1["code"] == "MM_TELEMETRY_APID_REQUIRED")
             )
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

    assert catalog_import_run_vue(view).props["mission_model"]["id"] ==
             "catalog-import-mission-model"
  end

  defp catalog_import_run_vue(view) do
    LiveVue.Test.get_vue(view, id: "catalog-import-run-show-component")
  end

  defp format_timestamp(timestamp), do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")
end
