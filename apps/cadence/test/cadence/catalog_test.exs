defmodule Cadence.CatalogTest do
  use Cadence.DataCase, async: false

  alias Cadence.Catalog.Artifact

  @organization_id "org-alpha"
  @mission_id "mission-alpha"

  setup do
    previous_importers = Application.get_env(:cadence, :catalog_importers, [])

    Application.put_env(:cadence, :catalog_importers, [
      Cadence.TestSupport.FakeTelemetryCatalogImporter
    ])

    on_exit(fn ->
      Application.put_env(:cadence, :catalog_importers, previous_importers)
    end)

    :ok
  end

  test "persists artifacts, lists importers, and executes import runs through the durable job queue" do
    persist_mission_scope(@organization_id, @mission_id)

    artifact =
      Artifact.new(%{
        artifact_id: "artifact-alpha",
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :telemetry,
        artifact_name: "mission-alpha-tm.json",
        format_key: "fake_tm_json",
        media_type: "application/json",
        source_artifact: %{
          "packets" => [
            %{"name" => "HK_PACKET"},
            %{"name" => "EVENT_PACKET"}
          ]
        },
        uploaded_by: %{"service_identity_id" => "svc-bootstrap"}
      })

    assert [%{descriptor: %{importer_key: "fake_tm_json"}}] = Cadence.list_catalog_importers()

    assert {:ok, persisted_artifact} =
             Cadence.persist_catalog_artifact(@organization_id, artifact)

    assert persisted_artifact.content_sha256 != ""

    assert {:ok, fetched_artifact} =
             Cadence.fetch_catalog_artifact(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id
             )

    assert fetched_artifact.source_artifact == artifact.source_artifact

    assert [listed_artifact] =
             Cadence.list_catalog_artifacts(
               @organization_id,
               @mission_id,
               catalog_family: :telemetry
             )

    assert listed_artifact.artifact_id == persisted_artifact.artifact_id

    assert {:ok, queued_run} =
             Cadence.start_catalog_import_run(
               @organization_id,
               @mission_id,
               persisted_artifact.artifact_id,
               "fake_tm_json",
               requested_by: %{"service_identity_id" => "svc-bootstrap"},
               metadata: %{"reason" => "test"}
             )

    assert queued_run.status == :running

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = Cadence.Jobs.run_job(queued_job.job_id)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.fetch_catalog_import_run(
               @organization_id,
               @mission_id,
               queued_run.import_run_id
             )

    assert completed_run.status == :completed
    assert completed_run.snapshot_id == "telemetry_snapshot:" <> queued_run.import_run_id
    assert completed_run.imported_definition_count == 2
    assert completed_run.result_document["packet_names"] == ["HK_PACKET", "EVENT_PACKET"]
    assert [%{code: "fake_tm_json.warning", severity: :warning}] = completed_run.diagnostics

    assert {:ok, telemetry_snapshot} =
             Cadence.fetch_catalog_telemetry_snapshot(
               @organization_id,
               @mission_id,
               completed_run.snapshot_id
             )

    assert telemetry_snapshot.snapshot_name == persisted_artifact.artifact_name
    assert Enum.map(telemetry_snapshot.packets, & &1.name) == ["HK_PACKET", "EVENT_PACKET"]

    assert [listed_snapshot] =
             Cadence.list_catalog_telemetry_snapshots(
               @organization_id,
               @mission_id,
               import_run_id: completed_run.import_run_id
             )

    assert listed_snapshot.snapshot_id == telemetry_snapshot.snapshot_id

    assert [listed_run] =
             Cadence.list_catalog_import_runs(
               @organization_id,
               @mission_id,
               artifact_id: persisted_artifact.artifact_id,
               status: :completed
             )

    assert listed_run.import_run_id == completed_run.import_run_id
  end
end
