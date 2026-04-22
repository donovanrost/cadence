defmodule Cadence.CatalogTest do
  use Cadence.DataCase, async: false

  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, Database}
  alias Cadence.Missions.Mission

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

  describe "latest_import_run_by_artifact/2" do
    test "returns empty map when there are no runs" do
      persist_mission_scope(@organization_id, @mission_id)

      assert Catalog.latest_import_run_by_artifact(
               @organization_id,
               @mission_id
             ) == %{}
    end

    test "returns the most recent run per artifact" do
      persist_mission_scope(@organization_id, @mission_id)

      artifact_a = persist_artifact!("artifact-a")
      artifact_b = persist_artifact!("artifact-b")

      {:ok, older_a} = start_import_run!(artifact_a.artifact_id)
      # Ensure monotonic started_at even on fast clocks.
      Process.sleep(10)
      {:ok, newer_a} = start_import_run!(artifact_a.artifact_id)
      Process.sleep(10)
      {:ok, only_b} = start_import_run!(artifact_b.artifact_id)

      result =
        Catalog.latest_import_run_by_artifact(@organization_id, @mission_id)

      assert result[artifact_a.artifact_id].import_run_id == newer_a.import_run_id
      assert result[artifact_b.artifact_id].import_run_id == only_b.import_run_id
      refute result[artifact_a.artifact_id].import_run_id == older_a.import_run_id
    end

    test "scopes by mission" do
      %{organization: _org, mission: mission_a} =
        persist_mission_scope(@organization_id, @mission_id)

      other_mission_id = "#{@mission_id}-other"

      # Persist the other mission under the same org.
      {:ok, _} =
        Cadence.persist_mission(
          Mission.new(%{
            mission_id: other_mission_id,
            organization_id: @organization_id,
            slug: other_mission_id,
            display_name: other_mission_id
          })
        )

      artifact = persist_artifact!("artifact-scope", mission_id: mission_a.mission_id)
      {:ok, _} = start_import_run!(artifact.artifact_id)

      assert Catalog.latest_import_run_by_artifact(
               @organization_id,
               other_mission_id
             ) == %{}
    end
  end

  describe "catalog database revisions" do
    test "creates a database and revision from a successful revision import" do
      persist_mission_scope(@organization_id, @mission_id)

      assert {:ok, %Database{} = database} =
               Catalog.create_database(@organization_id, @mission_id, %{
                 name: "Bus Catalog",
                 slug: "bus-catalog",
                 catalog_family: :telemetry,
                 default_importer_key: "fake_tm_json",
                 created_by: %{"service_identity_id" => "svc-bootstrap"}
               })

      artifact =
        Artifact.new(%{
          organization_id: @organization_id,
          mission_id: @mission_id,
          catalog_database_id: database.catalog_database_id,
          catalog_family: :telemetry,
          artifact_name: "bus.json",
          format_key: "fake_tm_json",
          media_type: "application/json",
          source_artifact: %{"packets" => [%{"name" => "HK_PACKET"}]}
        })

      assert {:ok, run} =
               Catalog.start_revision_import(
                 @organization_id,
                 @mission_id,
                 database.catalog_database_id,
                 artifact,
                 "fake_tm_json",
                 metadata: %{"revision_label" => "FSW 3.7"},
                 requested_by: %{"service_identity_id" => "svc-bootstrap"}
               )

      assert {:ok, job} = Cadence.Jobs.fetch_job_for_run(:catalog_import_run, run.import_run_id)
      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, _completed_job} = Cadence.Jobs.run_job(job.job_id)

      assert {:ok, completed_run} =
               Cadence.fetch_catalog_import_run(@organization_id, @mission_id, run.import_run_id)

      assert completed_run.status == :completed
      assert completed_run.catalog_database_id == database.catalog_database_id

      assert %{"catalog_revision_id" => revision_id} =
               completed_run.result_document["catalog_revision"]

      assert {:ok, revision} =
               Catalog.fetch_revision(@organization_id, @mission_id, revision_id)

      assert revision.catalog_database_id == database.catalog_database_id
      assert revision.revision_number == 1
      assert revision.revision_label == "FSW 3.7"
      assert revision.import_run_id == completed_run.import_run_id
      assert revision.telemetry_snapshot_id == completed_run.snapshot_id
      assert revision.command_snapshot_id == nil

      assert {:ok, latest} =
               Catalog.latest_revision(
                 @organization_id,
                 @mission_id,
                 database.catalog_database_id
               )

      assert latest.catalog_revision_id == revision.catalog_revision_id
    end

    test "does not create a revision for a failed revision import" do
      persist_mission_scope(@organization_id, @mission_id)

      {:ok, database} =
        Catalog.create_database(@organization_id, @mission_id, %{
          name: "Bus Catalog",
          slug: "bus-catalog",
          catalog_family: :telemetry
        })

      artifact =
        Artifact.new(%{
          organization_id: @organization_id,
          mission_id: @mission_id,
          catalog_database_id: database.catalog_database_id,
          catalog_family: :telemetry,
          artifact_name: "invalid.json",
          format_key: "fake_tm_json",
          media_type: "application/json",
          source_artifact: %{"not_packets" => []}
        })

      assert {:error, :invalid_fake_tm_json} =
               Catalog.start_revision_import(
                 @organization_id,
                 @mission_id,
                 database.catalog_database_id,
                 artifact,
                 "fake_tm_json",
                 metadata: %{"revision_label" => "Bad"}
               )

      assert [] =
               Catalog.list_revisions(
                 @organization_id,
                 @mission_id,
                 database.catalog_database_id
               )
    end
  end

  defp persist_artifact!(artifact_id, opts \\ []) do
    artifact =
      Catalog.Artifact.new(%{
        artifact_id: artifact_id,
        organization_id: @organization_id,
        mission_id: Keyword.get(opts, :mission_id, @mission_id),
        catalog_family: :telemetry,
        artifact_name: "#{artifact_id}.json",
        format_key: "fake_tm_json",
        media_type: "application/json",
        source_artifact: %{"packets" => [%{"name" => "HK_#{artifact_id}"}]},
        uploaded_by: %{"service_identity_id" => "svc-test"}
      })

    {:ok, persisted} = Cadence.persist_catalog_artifact(@organization_id, artifact)
    persisted
  end

  defp start_import_run!(artifact_id) do
    Cadence.start_catalog_import_run(
      @organization_id,
      @mission_id,
      artifact_id,
      "fake_tm_json",
      requested_by: %{"service_identity_id" => "svc-test"}
    )
  end
end
