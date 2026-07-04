defmodule Cadence.Dashboards.ManagedQuestDBProvisioningJobsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards.{DataSources, ManagedQuestDBProvisioningJobs}

  @organization_id "org-managed-questdb-provisioning-jobs"
  @mission_id "mission-managed-questdb-provisioning-jobs"
  @data_source_id "mission-managed-questdb-provisioning-job-source"
  @run_id "managed-questdb-provisioning-run"

  setup do
    previous_config = Application.get_env(:cadence, :dashboard_managed_questdb_provisioning)

    on_exit(fn ->
      if is_nil(previous_config) do
        Application.delete_env(:cadence, :dashboard_managed_questdb_provisioning)
      else
        Application.put_env(:cadence, :dashboard_managed_questdb_provisioning, previous_config)
      end
    end)

    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "enqueues a durable provisioning request without secret material" do
    assert {:ok, job} =
             Cadence.Dashboards.enqueue_managed_questdb_provisioning(
               attrs(%{
                 http_endpoint: "http://mission-questdb:9000",
                 password: "quest-password",
                 exec_fun: fn _sql, _opts -> {:ok, []} end,
                 migrator: fn _config -> {:ok, []} end
               }),
               run_id: @run_id
             )

    assert job.job_type == :managed_questdb_provisioning
    assert job.run_id == @run_id
    assert job.status == :queued
    assert job.payload["data_source_id"] == @data_source_id
    assert job.payload["organization_id"] == @organization_id
    assert job.payload["mission_id"] == @mission_id
    assert job.payload["http_endpoint"] == "http://mission-questdb:9000"
    assert job.payload["redacted_fields"] == ["password", "exec_fun", "migrator"]
    refute Map.has_key?(job.payload, "password")
    refute Map.has_key?(job.payload, "exec_fun")
    refute Map.has_key?(job.payload, "migrator")
    refute inspect(job) =~ "quest-password"
  end

  test "runs a queued provisioning job through the managed provisioner" do
    migration = migration("20260630020202", "job_provisioned")

    Application.put_env(:cadence, :dashboard_managed_questdb_provisioning,
      execution_opts: [
        migrator: fn migration_config ->
          assert migration_config[:http_endpoint] == "http://mission-questdb:9000"
          {:ok, [migration]}
        end
      ]
    )

    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{http_endpoint: "http://mission-questdb:9000"}),
               run_id: @run_id
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert claimed_job.status == :running

    assert {:ok, completed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed
    assert completed_job.attempt_count == 1
    assert completed_job.failure_reason == nil

    assert {:ok, persisted} = DataSources.fetch_data_source(@data_source_id)
    assert persisted.metadata["provisioning"]["applied_migration_versions"] == ["20260630020202"]
    refute inspect(completed_job) =~ "quest-password"
  end

  test "marks provisioning job failed with redacted failure evidence when execution fails" do
    Application.put_env(:cadence, :dashboard_managed_questdb_provisioning,
      provisioner: fn attrs, _opts ->
        assert attrs["data_source_id"] == @data_source_id
        {:error, {:questdb_unavailable, endpoint: "redacted-endpoint-ref"}}
      end
    )

    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{password: "quest-password"}),
               run_id: @run_id
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert {:ok, failed_job} = Cadence.Jobs.run_job(claimed_job.job_id)

    assert failed_job.job_id == job.job_id
    assert failed_job.status == :failed
    assert failed_job.attempt_count == 1

    assert failed_job.failure_reason["tuple"] == [
             "questdb_unavailable",
             [%{"tuple" => ["endpoint", "redacted-endpoint-ref"]}]
           ]

    refute inspect(failed_job) =~ "quest-password"
    assert {:error, :data_source_not_found} = DataSources.fetch_data_source(@data_source_id)
  end

  test "retry preserves the redacted durable request for a later provisioning attempt" do
    test_pid = self()

    Application.put_env(:cadence, :dashboard_managed_questdb_provisioning,
      provisioner: fn _attrs, _opts ->
        send(test_pid, :provisioner_called)
        {:error, :first_attempt_failed}
      end
    )

    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{password: "quest-password"}),
               run_id: @run_id
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert {:ok, failed_job} = Cadence.Jobs.run_job(claimed_job.job_id)
    assert failed_job.status == :failed
    assert_receive :provisioner_called

    assert {:ok, retried_job} = Cadence.Jobs.retry_failed_job(job.job_id)
    assert retried_job.status == :queued
    assert retried_job.payload == job.payload
    refute inspect(retried_job) =~ "quest-password"
  end

  test "requires mission scope before a provisioning request can be queued" do
    assert {:error, {:required_managed_questdb_job_field_missing, :mission_id}} =
             ManagedQuestDBProvisioningJobs.enqueue(attrs(%{mission_id: nil}))
  end

  defp attrs(overrides) do
    %{
      data_source_id: @data_source_id,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      endpoint_ref: "endpoint://cadence/mission-questdb",
      topology_ref: "topology://cadence/mission-questdb",
      actor_id: "operator-1"
    }
    |> Map.merge(overrides)
  end

  defp migration(version, name) do
    %{
      version: version,
      name: name,
      path: "/tmp/#{version}_#{name}.sql",
      sql: "SELECT 1",
      checksum: "checksum-#{version}"
    }
  end
end
