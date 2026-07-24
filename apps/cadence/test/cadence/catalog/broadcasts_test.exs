defmodule Cadence.Catalog.BroadcastsTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Catalog.{Artifact, Events}

  @organization_id "org-broadcasts"
  @mission_id "mission-broadcasts"

  setup do
    previous_importers = Application.get_env(:cadence_catalog, :catalog_importers, [])

    Application.put_env(:cadence_catalog, :catalog_importers, [
      Cadence.TestSupport.FakeTelemetryCatalogImporter,
      Cadence.TestSupport.FakeFailingImporter
    ])

    on_exit(fn ->
      Application.put_env(:cadence_catalog, :catalog_importers, previous_importers)
    end)

    persist_mission_scope(@organization_id, @mission_id)
    :ok
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

  defp run_enqueued_job(import_run_id) do
    {:ok, job} = Cadence.Jobs.fetch_job_for_run(:catalog_import_run, import_run_id)
    [_] = Cadence.Jobs.claim_jobs(1)
    {:ok, completed_job} = JobRunner.run_job(job.job_id)
    completed_job
  end

  test "broadcasts :import_run_started when a run is inserted" do
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
        "fake_tm_json"
      )

    assert_receive {:import_run_started, received_run}
    assert received_run.import_run_id == run.import_run_id
    assert received_run.status == :running
  end

  test "broadcasts :import_run_completed when an async run succeeds" do
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
        "fake_tm_json"
      )

    assert_receive {:import_run_started, _}

    _ = run_enqueued_job(run.import_run_id)

    assert_receive {:import_run_completed, completed}
    assert completed.import_run_id == run.import_run_id
    assert completed.status == :completed
  end

  test "broadcasts :import_run_failed when an async run fails" do
    artifact = build_and_persist_artifact("fake_failing", %{"irrelevant" => true})

    :ok = Events.subscribe_import_runs(@mission_id)

    {:ok, run} =
      Cadence.Catalog.start_import_run(
        @organization_id,
        @mission_id,
        artifact.artifact_id,
        "fake_failing"
      )

    assert_receive {:import_run_started, _}

    _ = run_enqueued_job(run.import_run_id)

    assert_receive {:import_run_failed, failed}
    assert failed.import_run_id == run.import_run_id
    assert failed.status == :failed
  end
end
