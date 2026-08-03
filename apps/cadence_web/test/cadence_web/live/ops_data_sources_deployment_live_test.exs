defmodule CadenceWeb.OpsDataSourcesDeploymentLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Dashboards.{
    DataSource,
    DataSources,
    ManagedQuestDBProvisioningJobs,
    SourceCredentials,
    SourceHealth
  }

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")

    {TestFixtures.member_conn(user), user, org, mission}
  end

  test "renders managed TSDB deployment status on source rows" do
    {conn, _user, org, mission} = signed_in_org_and_mission()

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "managed-mission-questdb",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{
                 storage: :questdb,
                 provisioning_mode: :managed_questdb,
                 provisioning: %{
                   provisioner: :managed_questdb,
                   storage: :questdb,
                   deployment_backend: :questdb,
                   deployment_status: :ready,
                   physical_boundary: :mission,
                   applied_migration_count: 2,
                   applied_migration_versions: ["20260630010101", "20260630020202"]
                 }
               }
             })

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    assert has_element?(
             view,
             ~s(#data-source-managed-mission-questdb[data-source-deployment-status="ready"][data-source-deployment-mode="managed_questdb"][data-source-deployment-backend="questdb"][data-source-deployment-boundary="mission"][data-source-deployment-remediation="probe_source_health"]),
             "deploy fix"
           )
  end

  test "registers dedicated mission BYO TSDB sources with deployment posture" do
    {conn, user, org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    view
    |> form("#register-source-form",
      source: %{
        data_source_id: "dedicated-mission-questdb",
        logical_source: "telemetry",
        kind: "byo_tsdb",
        isolation_level: "mission_isolated",
        credentials_ref: "cred-dedicated-mission-questdb",
        credential_provider: "questdb",
        endpoint_ref: "endpoint://customer/dedicated-mission",
        storage: "questdb"
      }
    )
    |> render_submit()

    assert has_element?(
             view,
             ~s(#data-source-dedicated-mission-questdb[data-source-deployment-status="external"][data-source-deployment-mode="byo_tsdb"][data-source-deployment-backend="questdb"][data-source-deployment-boundary="mission"][data-source-deployment-remediation="monitor_customer_dedicated_mission_backend"]),
             "dedicated-mission-questdb"
           )

    assert {:ok, source} = DataSources.fetch_data_source("dedicated-mission-questdb")
    assert source.owner == :customer
    assert source.kind == :byo_tsdb
    assert source.organization_id == org.organization_id
    assert source.mission_id == mission.mission_id
    assert source.isolation_level == :mission_isolated
    assert source.credentials_ref == "cred-dedicated-mission-questdb"
    assert source.metadata["endpoint_ref"] == "endpoint://customer/dedicated-mission"

    assert {:ok, reference} = SourceCredentials.fetch_reference("cred-dedicated-mission-questdb")
    assert reference.organization_id == org.organization_id
    assert reference.mission_id == mission.mission_id
    assert reference.data_source_id == "dedicated-mission-questdb"
    assert reference.kind == :byo_tsdb_connection

    view
    |> element("#provision-backend-dedicated-mission-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-dedicated-mission-questdb[data-source-deployment-lifecycle-operation="provision"][data-source-deployment-lifecycle-status="provision_requested"]),
             "provision_requested"
           )

    refute has_element?(view, "#provision-backend-dedicated-mission-questdb")

    assert has_element?(
             view,
             ~s([data-deployment-run-data-source-id="dedicated-mission-questdb"][data-deployment-run-status="queued"][data-deployment-run-mode="byo_tsdb"][data-deployment-run-boundary="mission"][data-deployment-run-remediation="wait_for_tsdb_lifecycle_worker"]),
             "dedicated-mission-questdb"
           )

    view
    |> element("#reconcile-backend-dedicated-mission-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-dedicated-mission-questdb[data-source-deployment-lifecycle-operation="reconcile"][data-source-deployment-lifecycle-status="reconciled"]),
             "reconciled"
           )

    assert {:ok, reconciled_source} =
             DataSources.fetch_data_source("dedicated-mission-questdb")

    assert reconciled_source.metadata["tsdb_backend_lifecycle"]["operation"] == "reconcile"
    assert reconciled_source.metadata["tsdb_backend_lifecycle"]["status"] == "reconciled"
    assert reconciled_source.metadata["tsdb_backend_lifecycle"]["backend"] == "questdb"
    assert reconciled_source.metadata["tsdb_backend_lifecycle"]["physical_boundary"] == "mission"

    assert [changed_event | _events] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "dedicated-mission-questdb"
             )

    assert changed_event.event_type == :changed
    assert changed_event.actor_id == user.user_id
    assert changed_event.payload["source"] == "ops_data_sources_live"
    assert changed_event.payload["operation"] == "reconcile_tsdb_backend"
    assert changed_event.payload["deployment_boundary"] == "mission"
    assert changed_event.current_metadata["tsdb_backend_lifecycle"]["status"] == "reconciled"

    view
    |> element("#deprovision-backend-dedicated-mission-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-dedicated-mission-questdb[data-source-status="disabled"][data-source-deployment-lifecycle-operation="deprovision"][data-source-deployment-lifecycle-status="deprovision_requested"]),
             "deprovision_requested"
           )

    refute has_element?(view, "#enable-source-dedicated-mission-questdb")

    assert has_element?(
             view,
             ~s([data-deployment-run-data-source-id="dedicated-mission-questdb"][data-deployment-run-status="queued"][data-deployment-run-mode="byo_tsdb"][data-deployment-run-boundary="mission"][data-deployment-run-remediation="wait_for_tsdb_lifecycle_worker"]),
             "dedicated-mission-questdb"
           )

    assert {:ok, deprovisioned_source} =
             DataSources.fetch_data_source("dedicated-mission-questdb")

    assert deprovisioned_source.status == :disabled
    assert deprovisioned_source.disabled_at
    assert deprovisioned_source.metadata["tsdb_backend_lifecycle"]["operation"] == "deprovision"

    assert deprovisioned_source.metadata["tsdb_backend_lifecycle"]["status"] ==
             "deprovision_requested"

    assert [disabled_event | _events] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "dedicated-mission-questdb"
             )

    assert disabled_event.event_type == :disabled
    assert disabled_event.actor_id == user.user_id
    assert disabled_event.payload["source"] == "ops_data_sources_live"
    assert disabled_event.payload["operation"] == "request_tsdb_backend_deprovisioning"
    assert disabled_event.payload["deployment_boundary"] == "mission"

    assert disabled_event.current_metadata["tsdb_backend_lifecycle"]["status"] ==
             "deprovision_requested"
  end

  test "renders source probe policy on BYO source rows" do
    {conn, _user, org, mission} = signed_in_org_and_mission()

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-policy-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               data_source_id: "policy-customer-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/policy"}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "policy-customer-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :customer_owned,
               credentials_ref: "cred-policy-questdb",
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{
                 storage: :questdb,
                 probe_policy: %{id: "customer-policy", stale_after_ms: 30_000}
               }
             })

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    assert has_element?(
             view,
             ~s(#data-source-policy-customer-questdb[data-source-probe-policy="customer-policy"][data-source-probe-stale-after-ms="30000"]),
             "customer-policy"
           )
  end

  test "renders scheduled probe timeout evidence for BYO source rows" do
    {conn, _user, org, mission} = signed_in_org_and_mission()

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-timeout-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               data_source_id: "timeout-customer-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/timeout"}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "timeout-customer-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :customer_owned,
               credentials_ref: "cred-timeout-questdb",
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :unknown,
                 data_source_id: "timeout-customer-questdb",
                 source_health: :unavailable,
                 reason: :source_probe_timeout,
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   source: "dashboard_source_probe_scheduler",
                   probe_kind: "scheduler",
                   probe_message: "Source probe exceeded scheduler timeout.",
                   probe_metadata: %{probe_timeout_ms: 25},
                   connection_test_result: "blocked",
                   connection_test_kind: "scheduler_timeout",
                   connection_test_message: "Scheduled source probe timed out before completion."
                 }
               },
               invalidate_runtime_cache?: false
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/failed-managed-questdb/settings"
      )

    assert has_element?(
             view,
             ~s(#data-source-timeout-customer-questdb[data-source-health="unavailable"][data-source-readiness="blocked"][data-source-readiness-reasons*="source_unavailable"][data-source-readiness-reasons*="connection_test_blocked"][data-source-probe-kind="scheduler"][data-source-probe-message="Source probe exceeded scheduler timeout."][data-source-probe-metadata*="probe_timeout_ms=25"][data-source-connection-test-result="blocked"][data-source-connection-test-kind="scheduler_timeout"]),
             "Scheduled source probe timed out before completion."
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="unavailable"][data-event-probe-kind="scheduler"][data-event-connection-test-result="blocked"][data-event-connection-test-kind="scheduler_timeout"]),
             "source_probe_timeout"
           )
  end

  test "renders managed TSDB deployment runs before sources exist" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    previous_config = Application.get_env(:cadence, :dashboard_managed_questdb_provisioning)

    on_exit(fn ->
      if is_nil(previous_config) do
        Application.delete_env(:cadence, :dashboard_managed_questdb_provisioning)
      else
        Application.put_env(:cadence, :dashboard_managed_questdb_provisioning, previous_config)
      end
    end)

    Application.put_env(:cadence, :dashboard_managed_questdb_provisioning,
      provisioner: fn attrs, _opts ->
        assert attrs["data_source_id"] == "failed-managed-questdb"
        {:error, {:questdb_unavailable, endpoint: "redacted-endpoint-ref"}}
      end
    )

    assert {:ok, failed_job} =
             ManagedQuestDBProvisioningJobs.enqueue(%{
               data_source_id: "failed-managed-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               endpoint_ref: "endpoint://cadence/failed-managed-questdb",
               topology_ref: "topology://cadence/failed-managed-questdb",
               provisioning_run_id: "failed-managed-questdb-run",
               actor_id: "operator-1"
             })

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == failed_job.job_id
    assert {:ok, _failed_job} = JobRunner.run_job(claimed_job.job_id)

    assert {:ok, running_job} =
             ManagedQuestDBProvisioningJobs.enqueue(%{
               data_source_id: "running-managed-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               endpoint_ref: "endpoint://cadence/running-managed-questdb",
               topology_ref: "topology://cadence/running-managed-questdb",
               provisioning_run_id: "running-managed-questdb-run",
               actor_id: "operator-1"
             })

    assert [claimed_running_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_running_job.job_id == running_job.job_id

    assert {:ok, queued_job} =
             ManagedQuestDBProvisioningJobs.enqueue(%{
               data_source_id: "queued-managed-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               endpoint_ref: "endpoint://cadence/queued-managed-questdb",
               topology_ref: "topology://cadence/queued-managed-questdb",
               provisioning_run_id: "queued-managed-questdb-run",
               actor_id: "operator-1"
             })

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/failed-managed-questdb/settings"
      )

    assert has_element?(
             view,
             ~s(#deployment-run-failed-managed-questdb-run[data-deployment-run-job-id="#{failed_job.job_id}"][data-deployment-run-data-source-id="failed-managed-questdb"][data-deployment-run-status="failed"][data-deployment-run-backend="questdb"][data-deployment-run-boundary="mission"][data-deployment-run-failure-summary="questdb_unavailable"][data-deployment-run-remediation="inspect_provisioning_job_and_retry"]),
             "failed-managed-questdb"
           )

    assert has_element?(
             view,
             ~s(#deployment-run-queued-managed-questdb-run[data-deployment-run-job-id="#{queued_job.job_id}"][data-deployment-run-data-source-id="queued-managed-questdb"][data-deployment-run-status="queued"][data-deployment-run-backend="questdb"][data-deployment-run-boundary="mission"][data-deployment-run-failure-summary="none"][data-deployment-run-remediation="wait_for_provisioning_worker"]),
             "queued-managed-questdb"
           )

    assert has_element?(
             view,
             ~s(#deployment-run-running-managed-questdb-run[data-deployment-run-job-id="#{running_job.job_id}"][data-deployment-run-data-source-id="running-managed-questdb"][data-deployment-run-status="provisioning"][data-deployment-run-backend="questdb"][data-deployment-run-boundary="mission"][data-deployment-run-failure-summary="none"][data-deployment-run-remediation="monitor_schema_migration_job"]),
             "running-managed-questdb"
           )

    view
    |> element("#retry-deployment-run-failed-managed-questdb-run")
    |> render_click()

    assert has_element?(
             view,
             ~s(#deployment-run-failed-managed-questdb-run[data-deployment-run-job-id="#{failed_job.job_id}"][data-deployment-run-status="queued"][data-deployment-run-failure-summary="none"][data-deployment-run-remediation="wait_for_provisioning_worker"])
           )

    refute has_element?(view, "#retry-deployment-run-failed-managed-questdb-run")

    assert {:ok, retried_job} = Cadence.Jobs.fetch_job(failed_job.job_id)
    assert retried_job.status == :queued
    assert retried_job.failure_reason == nil

    view
    |> element("#requeue-deployment-run-running-managed-questdb-run")
    |> render_click()

    assert has_element?(
             view,
             ~s(#deployment-run-running-managed-questdb-run[data-deployment-run-job-id="#{running_job.job_id}"][data-deployment-run-status="queued"][data-deployment-run-failure-summary="managed_questdb_provisioning_requeued"][data-deployment-run-remediation="wait_for_provisioning_worker"])
           )

    refute has_element?(view, "#requeue-deployment-run-running-managed-questdb-run")

    assert {:ok, requeued_job} = Cadence.Jobs.fetch_job(running_job.job_id)
    assert requeued_job.status == :queued
    assert requeued_job.failure_reason == %{"reason" => "managed_questdb_provisioning_requeued"}
  end
end
