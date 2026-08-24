defmodule CadenceWeb.OpsDataSourcesDeploymentLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Jobs.Runner, as: JobRunner

  alias Cadence.Control.DataSources.ManagedQuestDBProvisioningJobs

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  alias Cadence.Management.DataSources

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.DataSource

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

    source = source_row(view, "managed-mission-questdb")
    assert source["deployment_status_text"] == "ready"
    assert source["deployment_mode_text"] == "managed_questdb"
    assert source["deployment_backend_text"] == "questdb"
    assert source["deployment_boundary_text"] == "mission"
    assert source["deployment_remediation_text"] == "probe_source_health"
  end

  test "registers dedicated mission BYO TSDB sources with deployment posture" do
    {conn, user, org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new")

    render_hook(view, "register_source", %{
      "source" => %{
        "data_source_id" => "dedicated-mission-questdb",
        "logical_source" => "telemetry",
        "kind" => "byo_tsdb",
        "isolation_level" => "mission_isolated",
        "credentials_ref" => "cred-dedicated-mission-questdb",
        "credential_provider" => "questdb",
        "endpoint_ref" => "endpoint://customer/dedicated-mission",
        "material_env_profile" => "",
        "http_endpoint_env" => "",
        "storage" => "questdb"
      }
    })

    source = source_row(view, "dedicated-mission-questdb")
    assert source["deployment_status_text"] == "external"
    assert source["deployment_mode_text"] == "byo_tsdb"
    assert source["deployment_backend_text"] == "questdb"
    assert source["deployment_boundary_text"] == "mission"

    assert source["deployment_remediation_text"] ==
             "monitor_customer_dedicated_mission_backend"

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

    provision = source_action(view, "dedicated-mission-questdb", "provision_tsdb_backend")

    assert provision["payload"] == %{"data-source-id" => "dedicated-mission-questdb"}
    render_hook(view, "provision_tsdb_backend", provision["payload"])

    source = source_row(view, "dedicated-mission-questdb")
    assert source["deployment_lifecycle_operation_text"] == "provision"
    assert source["deployment_lifecycle_status_text"] == "provision_requested"
    refute source_action(view, "dedicated-mission-questdb", "provision_tsdb_backend")

    provision_run = deployment_run_for_source(view, "dedicated-mission-questdb")
    assert provision_run["status_text"] == "queued"
    assert provision_run["mode_text"] == "byo_tsdb"
    assert provision_run["physical_boundary_text"] == "mission"
    assert provision_run["remediation"] == "wait_for_tsdb_lifecycle_worker"

    reconcile = source_action(view, "dedicated-mission-questdb", "reconcile_tsdb_backend")
    assert reconcile["payload"] == %{"data-source-id" => "dedicated-mission-questdb"}
    render_hook(view, "reconcile_tsdb_backend", reconcile["payload"])

    source = source_row(view, "dedicated-mission-questdb")
    assert source["deployment_lifecycle_operation_text"] == "reconcile"
    assert source["deployment_lifecycle_status_text"] == "reconciled"

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

    deprovision = source_action(view, "dedicated-mission-questdb", "deprovision_tsdb_backend")

    assert deprovision["payload"] == %{"data-source-id" => "dedicated-mission-questdb"}

    assert deprovision["confirm"] ==
             "Request deprovisioning for this dedicated TSDB backend?"

    render_hook(view, "deprovision_tsdb_backend", deprovision["payload"])

    source = source_row(view, "dedicated-mission-questdb")
    assert source["status_text"] == "disabled"
    assert source["deployment_lifecycle_operation_text"] == "deprovision"
    assert source["deployment_lifecycle_status_text"] == "deprovision_requested"
    refute source_action(view, "dedicated-mission-questdb", "enable_source")

    deprovision_run = deployment_run_for_source(view, "dedicated-mission-questdb")
    assert deprovision_run["status_text"] == "queued"
    assert deprovision_run["mode_text"] == "byo_tsdb"
    assert deprovision_run["physical_boundary_text"] == "mission"
    assert deprovision_run["remediation"] == "wait_for_tsdb_lifecycle_worker"

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

    source = source_row(view, "policy-customer-questdb")
    assert source["probe_policy_text"] == "customer-policy"
    assert source["probe_stale_after_ms_text"] == "30000"
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
                   source: "data_source_probe_scheduler",
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

    source = source_row(view, "timeout-customer-questdb")
    assert source["health_status"] == "unavailable"
    assert source["source_readiness_status"] == "blocked"
    assert source["source_readiness_reason_text"] =~ "source_unavailable"
    assert source["source_readiness_reason_text"] =~ "connection_test_blocked"
    assert source["probe_kind_text"] == "scheduler"
    assert source["probe_message_text"] == "Source probe exceeded scheduler timeout."
    assert source["probe_metadata_text"] =~ "probe_timeout_ms=25"
    assert source["connection_test_result_text"] == "blocked"
    assert source["connection_test_kind_text"] == "scheduler_timeout"

    event =
      Enum.find(ops_data_sources_page(view)["activity"]["health_events"]["rows"], fn row ->
        row["event_type"] == "unavailable"
      end)

    assert event["subtitle"] =~ "source_probe_timeout"
    assert event["probe_kind"] == "scheduler"
    assert event["connection_test_result"] == "blocked"
    assert event["connection_test_kind"] == "scheduler_timeout"

    assert event["connection_test_message"] ==
             "Scheduled source probe timed out before completion."
  end

  test "renders managed TSDB deployment runs before sources exist" do
    {conn, _user, org, mission} = signed_in_org_and_mission()

    policy =
      ManagedQuestDBProvisioningJobs.policy(
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

    runner =
      JobRunner.new(%{
        ManagedQuestDBProvisioningJobs.job_type() =>
          ManagedQuestDBProvisioningJobs.handler(policy)
      })

    assert {:ok, _failed_job} = JobRunner.run_job(runner, claimed_job.job_id)

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

    failed_run = deployment_run(view, "failed-managed-questdb-run")
    assert failed_run["job_id"] == failed_job.job_id
    assert failed_run["data_source_id"] == "failed-managed-questdb"
    assert failed_run["status_text"] == "failed"
    assert failed_run["backend_text"] == "questdb"
    assert failed_run["physical_boundary_text"] == "mission"
    assert failed_run["failure_summary"] == "questdb_unavailable"
    assert failed_run["remediation"] == "inspect_provisioning_job_and_retry"

    assert failed_run["action"] == %{
             "id" => "retry-deployment-run-failed-managed-questdb-run",
             "event" => "retry_deployment_run",
             "payload" => %{"job-id" => failed_job.job_id},
             "label" => "Retry",
             "icon" => "hero-arrow-path"
           }

    queued_run = deployment_run(view, "queued-managed-questdb-run")
    assert queued_run["job_id"] == queued_job.job_id
    assert queued_run["data_source_id"] == "queued-managed-questdb"
    assert queued_run["status_text"] == "queued"
    assert queued_run["backend_text"] == "questdb"
    assert queued_run["physical_boundary_text"] == "mission"
    assert queued_run["failure_summary"] == "none"
    assert queued_run["remediation"] == "wait_for_provisioning_worker"

    running_run = deployment_run(view, "running-managed-questdb-run")
    assert running_run["job_id"] == running_job.job_id
    assert running_run["data_source_id"] == "running-managed-questdb"
    assert running_run["status_text"] == "provisioning"
    assert running_run["backend_text"] == "questdb"
    assert running_run["physical_boundary_text"] == "mission"
    assert running_run["failure_summary"] == "none"
    assert running_run["remediation"] == "monitor_schema_migration_job"

    render_hook(view, "retry_deployment_run", failed_run["action"]["payload"])

    failed_run = deployment_run(view, "failed-managed-questdb-run")
    assert failed_run["job_id"] == failed_job.job_id
    assert failed_run["status_text"] == "queued"
    assert failed_run["failure_summary"] == "none"
    assert failed_run["remediation"] == "wait_for_provisioning_worker"
    refute Map.has_key?(failed_run, "action")

    assert {:ok, retried_job} = Cadence.Jobs.fetch_job(failed_job.job_id)
    assert retried_job.status == :queued
    assert retried_job.failure_reason == nil

    running_action = deployment_run(view, "running-managed-questdb-run")["action"]
    assert running_action["event"] == "requeue_deployment_run"
    assert running_action["payload"] == %{"job-id" => running_job.job_id}
    render_hook(view, "requeue_deployment_run", running_action["payload"])

    running_run = deployment_run(view, "running-managed-questdb-run")
    assert running_run["job_id"] == running_job.job_id
    assert running_run["status_text"] == "queued"
    assert running_run["failure_summary"] == "managed_questdb_provisioning_requeued"
    assert running_run["remediation"] == "wait_for_provisioning_worker"
    refute Map.has_key?(running_run, "action")

    assert {:ok, requeued_job} = Cadence.Jobs.fetch_job(running_job.job_id)
    assert requeued_job.status == :queued
    assert requeued_job.failure_reason == %{"reason" => "managed_questdb_provisioning_requeued"}
  end

  defp ops_data_sources_page(view_or_html) do
    view_or_html
    |> LiveVue.Test.get_vue(id: "ops-data-sources-component")
    |> then(& &1.props["page"])
  end

  defp source_row(view_or_html, data_source_id) do
    Enum.find(
      ops_data_sources_page(view_or_html)["sources"]["rows"],
      &(&1["data_source_id"] == data_source_id)
    )
  end

  defp source_action(view_or_html, data_source_id, event) do
    view_or_html
    |> source_row(data_source_id)
    |> Map.get("actions", [])
    |> Enum.find(&(&1["event"] == event))
  end

  defp deployment_run(view_or_html, run_id) do
    Enum.find(
      ops_data_sources_page(view_or_html)["deployment_runs"]["rows"],
      &(&1["run_id"] == run_id)
    )
  end

  defp deployment_run_for_source(view_or_html, data_source_id) do
    Enum.find(
      ops_data_sources_page(view_or_html)["deployment_runs"]["rows"],
      &(&1["data_source_id"] == data_source_id)
    )
  end
end
