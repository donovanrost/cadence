defmodule Cadence.Control.DataSources.ManagedQuestDBProvisioningJobsTest do
  use Cadence.DataCase, async: true
  use GenServer

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs
  alias Cadence.Control.ManagedResources

  alias Cadence.DataSources.{DataSourceEvent, DeploymentStatus, Facts}

  alias Cadence.Management.DataSources
  alias Cadence.Platform.EventBus

  @organization_id "org-managed-questdb-provisioning-jobs"
  @mission_id "mission-managed-questdb-provisioning-jobs"
  @data_source_id "mission-managed-questdb-provisioning-job-source"
  @run_id "managed-questdb-provisioning-run"
  @event_bus __MODULE__.EventBus

  setup_all do
    start_supervised!({EventBus, name: @event_bus, delivery: :sync, before_notify: nil})
    :ok
  end

  setup do
    persist_mission_scope(@organization_id, @mission_id)

    forwarder = start_fact_forwarder()
    assert_receive {:managed_questdb_job_fact_forwarder_ready, ^forwarder}

    :ok
  end

  test "enqueues a durable provisioning request without secret material" do
    assert {:ok, job} =
             ManagedResources.enqueue_managed_questdb(
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

    assert %{
             status: :queued,
             mode: :managed_questdb,
             backend: :questdb,
             physical_boundary: :mission,
             remediation: "wait_for_provisioning_worker"
           } = DeploymentStatus.from_job(job)
  end

  test "runs a queued provisioning job through the managed provisioner" do
    migration = migration("20260630020202", "job_provisioned")

    policy =
      ManagedQuestDBProvisioningJobs.policy(
        execution_opts: [
          event_bus: @event_bus,
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
    assert DeploymentStatus.from_job(claimed_job).status == :provisioning

    assert {:ok, completed_job} = run_job(claimed_job.job_id, policy)
    assert completed_job.status == :completed
    assert completed_job.attempt_count == 1
    assert completed_job.failure_reason == nil

    assert_receive {:managed_questdb_job_fact,
                    %DataSourceEvent{
                      data_source_id: @data_source_id,
                      payload: %{"kind" => "managed_questdb_provisioned"}
                    }}

    assert {:ok, persisted} = DataSources.fetch_data_source(@data_source_id)
    assert persisted.metadata["provisioning"]["applied_migration_versions"] == ["20260630020202"]
    refute inspect(completed_job) =~ "quest-password"
  end

  test "marks provisioning job failed with redacted failure evidence when execution fails" do
    policy =
      provisioning_policy(fn attrs, _opts ->
        assert attrs["data_source_id"] == @data_source_id
        {:error, {:questdb_unavailable, endpoint: "redacted-endpoint-ref"}}
      end)

    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{password: "quest-password"}),
               run_id: @run_id
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert {:ok, failed_job} = run_job(claimed_job.job_id, policy)

    assert failed_job.job_id == job.job_id
    assert failed_job.status == :failed
    assert DeploymentStatus.from_job(failed_job).status == :failed

    assert DeploymentStatus.from_job(failed_job).remediation ==
             "inspect_provisioning_job_and_retry"

    assert failed_job.attempt_count == 1

    assert failed_job.failure_reason["tuple"] == [
             "questdb_unavailable",
             [%{"tuple" => ["endpoint", "redacted-endpoint-ref"]}]
           ]

    refute inspect(failed_job) =~ "quest-password"
    assert {:error, :data_source_not_found} = DataSources.fetch_data_source(@data_source_id)
  end

  test "lists managed QuestDB provisioning runs for a mission" do
    persist_mission_scope(@organization_id, "other-managed-questdb-provisioning-jobs")

    policy =
      provisioning_policy(fn attrs, _opts ->
        assert attrs["data_source_id"] == "failed-managed-questdb-source"
        {:error, {:questdb_unavailable, endpoint: "redacted-endpoint-ref"}}
      end)

    assert {:ok, failed_job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{
                 data_source_id: "failed-managed-questdb-source",
                 provisioning_run_id: "failed-managed-questdb-run"
               })
             )

    assert [claimed_failed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_failed_job.job_id == failed_job.job_id
    assert {:ok, failed_job} = run_job(claimed_failed_job.job_id, policy)

    assert {:ok, queued_job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{
                 data_source_id: "queued-managed-questdb-source",
                 provisioning_run_id: "queued-managed-questdb-run"
               })
             )

    assert {:ok, _other_job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{
                 data_source_id: "other-managed-questdb-source",
                 mission_id: "other-managed-questdb-provisioning-jobs",
                 provisioning_run_id: "other-managed-questdb-run"
               })
             )

    runs = ManagedResources.list_managed_questdb_runs(@mission_id, limit: 10)
    failed_run = Enum.find(runs, &(&1.run_id == "failed-managed-questdb-run"))
    queued_run = Enum.find(runs, &(&1.run_id == "queued-managed-questdb-run"))

    assert failed_run.job_id == failed_job.job_id
    assert failed_run.run_id == "failed-managed-questdb-run"
    assert failed_run.data_source_id == "failed-managed-questdb-source"
    assert failed_run.status == :failed
    assert failed_run.status_text == "failed"
    assert failed_run.backend_text == "questdb"
    assert failed_run.physical_boundary_text == "mission"
    assert failed_run.failure_summary == "questdb_unavailable"
    assert failed_run.remediation == "inspect_provisioning_job_and_retry"

    assert queued_run.job_id == queued_job.job_id
    assert queued_run.run_id == "queued-managed-questdb-run"
    assert queued_run.data_source_id == "queued-managed-questdb-source"
    assert queued_run.status == :queued
    assert queued_run.failure_summary == "none"

    refute Enum.any?([failed_run, queued_run], &(&1.run_id == "other-managed-questdb-run"))
  end

  test "retry preserves the redacted durable request for a later provisioning attempt" do
    test_pid = self()

    policy =
      provisioning_policy(fn _attrs, _opts ->
        send(test_pid, :provisioner_called)
        {:error, :first_attempt_failed}
      end)

    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{password: "quest-password"}),
               run_id: @run_id
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert {:ok, failed_job} = run_job(claimed_job.job_id, policy)
    assert failed_job.status == :failed
    assert_receive :provisioner_called

    assert {:ok, retried_job} = Cadence.Jobs.retry_failed_job(job.job_id)
    assert retried_job.status == :queued
    assert retried_job.payload == job.payload
    refute inspect(retried_job) =~ "quest-password"
  end

  test "retries failed managed QuestDB provisioning runs through the control boundary" do
    policy =
      provisioning_policy(fn attrs, _opts ->
        assert attrs["data_source_id"] == @data_source_id
        {:error, :questdb_unavailable}
      end)

    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{password: "quest-password"}),
               run_id: @run_id
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert {:ok, failed_job} = run_job(claimed_job.job_id, policy)
    assert failed_job.status == :failed

    assert {:ok, retried_run} =
             ManagedResources.retry_deployment_run(job.job_id)

    assert retried_run.job_id == job.job_id
    assert retried_run.run_id == @run_id
    assert retried_run.status == :queued
    assert retried_run.status_text == "queued"
    assert retried_run.failure_summary == "none"
    assert retried_run.remediation == "wait_for_provisioning_worker"
    refute inspect(retried_run.job) =~ "quest-password"
  end

  test "does not retry unrelated jobs through the managed-resource control boundary" do
    assert {:ok, job} =
             Cadence.Jobs.enqueue(:catalog_import_run, @mission_id, "catalog-import-run", %{})

    assert {:error, {:unsupported_deployment_job, :catalog_import_run}} =
             ManagedResources.retry_deployment_run(job.job_id)
  end

  test "requeues running managed QuestDB provisioning runs through the control boundary" do
    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{password: "quest-password"}),
               run_id: @run_id
             )

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == job.job_id
    assert claimed_job.status == :running

    assert {:ok, requeued_run} =
             ManagedResources.requeue_deployment_run(job.job_id)

    assert requeued_run.job_id == job.job_id
    assert requeued_run.run_id == @run_id
    assert requeued_run.status == :queued
    assert requeued_run.status_text == "queued"
    assert requeued_run.failure_summary == "managed_questdb_provisioning_requeued"
    assert requeued_run.remediation == "wait_for_provisioning_worker"
    refute inspect(requeued_run.job) =~ "quest-password"
  end

  test "does not requeue non-running managed QuestDB provisioning runs" do
    assert {:ok, job} =
             ManagedQuestDBProvisioningJobs.enqueue(
               attrs(%{password: "quest-password"}),
               run_id: @run_id
             )

    assert {:error, {:job_not_running, :queued}} =
             ManagedResources.requeue_deployment_run(job.job_id)
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

  defp provisioning_policy(provisioner) do
    ManagedQuestDBProvisioningJobs.policy(
      provisioner: provisioner,
      execution_opts: [event_bus: @event_bus]
    )
  end

  defp run_job(job_id, policy) do
    runner =
      JobRunner.new(%{
        ManagedQuestDBProvisioningJobs.job_type() =>
          ManagedQuestDBProvisioningJobs.handler(policy)
      })

    JobRunner.run_job(runner, job_id)
  end

  defp start_fact_forwarder do
    start_supervised!(%{
      id: {:managed_questdb_job_fact_forwarder, make_ref()},
      start: {__MODULE__, :start_link, [[owner: self(), event_bus: @event_bus]]},
      restart: :temporary
    })
  end

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    event_bus = Keyword.fetch!(opts, :event_bus)

    :ok = Facts.subscribe(event_bus, self())
    send(owner, {:managed_questdb_job_fact_forwarder_ready, self()})

    {:ok, owner}
  end

  @impl true
  def handle_call({:cadence_fact, _topic, fact}, _from, owner) do
    send(owner, {:managed_questdb_job_fact, fact})
    {:reply, :ok, owner}
  end
end
