defmodule Cadence.Catalog.BroadcastsTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Catalog.{Artifact, Events, Registry}

  @organization_id "org-broadcasts"
  @mission_id "mission-broadcasts"

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    {:ok,
     importer_opts: [
       importer_registrations:
         Registry.registrations([
           Cadence.TestSupport.FakeTelemetryCatalogImporter,
           Cadence.TestSupport.FakeFailingImporter
         ])
     ]}
  end

  defp build_and_persist_artifact(format_key, source_artifact) do
    artifact =
      Artifact.new(%{
        organization_id: @organization_id,
        mission_id: @mission_id,
        catalog_family: :telemetry,
        artifact_name: "fixture.json",
        format_key: format_key,
        media_type: "application/json",
        source_artifact: source_artifact,
        uploaded_by: %{"service_identity_id" => "svc-bootstrap"}
      })

    {:ok, persisted} = Cadence.Catalog.persist_artifact(@organization_id, artifact)
    persisted
  end

  defp run_enqueued_job(import_run_id, importer_opts) do
    {:ok, job} = Cadence.Jobs.fetch_job_for_run(:catalog_import_run, import_run_id)
    [_] = Cadence.Jobs.claim_jobs(1)

    runner =
      JobRunner.new(%{
        catalog_import_run: fn run_id ->
          Cadence.Catalog.execute_enqueued_run(run_id, importer_opts)
        end
      })

    {:ok, completed_job} = JobRunner.run_job(runner, job.job_id)
    completed_job
  end

  test "broadcasts :import_run_started when a run is inserted", %{
    importer_opts: importer_opts
  } do
    artifact =
      build_and_persist_artifact("fake_tm_json", %{
        "packets" => [%{"name" => "HK"}]
      })

    :ok = Events.subscribe_import_runs(@mission_id)

    {:ok, run} =
      Cadence.Catalog.start_import_run(
        @organization_id,
        @mission_id,
        artifact.artifact_id,
        "fake_tm_json",
        importer_opts
      )

    assert_receive {:import_run_started, received_run}
    assert received_run.import_run_id == run.import_run_id
    assert received_run.status == :running
  end

  test "broadcasts :import_run_completed when an async run succeeds", %{
    importer_opts: importer_opts
  } do
    artifact =
      build_and_persist_artifact("fake_tm_json", %{
        "packets" => [%{"name" => "HK"}]
      })

    :ok = Events.subscribe_import_runs(@mission_id)

    {:ok, run} =
      Cadence.Catalog.start_import_run(
        @organization_id,
        @mission_id,
        artifact.artifact_id,
        "fake_tm_json",
        importer_opts
      )

    assert_receive {:import_run_started, _}

    _ = run_enqueued_job(run.import_run_id, importer_opts)

    assert_receive {:import_run_completed, completed}
    assert completed.import_run_id == run.import_run_id
    assert completed.status == :completed
  end

  test "broadcasts :import_run_failed when an async run fails", %{
    importer_opts: importer_opts
  } do
    artifact = build_and_persist_artifact("fake_failing", %{"irrelevant" => true})

    :ok = Events.subscribe_import_runs(@mission_id)

    {:ok, run} =
      Cadence.Catalog.start_import_run(
        @organization_id,
        @mission_id,
        artifact.artifact_id,
        "fake_failing",
        importer_opts
      )

    assert_receive {:import_run_started, _}

    _ = run_enqueued_job(run.import_run_id, importer_opts)

    assert_receive {:import_run_failed, failed}
    assert failed.import_run_id == run.import_run_id
    assert failed.status == :failed
  end
end
