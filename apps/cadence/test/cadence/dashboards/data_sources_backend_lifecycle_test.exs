defmodule Cadence.Dashboards.DataSourcesBackendLifecycleTest do
  use Cadence.ConfigCase, async: false

  import Cadence.Dashboards.DataSourcesFixtures

  alias Cadence.Dashboards.{
    DataSource,
    DataSources,
    SourceCredentials,
    TSDBBackendLifecycleJobs,
    TSDBDeploymentStatus
  }

  alias Cadence.Jobs

  setup do
    persist_mission_scope("org-dash-source", "mission-dash-source")
    :ok
  end

  test "persists BYO TSDB data sources with dedicated mission isolation" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-dedicated-mission-byo",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "dedicated-mission-byo",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/dedicated-mission"}
             })

    assert {:ok, persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "dedicated-mission-byo",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               credentials_ref: "cred-dedicated-mission-byo",
               capabilities: %{range_scan?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://customer/dedicated-mission"
               }
             })

    assert persisted.owner == :customer
    assert persisted.kind == :byo_tsdb
    assert persisted.isolation_level == :mission_isolated

    assert %{
             physical_boundary: :mission,
             organization_id: "org-dash-source",
             mission_id: "mission-dash-source",
             endpoint_ref: "endpoint://customer/dedicated-mission"
           } = DataSource.isolation_profile(persisted)

    assert %{
             status: :external,
             mode: :byo_tsdb,
             backend: :questdb,
             physical_boundary: :mission,
             remediation: "monitor_customer_dedicated_mission_backend"
           } = TSDBDeploymentStatus.from_data_source(persisted)
  end

  test "reconciles dedicated BYO TSDB backend lifecycle state" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-reconcile-dedicated-byo",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "reconcile-dedicated-byo",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/reconcile-dedicated"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "reconcile-dedicated-byo",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               credentials_ref: "cred-reconcile-dedicated-byo",
               capabilities: %{range_scan?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://customer/reconcile-dedicated"
               }
             })

    occurred_at = ~U[2026-07-07 15:30:00Z]

    assert {:ok, reconciled} =
             DataSources.reconcile_tsdb_backend(
               "reconcile-dedicated-byo",
               %{},
               actor_id: "operator-1",
               occurred_at: occurred_at,
               payload: %{source: "test"}
             )

    assert reconciled.metadata["tsdb_backend_lifecycle"] == %{
             "operation" => "reconcile",
             "status" => "reconciled",
             "reconciled_at" => "2026-07-07T15:30:00Z",
             "backend" => "questdb",
             "physical_boundary" => "mission",
             "endpoint_ref" => "endpoint://customer/reconcile-dedicated"
           }

    assert %{
             lifecycle_operation_text: "reconcile",
             lifecycle_status_text: "reconciled",
             lifecycle_observed_at_text: "2026-07-07T15:30:00Z"
           } = TSDBDeploymentStatus.from_data_source(reconciled)

    events =
      DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
        data_source_id: "reconcile-dedicated-byo"
      )

    assert changed_event = Enum.find(events, &(&1.event_type == :changed))
    assert registered_event = Enum.find(events, &(&1.event_type == :registered))

    assert changed_event.event_type == :changed
    assert changed_event.actor_id == "operator-1"
    assert changed_event.payload["source"] == "test"
    assert changed_event.payload["operation"] == "reconcile_tsdb_backend"
    assert changed_event.payload["deployment_backend"] == "questdb"
    assert changed_event.payload["deployment_boundary"] == "mission"
    assert changed_event.payload["lifecycle_status"] == "reconciled"
    assert changed_event.current_metadata["tsdb_backend_lifecycle"]["status"] == "reconciled"
    assert registered_event.event_type == :registered
  end

  test "requests dedicated BYO TSDB backend deprovisioning" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-deprovision-dedicated-byo",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "deprovision-dedicated-byo",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/deprovision-dedicated"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "deprovision-dedicated-byo",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               credentials_ref: "cred-deprovision-dedicated-byo",
               capabilities: %{range_scan?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://customer/deprovision-dedicated"
               }
             })

    occurred_at = ~U[2026-07-07 16:00:00Z]

    assert {:ok, deprovisioned} =
             DataSources.request_tsdb_backend_deprovisioning(
               "deprovision-dedicated-byo",
               %{},
               actor_id: "operator-1",
               occurred_at: occurred_at,
               payload: %{source: "test"}
             )

    assert deprovisioned.status == :disabled
    assert DateTime.truncate(deprovisioned.disabled_at, :second) == occurred_at

    assert deprovisioned.metadata["tsdb_backend_lifecycle"] == %{
             "operation" => "deprovision",
             "status" => "deprovision_requested",
             "deprovision_requested_at" => "2026-07-07T16:00:00Z",
             "backend" => "questdb",
             "physical_boundary" => "mission",
             "endpoint_ref" => "endpoint://customer/deprovision-dedicated"
           }

    assert %{
             lifecycle_operation_text: "deprovision",
             lifecycle_status_text: "deprovision_requested",
             lifecycle_observed_at_text: "2026-07-07T16:00:00Z"
           } = TSDBDeploymentStatus.from_data_source(deprovisioned)

    events =
      DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
        data_source_id: "deprovision-dedicated-byo"
      )

    assert disabled_event = Enum.find(events, &(&1.event_type == :disabled))
    assert registered_event = Enum.find(events, &(&1.event_type == :registered))

    assert disabled_event.actor_id == "operator-1"
    assert disabled_event.payload["source"] == "test"
    assert disabled_event.payload["operation"] == "request_tsdb_backend_deprovisioning"
    assert disabled_event.payload["deployment_backend"] == "questdb"
    assert disabled_event.payload["deployment_boundary"] == "mission"
    assert disabled_event.payload["lifecycle_status"] == "deprovision_requested"

    assert disabled_event.current_metadata["tsdb_backend_lifecycle"]["status"] ==
             "deprovision_requested"

    assert registered_event.event_type == :registered
  end

  test "worker completes dedicated BYO TSDB backend provisioning" do
    test_pid = self()
    previous_config = Application.get_env(:cadence, :dashboard_tsdb_backend_lifecycle)

    Application.put_env(:cadence, :dashboard_tsdb_backend_lifecycle,
      executor: fn payload, opts ->
        send(test_pid, {:tsdb_backend_lifecycle_executor, payload, opts})
        {:ok, %{"status" => "physical_provisioned"}}
      end,
      execution_opts: [worker: "test-lifecycle-worker"]
    )

    on_exit(fn ->
      case previous_config do
        nil -> Application.delete_env(:cadence, :dashboard_tsdb_backend_lifecycle)
        config -> Application.put_env(:cadence, :dashboard_tsdb_backend_lifecycle, config)
      end
    end)

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-worker-provision-byo",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "worker-provision-byo",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/worker-provision"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "worker-provision-byo",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               credentials_ref: "cred-worker-provision-byo",
               capabilities: %{range_scan?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://customer/worker-provision"
               }
             })

    assert {:ok, requested_source, queued_job} =
             TSDBBackendLifecycleJobs.request_provisioning(
               "worker-provision-byo",
               %{},
               actor_id: "operator-1",
               payload: %{source: "test"},
               run_id: "worker-provision-run"
             )

    assert requested_source.status == :active
    assert requested_source.metadata["tsdb_backend_lifecycle"]["status"] == "provision_requested"
    assert queued_job.job_type == :dashboard_tsdb_backend_lifecycle
    assert queued_job.run_id == "worker-provision-run"
    assert queued_job.payload["operation"] == "provision"
    assert queued_job.payload["provisioning_kind"] == "byo_tsdb"
    assert queued_job.payload["data_source_id"] == "worker-provision-byo"
    assert queued_job.payload["physical_boundary"] == "mission"

    assert [claimed_job] = Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.status == :running

    assert {:ok, completed_job} = Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert_receive {:tsdb_backend_lifecycle_executor, executor_payload, executor_opts}
    assert executor_payload["operation"] == "provision"
    assert executor_payload["data_source_id"] == "worker-provision-byo"
    assert executor_opts[:worker] == "test-lifecycle-worker"

    assert {:ok, completed_source} = DataSources.fetch_data_source("worker-provision-byo")
    assert completed_source.status == :active
    assert completed_source.disabled_at == nil

    assert completed_source.metadata["tsdb_backend_lifecycle"]["status"] == "provisioned"
    assert completed_source.metadata["tsdb_backend_lifecycle"]["operation"] == "provision"
    assert completed_source.metadata["tsdb_backend_lifecycle"]["job_id"] == queued_job.job_id
    assert completed_source.metadata["tsdb_backend_lifecycle"]["run_id"] == queued_job.run_id

    assert completed_source.metadata["tsdb_backend_lifecycle"]["executor_status"] ==
             "physical_provisioned"

    events =
      DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
        data_source_id: "worker-provision-byo"
      )

    assert completed_event =
             Enum.find(
               events,
               &(&1.payload["operation"] == "complete_tsdb_backend_provisioning")
             )

    assert completed_event.actor_id == "dashboard_tsdb_backend_lifecycle_worker"
    assert completed_event.payload["job_id"] == queued_job.job_id
    assert completed_event.payload["run_id"] == queued_job.run_id
    assert completed_event.current_metadata["tsdb_backend_lifecycle"]["status"] == "provisioned"
  end

  test "worker completes dedicated BYO TSDB backend deprovisioning" do
    test_pid = self()
    previous_config = Application.get_env(:cadence, :dashboard_tsdb_backend_lifecycle)

    Application.put_env(:cadence, :dashboard_tsdb_backend_lifecycle,
      executor: fn payload, opts ->
        send(test_pid, {:tsdb_backend_lifecycle_executor, payload, opts})
        {:ok, %{"status" => "physical_deprovisioned"}}
      end,
      execution_opts: [worker: "test-lifecycle-worker"]
    )

    on_exit(fn ->
      case previous_config do
        nil -> Application.delete_env(:cadence, :dashboard_tsdb_backend_lifecycle)
        config -> Application.put_env(:cadence, :dashboard_tsdb_backend_lifecycle, config)
      end
    end)

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-worker-deprovision-byo",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "worker-deprovision-byo",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/worker-deprovision"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "worker-deprovision-byo",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               credentials_ref: "cred-worker-deprovision-byo",
               capabilities: %{range_scan?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://customer/worker-deprovision"
               }
             })

    assert {:ok, requested_source, queued_job} =
             TSDBBackendLifecycleJobs.request_deprovisioning(
               "worker-deprovision-byo",
               %{},
               actor_id: "operator-1",
               payload: %{source: "test"},
               run_id: "worker-deprovision-run"
             )

    assert requested_source.status == :disabled
    assert queued_job.job_type == :dashboard_tsdb_backend_lifecycle
    assert queued_job.run_id == "worker-deprovision-run"
    assert queued_job.payload["operation"] == "deprovision"
    assert queued_job.payload["provisioning_kind"] == "byo_tsdb"
    assert queued_job.payload["data_source_id"] == "worker-deprovision-byo"
    assert queued_job.payload["physical_boundary"] == "mission"

    assert [claimed_job] = Jobs.claim_jobs(1)
    assert claimed_job.job_id == queued_job.job_id
    assert claimed_job.status == :running

    assert {:ok, completed_job} = Jobs.run_job(claimed_job.job_id)
    assert completed_job.status == :completed

    assert_receive {:tsdb_backend_lifecycle_executor, executor_payload, executor_opts}
    assert executor_payload["operation"] == "deprovision"
    assert executor_payload["data_source_id"] == "worker-deprovision-byo"
    assert executor_opts[:worker] == "test-lifecycle-worker"

    assert {:ok, completed_source} = DataSources.fetch_data_source("worker-deprovision-byo")
    assert completed_source.status == :disabled

    assert completed_source.metadata["tsdb_backend_lifecycle"]["status"] == "deprovisioned"
    assert completed_source.metadata["tsdb_backend_lifecycle"]["operation"] == "deprovision"
    assert completed_source.metadata["tsdb_backend_lifecycle"]["job_id"] == queued_job.job_id
    assert completed_source.metadata["tsdb_backend_lifecycle"]["run_id"] == queued_job.run_id

    assert completed_source.metadata["tsdb_backend_lifecycle"]["executor_status"] ==
             "physical_deprovisioned"

    events =
      DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
        data_source_id: "worker-deprovision-byo"
      )

    assert completed_event =
             Enum.find(
               events,
               &(&1.payload["operation"] == "complete_tsdb_backend_deprovisioning")
             )

    assert completed_event.actor_id == "dashboard_tsdb_backend_lifecycle_worker"
    assert completed_event.payload["job_id"] == queued_job.job_id
    assert completed_event.payload["run_id"] == queued_job.run_id
    assert completed_event.current_metadata["tsdb_backend_lifecycle"]["status"] == "deprovisioned"
  end

  test "reconcile TSDB backend requires a dedicated BYO source" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-customer-reconcile-byo",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "customer-reconcile-byo",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/reconcile"}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "customer-reconcile-byo",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :customer_owned,
               credentials_ref: "cred-customer-reconcile-byo",
               capabilities: %{range_scan?: true},
               metadata: %{storage: :questdb}
             })

    assert {:error, :dedicated_tsdb_backend_required} =
             DataSources.reconcile_tsdb_backend("customer-reconcile-byo")

    assert {:error, :dedicated_tsdb_backend_required} =
             DataSources.request_tsdb_backend_deprovisioning("customer-reconcile-byo")

    assert {:ok, _managed} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "managed-reconcile-questdb",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true},
               metadata: %{storage: :questdb}
             })

    assert {:error, :byo_tsdb_backend_required} =
             DataSources.reconcile_tsdb_backend("managed-reconcile-questdb")

    assert {:error, :byo_tsdb_backend_required} =
             DataSources.request_tsdb_backend_deprovisioning("managed-reconcile-questdb")
  end

  test "rejects unsafe BYO data source configurations before persistence" do
    data_source = %DataSource{
      data_source_id: "unsafe-byo-questdb",
      owner: :cadence,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      isolation_level: :shared,
      capabilities: %{range_scan?: true},
      metadata: %{connection: %{password: "plaintext"}}
    }

    assert {:error, %Ecto.Changeset{} = changeset} = DataSources.persist_data_source(data_source)

    assert "must be customer for BYO TSDB data sources" in field_errors(changeset, :owner)

    assert "must be customer_owned, org_isolated, or mission_isolated for BYO TSDB data sources" in field_errors(
             changeset,
             :isolation_level
           )

    assert "must be set for BYO TSDB data sources" in field_errors(changeset, :organization_id)
    assert "must be set for BYO TSDB data sources" in field_errors(changeset, :credentials_ref)

    assert "must not embed credentials or secrets; use credentials_ref" in metadata_errors(
             changeset
           )
  end

  test "rejects isolated data sources without the matching semantic scope" do
    org_isolated_source = %DataSource{
      data_source_id: "org-isolated-without-org",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      isolation_level: :org_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:error, %Ecto.Changeset{} = org_changeset} =
             DataSources.persist_data_source(org_isolated_source)

    assert "must be set for org-isolated data sources" in field_errors(
             org_changeset,
             :organization_id
           )

    mission_isolated_source = %DataSource{
      data_source_id: "mission-isolated-without-mission",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:error, %Ecto.Changeset{} = mission_changeset} =
             DataSources.persist_data_source(mission_isolated_source)

    assert "must be set for mission-isolated data sources" in field_errors(
             mission_changeset,
             :mission_id
           )
  end
end
