defmodule Cadence.CatalogTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Catalog
  alias Cadence.Catalog.{Artifact, Database, Registry}

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeFactConsumer,
    RuntimeCacheKey,
    SourceResult
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Missions.Mission

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-catalog-#{suffix}"
    mission_id = "mission-catalog-#{suffix}"

    Process.put(:catalog_test_organization_id, organization_id)
    Process.put(:catalog_test_mission_id, mission_id)

    {:ok,
     importer_opts: [
       importer_registrations:
         Registry.registrations([Cadence.TestSupport.FakeTelemetryCatalogImporter])
     ]}
  end

  defp organization_id,
    do: Process.get(:catalog_test_organization_id) || raise("missing catalog test org")

  defp mission_id,
    do: Process.get(:catalog_test_mission_id) || raise("missing catalog test mission")

  test "persists artifacts, lists importers, and executes import runs through the durable job queue",
       %{importer_opts: importer_opts} do
    persist_mission_scope(organization_id(), mission_id())

    artifact =
      Artifact.new(%{
        artifact_id: "artifact-alpha",
        organization_id: organization_id(),
        mission_id: mission_id(),
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

    assert [%{descriptor: %{importer_key: "fake_tm_json"}}] =
             Cadence.Catalog.list_importers(importer_opts)

    assert {:ok, persisted_artifact} =
             Cadence.Catalog.persist_artifact(organization_id(), artifact)

    assert persisted_artifact.content_sha256 != ""

    assert {:ok, fetched_artifact} =
             Cadence.Catalog.fetch_artifact(
               organization_id(),
               mission_id(),
               persisted_artifact.artifact_id
             )

    assert fetched_artifact.source_artifact == artifact.source_artifact

    assert [listed_artifact] =
             Cadence.Catalog.list_artifacts(
               organization_id(),
               mission_id(),
               catalog_family: :telemetry
             )

    assert listed_artifact.artifact_id == persisted_artifact.artifact_id

    assert {:ok, queued_run} =
             Cadence.Catalog.start_import_run(
               organization_id(),
               mission_id(),
               persisted_artifact.artifact_id,
               "fake_tm_json",
               catalog_opts(importer_opts,
                 requested_by: %{"service_identity_id" => "svc-bootstrap"},
                 metadata: %{"reason" => "test"}
               )
             )

    assert queued_run.status == :running
    assert queued_run.importer_key == "fake_tm_json"
    assert queued_run.importer_version == 1

    assert {:error, :catalog_importer_version_not_found} =
             Cadence.Catalog.start_import_run(
               organization_id(),
               mission_id(),
               persisted_artifact.artifact_id,
               "fake_tm_json",
               catalog_opts(importer_opts, importer_version: 2)
             )

    assert {:ok, queued_job} =
             Cadence.Jobs.fetch_job_for_run(:catalog_import_run, queued_run.import_run_id)

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert {:ok, completed_job} = run_catalog_job(queued_job.job_id, importer_opts)
    assert completed_job.status == :completed

    assert {:ok, completed_run} =
             Cadence.Catalog.fetch_import_run(
               organization_id(),
               mission_id(),
               queued_run.import_run_id
             )

    assert completed_run.status == :completed
    assert completed_run.importer_version == 1
    assert completed_run.imported_definition_count == 2
    assert completed_run.result_document["packet_names"] == ["HK_PACKET", "EVENT_PACKET"]
    assert is_binary(completed_run.result_document["mission_model"]["revision_id"])

    assert Enum.map(completed_run.diagnostics, &{&1.code, &1.severity}) == [
             {"fake_tm_json.warning", :warning}
           ]

    assert [listed_run] =
             Cadence.Catalog.list_import_runs(
               organization_id(),
               mission_id(),
               artifact_id: persisted_artifact.artifact_id,
               status: :completed
             )

    assert listed_run.import_run_id == completed_run.import_run_id
  end

  describe "latest_import_run_by_artifact/2" do
    test "returns empty map when there are no runs" do
      suffix = System.unique_integer([:positive])
      organization_id = "org-catalog-empty-#{suffix}"
      mission_id = "mission-catalog-empty-#{suffix}"

      persist_mission_scope(organization_id, mission_id)

      assert Catalog.latest_import_run_by_artifact(organization_id, mission_id) == %{}
    end

    test "returns the most recent run per artifact", %{importer_opts: importer_opts} do
      persist_mission_scope(organization_id(), mission_id())

      artifact_a = persist_artifact!("artifact-a")
      artifact_b = persist_artifact!("artifact-b")

      {:ok, older_a} = start_import_run!(artifact_a.artifact_id, importer_opts)
      # Ensure monotonic started_at even on fast clocks.
      Process.sleep(10)
      {:ok, newer_a} = start_import_run!(artifact_a.artifact_id, importer_opts)
      Process.sleep(10)
      {:ok, only_b} = start_import_run!(artifact_b.artifact_id, importer_opts)

      result =
        Catalog.latest_import_run_by_artifact(organization_id(), mission_id())

      assert result[artifact_a.artifact_id].import_run_id == newer_a.import_run_id
      assert result[artifact_b.artifact_id].import_run_id == only_b.import_run_id
      refute result[artifact_a.artifact_id].import_run_id == older_a.import_run_id
    end

    test "scopes by mission", %{importer_opts: importer_opts} do
      %{organization: _org, mission: mission_a} =
        persist_mission_scope(organization_id(), mission_id())

      other_mission_id = "#{mission_id()}-other"

      # Persist the other mission under the same org.
      {:ok, _} =
        Cadence.Missions.persist_mission(
          Mission.new(%{
            mission_id: other_mission_id,
            organization_id: organization_id(),
            slug: other_mission_id,
            display_name: other_mission_id
          })
        )

      artifact = persist_artifact!("artifact-scope", mission_id: mission_a.mission_id)
      {:ok, _} = start_import_run!(artifact.artifact_id, importer_opts)

      assert Catalog.latest_import_run_by_artifact(
               organization_id(),
               other_mission_id
             ) == %{}
    end
  end

  describe "catalog database revisions" do
    test "creates a database and revision from a successful revision import", %{
      importer_opts: importer_opts
    } do
      persist_mission_scope(organization_id(), mission_id())

      assert {:ok, %Database{} = database} =
               Catalog.create_database(organization_id(), mission_id(), %{
                 name: "Bus Catalog",
                 slug: "bus-catalog",
                 catalog_family: :telemetry,
                 default_importer_key: "fake_tm_json",
                 created_by: %{"service_identity_id" => "svc-bootstrap"}
               })

      artifact =
        Artifact.new(%{
          organization_id: organization_id(),
          mission_id: mission_id(),
          catalog_database_id: database.catalog_database_id,
          catalog_family: :telemetry,
          artifact_name: "bus.json",
          format_key: "fake_tm_json",
          media_type: "application/json",
          source_artifact: %{"packets" => [%{"name" => "HK_PACKET"}]}
        })

      assert {:ok, run} =
               Catalog.start_revision_import(
                 organization_id(),
                 mission_id(),
                 database.catalog_database_id,
                 artifact,
                 "fake_tm_json",
                 catalog_opts(importer_opts,
                   metadata: %{"revision_label" => "FSW 3.7"},
                   requested_by: %{"service_identity_id" => "svc-bootstrap"}
                 )
               )

      assert {:ok, job} = Cadence.Jobs.fetch_job_for_run(:catalog_import_run, run.import_run_id)
      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, _completed_job} = run_catalog_job(job.job_id, importer_opts)

      assert {:ok, completed_run} =
               Cadence.Catalog.fetch_import_run(
                 organization_id(),
                 mission_id(),
                 run.import_run_id
               )

      assert completed_run.status == :completed
      assert completed_run.catalog_database_id == database.catalog_database_id

      assert %{"catalog_revision_id" => revision_id} =
               completed_run.result_document["catalog_revision"]

      assert {:ok, revision} =
               Catalog.fetch_revision(organization_id(), mission_id(), revision_id)

      assert revision.catalog_database_id == database.catalog_database_id
      assert revision.revision_number == 1
      assert revision.revision_label == "FSW 3.7"
      assert revision.import_run_id == completed_run.import_run_id

      assert revision.mission_model_revision_id ==
               completed_run.result_document["mission_model"]["revision_id"]

      assert {:ok, latest} =
               Catalog.latest_revision(
                 organization_id(),
                 mission_id(),
                 database.catalog_database_id
               )

      assert latest.catalog_revision_id == revision.catalog_revision_id

      assert [operational_event] =
               Cadence.OperationalEvents.list_events(organization_id(), mission_id(),
                 category: :catalog,
                 kind: :catalog_revision_registered,
                 source_record_kind: :catalog_revision,
                 source_record_id: revision.catalog_revision_id
               )

      assert operational_event.subject == %{
               kind: :catalog_revision,
               id: revision.catalog_revision_id
             }

      assert operational_event.payload["catalog_database_id"] == database.catalog_database_id
      assert operational_event.payload["revision_number"] == 1
      assert operational_event.payload["revision_label"] == "FSW 3.7"

      assert operational_event.payload["mission_model_revision_id"] ==
               revision.mission_model_revision_id

      assert operational_event.causality.import_run_id == completed_run.import_run_id
    end

    test "successful revision import invalidates matching dashboard runtime caches", %{
      importer_opts: importer_opts
    } do
      cache = start_supervised!({RuntimeCache, name: nil})
      use_dashboard_runtime_cache!(cache)
      persist_mission_scope(organization_id(), mission_id())

      other_mission_id = "mission-catalog-cache-other"
      persist_mission_scope(organization_id(), other_mission_id)

      assert {:ok, %Database{} = database} =
               Catalog.create_database(organization_id(), mission_id(), %{
                 name: "Bus Catalog",
                 slug: "bus-catalog",
                 catalog_family: :telemetry,
                 default_importer_key: "fake_tm_json"
               })

      telemetry_plan_key = dashboard_plan_key(mission_id(), :telemetry)
      limits_plan_key = dashboard_plan_key(mission_id(), :limits)
      other_plan_key = dashboard_plan_key(other_mission_id, :telemetry)
      telemetry_key = dashboard_source_result_key(mission_id(), :telemetry)
      telemetry_frame_key = dashboard_frame_key(telemetry_key, "frame-telemetry")
      limits_key = dashboard_source_result_key(mission_id(), :limits)
      limits_frame_key = dashboard_frame_key(limits_key, "frame-limits")
      other_key = dashboard_source_result_key(other_mission_id, :telemetry)
      other_frame_key = dashboard_frame_key(other_key, "frame-other")

      telemetry_plan = dashboard_plan(mission_id(), :telemetry, telemetry_plan_key)
      limits_plan = dashboard_plan(mission_id(), :limits, limits_plan_key)
      other_plan = dashboard_plan(other_mission_id, :telemetry, other_plan_key)
      telemetry_result = dashboard_source_result(telemetry_key)
      telemetry_frames = dashboard_frames(:telemetry, "frame-telemetry")
      limits_result = dashboard_source_result(limits_key)
      limits_frames = dashboard_frames(:limits, "frame-limits")
      other_result = dashboard_source_result(other_key)
      other_frames = dashboard_frames(:telemetry, "frame-other")

      assert :ok = RuntimeCache.put_plan(telemetry_plan_key, telemetry_plan, cache)
      assert :ok = RuntimeCache.put_plan(limits_plan_key, limits_plan, cache)
      assert :ok = RuntimeCache.put_plan(other_plan_key, other_plan, cache)
      assert :ok = RuntimeCache.put_source_result(telemetry_key, telemetry_result, cache)
      assert :ok = RuntimeCache.put_frame(telemetry_frame_key, telemetry_frames, cache)
      assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)
      assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames, cache)
      assert :ok = RuntimeCache.put_source_result(other_key, other_result, cache)
      assert :ok = RuntimeCache.put_frame(other_frame_key, other_frames, cache)

      artifact =
        Artifact.new(%{
          organization_id: organization_id(),
          mission_id: mission_id(),
          catalog_database_id: database.catalog_database_id,
          catalog_family: :telemetry,
          artifact_name: "bus.json",
          format_key: "fake_tm_json",
          media_type: "application/json",
          source_artifact: %{"packets" => [%{"name" => "HK_PACKET"}]}
        })

      assert {:ok, run} =
               Catalog.start_revision_import(
                 organization_id(),
                 mission_id(),
                 database.catalog_database_id,
                 artifact,
                 "fake_tm_json",
                 importer_opts
               )

      assert {:ok, job} = Cadence.Jobs.fetch_job_for_run(:catalog_import_run, run.import_run_id)
      assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
      assert claimed_job.job_id == job.job_id
      assert {:ok, _completed_job} = run_catalog_job(claimed_job.job_id, importer_opts)

      assert RuntimeCache.get_plan(telemetry_plan_key, cache) == :miss
      assert RuntimeCache.get_plan(limits_plan_key, cache) == :miss
      assert RuntimeCache.get_source_result(telemetry_key, cache) == :miss
      assert RuntimeCache.get_frame(telemetry_frame_key, cache) == :miss
      assert RuntimeCache.get_source_result(limits_key, cache) == :miss
      assert RuntimeCache.get_frame(limits_frame_key, cache) == :miss
      assert {:ok, ^other_plan} = RuntimeCache.get_plan(other_plan_key, cache)
      assert {:ok, ^other_result} = RuntimeCache.get_source_result(other_key, cache)
      assert {:ok, ^other_frames} = RuntimeCache.get_frame(other_frame_key, cache)
    end

    test "does not create a revision for a failed revision import", %{
      importer_opts: importer_opts
    } do
      persist_mission_scope(organization_id(), mission_id())

      {:ok, database} =
        Catalog.create_database(organization_id(), mission_id(), %{
          name: "Bus Catalog",
          slug: "bus-catalog",
          catalog_family: :telemetry
        })

      artifact =
        Artifact.new(%{
          organization_id: organization_id(),
          mission_id: mission_id(),
          catalog_database_id: database.catalog_database_id,
          catalog_family: :telemetry,
          artifact_name: "invalid.json",
          format_key: "fake_tm_json",
          media_type: "application/json",
          source_artifact: %{"not_packets" => []}
        })

      assert {:error, :invalid_fake_tm_json} =
               Catalog.start_revision_import(
                 organization_id(),
                 mission_id(),
                 database.catalog_database_id,
                 artifact,
                 "fake_tm_json",
                 catalog_opts(importer_opts, metadata: %{"revision_label" => "Bad"})
               )

      assert [] =
               Catalog.list_revisions(
                 organization_id(),
                 mission_id(),
                 database.catalog_database_id
               )
    end
  end

  defp persist_artifact!(artifact_id, opts \\ []) do
    artifact =
      Catalog.Artifact.new(%{
        artifact_id: artifact_id,
        organization_id: organization_id(),
        mission_id: Keyword.get(opts, :mission_id, mission_id()),
        catalog_family: :telemetry,
        artifact_name: "#{artifact_id}.json",
        format_key: "fake_tm_json",
        media_type: "application/json",
        source_artifact: %{"packets" => [%{"name" => "HK_#{artifact_id}"}]},
        uploaded_by: %{"service_identity_id" => "svc-test"}
      })

    {:ok, persisted} = Cadence.Catalog.persist_artifact(organization_id(), artifact)
    persisted
  end

  defp start_import_run!(artifact_id, importer_opts) do
    Cadence.Catalog.start_import_run(
      organization_id(),
      mission_id(),
      artifact_id,
      "fake_tm_json",
      catalog_opts(importer_opts, requested_by: %{"service_identity_id" => "svc-test"})
    )
  end

  defp run_catalog_job(job_id, importer_opts) do
    runner =
      JobRunner.new(%{
        catalog_import_run: fn import_run_id ->
          Catalog.execute_enqueued_run(import_run_id, importer_opts)
        end
      })

    JobRunner.run_job(runner, job_id)
  end

  defp catalog_opts(importer_opts, opts), do: Keyword.merge(opts, importer_opts)

  defp use_dashboard_runtime_cache!(cache) do
    start_supervised!(
      {RuntimeFactConsumer, name: nil, enabled?: true, runtime_cache: RuntimeCache.client(cache)}
    )
  end

  defp dashboard_plan_key(mission_id, logical_source) do
    mission_id
    |> dashboard_resolve_request(logical_source)
    |> RuntimeCacheKey.plan()
  end

  defp dashboard_plan(mission_id, logical_source, %RuntimeCacheKey{} = plan_key) do
    %DashboardResolveResult{
      dashboard_id: "dashboard-#{mission_id}-#{logical_source}",
      planned_source_requests: [dashboard_source_request(mission_id, logical_source)],
      plan_metadata: %{cache: %{plan_key: plan_key}}
    }
  end

  defp dashboard_resolve_request(mission_id, logical_source) do
    document = %Document{
      dashboard_id: "dashboard-#{mission_id}-#{logical_source}",
      organization_id: organization_id(),
      mission_id: mission_id,
      name: "Catalog cache dashboard",
      placements: []
    }

    %DashboardResolveRequest{
      organization_id: organization_id(),
      mission_id: mission_id,
      dashboard_id: document.dashboard_id,
      document: document
    }
  end

  defp dashboard_source_result_key(mission_id, logical_source) do
    request = dashboard_source_request(mission_id, logical_source)

    RuntimeCacheKey.source_result(request,
      source_binding: dashboard_source_binding(mission_id, logical_source),
      data_source: dashboard_data_source(mission_id, logical_source),
      watermark: dashboard_watermark(mission_id, logical_source)
    )
  end

  defp dashboard_source_request(mission_id, logical_source) do
    %PlannedSourceRequest{
      request_id: "source-request-#{mission_id}-#{logical_source}",
      organization_id: organization_id(),
      mission_id: mission_id,
      logical_source: logical_source,
      observables: ["HK.counter"],
      sampling: %{mode: :latest}
    }
  end

  defp dashboard_frame_key(%RuntimeCacheKey{} = source_key, frame_id) do
    RuntimeCacheKey.frame(source_key,
      placement_id: "placement-#{frame_id}",
      placement_size: %{width_px: 320, height_px: 120},
      display: %{density: :normal},
      frame_shape: :scalar,
      catalog_revision: "catalog-revision-old"
    )
  end

  defp dashboard_source_result(%RuntimeCacheKey{} = key) do
    %SourceResult{
      request_id: key.parts.request.request_id,
      watermarks: []
    }
  end

  defp dashboard_frames(logical_source, frame_id) do
    [%Frame{frame_id: frame_id, source: logical_source, shape: :scalar, fields: []}]
  end

  defp dashboard_source_binding(mission_id, logical_source) do
    %DataBinding{
      binding_id: "binding-#{mission_id}-#{logical_source}",
      organization_id: organization_id(),
      mission_id: mission_id,
      realm: :flight,
      logical_source: logical_source,
      data_source_id: dashboard_data_source_id(logical_source),
      dataset: dashboard_dataset(logical_source)
    }
  end

  defp dashboard_data_source(mission_id, logical_source) do
    %DataSource{
      data_source_id: dashboard_data_source_id(logical_source),
      owner: :cadence,
      kind: dashboard_source_kind(logical_source),
      adapter: dashboard_source_adapter(logical_source),
      organization_id: organization_id(),
      mission_id: mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{latest?: true, latest_state?: true, event_history?: true, watermarks?: true}
    }
  end

  defp dashboard_watermark(mission_id, logical_source) do
    %SourceWatermark{
      logical_source: logical_source,
      request_id: "source-request-#{mission_id}-#{logical_source}",
      source_binding_id: "binding-#{mission_id}-#{logical_source}",
      data_source_id: dashboard_data_source_id(logical_source),
      realm: :flight,
      dataset: dashboard_dataset(logical_source),
      complete_through: ~U[2026-06-17 12:00:00Z],
      latest_receipt_time: ~U[2026-06-17 12:00:00Z],
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: :best_effort,
      freshness_state: :fresh
    }
  end

  defp dashboard_data_source_id(:telemetry), do: "managed_questdb_primary"
  defp dashboard_data_source_id(:limits), do: "managed_limits_projection"

  defp dashboard_dataset(:telemetry), do: "flight"
  defp dashboard_dataset(:limits), do: "telemetry_latest_limit_states"

  defp dashboard_source_kind(:limits), do: :projection
  defp dashboard_source_kind(_logical_source), do: :managed_tsdb

  defp dashboard_source_adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry
  defp dashboard_source_adapter(:limits), do: Cadence.Dashboards.Sources.Limits
end
