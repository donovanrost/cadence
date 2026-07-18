defmodule Cadence.Dashboards.DataSourcesTest do
  use Cadence.ConfigCase, async: false

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Catalog.Revision

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataBindingEvent,
    DataBindingInterval,
    DataSource,
    DataSourceEvent,
    DataSourceRegistry,
    DataSources,
    Document,
    Engine,
    EvidenceRef,
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    SourceCredentials,
    SourceFacts,
    SourceHealth,
    SourceRegistry,
    SourceResult,
    SourceWatermark,
    TSDBBackendLifecycleJobs,
    TSDBDeploymentStatus
  }

  alias Cadence.Jobs

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow}

  @fixture_dir Path.expand("../../fixtures/dashboards", __DIR__)

  setup do
    persist_mission_scope("org-dash-source", "mission-dash-source")
    :ok
  end

  test "persists and lists dashboard data sources" do
    data_source = %DataSource{
      data_source_id: "org-managed-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      isolation_level: :org_isolated,
      capabilities: %{range_scan?: true, watermarks?: false},
      metadata: %{storage: :questdb}
    }

    assert {:ok, persisted} =
             DataSources.persist_data_source(data_source,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 18:00:00Z],
               payload: %{reason: :initial_source}
             )

    assert persisted.data_source_id == "org-managed-questdb"
    assert persisted.owner == :cadence
    assert persisted.kind == :managed_tsdb
    assert persisted.adapter == Cadence.Dashboards.Sources.Telemetry
    assert persisted.isolation_level == :org_isolated
    assert persisted.credentials_ref == nil
    assert persisted.status == :active
    assert is_binary(persisted.current_event_id)
    assert persisted.capabilities == %{"range_scan?" => true, "watermarks?" => false}
    assert persisted.metadata == %{"storage" => "questdb"}

    assert listed =
             "org-dash-source"
             |> DataSources.list_data_sources("mission-dash-source")
             |> Enum.find(&(&1.data_source_id == "org-managed-questdb"))

    assert listed.data_source_id == "org-managed-questdb"

    assert [%DataSourceEvent{} = registered_event] =
             DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
               data_source_id: "org-managed-questdb"
             )

    assert registered_event.event_type == :registered
    assert registered_event.data_source_id == "org-managed-questdb"
    assert registered_event.current_status == :active
    assert registered_event.current_owner == :cadence
    assert registered_event.current_kind == :managed_tsdb
    assert registered_event.current_adapter == Cadence.Dashboards.Sources.Telemetry
    assert registered_event.current_isolation_level == :org_isolated

    assert registered_event.current_capabilities == %{
             "range_scan?" => true,
             "watermarks?" => false
           }

    assert registered_event.current_metadata == %{"storage" => "questdb"}
    assert registered_event.actor_id == "operator-1"
    assert registered_event.payload["reason"] == "initial_source"

    updated_source = %DataSource{
      data_source
      | capabilities: %{range_scan?: true, watermarks?: true},
        metadata: %{storage: :questdb, retention: :bounded}
    }

    assert {:ok, updated} =
             DataSources.persist_data_source(updated_source,
               actor_id: "operator-2",
               occurred_at: ~U[2026-06-21 19:00:00Z],
               payload: %{change_request_id: "DS-42"}
             )

    assert updated.capabilities["watermarks?"] == true
    assert updated.metadata["retention"] == "bounded"

    assert [changed_event, first_event] =
             DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
               data_source_id: "org-managed-questdb"
             )

    assert first_event.data_source_event_id == registered_event.data_source_event_id
    assert changed_event.event_type == :changed
    assert changed_event.previous_status == :active
    assert changed_event.current_status == :active

    assert changed_event.previous_capabilities == %{
             "range_scan?" => true,
             "watermarks?" => false
           }

    assert changed_event.current_capabilities == %{"range_scan?" => true, "watermarks?" => true}
    assert changed_event.previous_metadata == %{"storage" => "questdb"}
    assert changed_event.current_metadata == %{"retention" => "bounded", "storage" => "questdb"}
    assert changed_event.actor_id == "operator-2"
    assert changed_event.payload["change_request_id"] == "DS-42"

    assert {:ok, _same_source} = DataSources.persist_data_source(updated)

    assert [_, _] =
             DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
               data_source_id: "org-managed-questdb"
             )
  end

  test "disables and enables data sources as lifecycle events" do
    data_source = %DataSource{
      data_source_id: "toggle-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} =
             DataSources.persist_data_source(data_source, occurred_at: ~U[2026-06-21 18:00:00Z])

    assert {:ok, disabled} =
             DataSources.disable_data_source("toggle-questdb", %{},
               actor_id: "operator-3",
               occurred_at: ~U[2026-06-21 19:00:00Z],
               payload: %{reason: :maintenance}
             )

    assert disabled.status == :disabled
    assert disabled.disabled_at == ~U[2026-06-21 19:00:00.000000Z]
    assert is_binary(disabled.current_event_id)

    assert {:ok, fetched_disabled} = DataSources.fetch_data_source("toggle-questdb")
    assert fetched_disabled.status == :disabled

    assert {:ok, enabled} =
             DataSources.enable_data_source("toggle-questdb", %{},
               actor_id: "operator-4",
               occurred_at: ~U[2026-06-21 20:00:00Z],
               payload: %{reason: :maintenance_complete}
             )

    assert enabled.status == :active
    assert enabled.disabled_at == nil

    assert [enabled_event, disabled_event, registered_event] =
             DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
               data_source_id: "toggle-questdb"
             )

    assert registered_event.event_type == :registered
    assert disabled_event.event_type == :disabled
    assert disabled_event.previous_status == :active
    assert disabled_event.current_status == :disabled
    assert disabled_event.actor_id == "operator-3"
    assert disabled_event.payload["reason"] == "maintenance"
    assert enabled_event.event_type == :enabled
    assert enabled_event.previous_status == :disabled
    assert enabled_event.current_status == :active
    assert enabled_event.actor_id == "operator-4"
    assert enabled_event.payload["reason"] == "maintenance_complete"
  end

  test "probes data source descriptors into source health" do
    data_source = %DataSource{
      data_source_id: "probe-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    assert {:ok, healthy_event, healthy_status} =
             DataSources.probe_data_source(
               "probe-questdb",
               %{observed_at: ~U[2026-06-21 21:00:00Z]},
               actor_id: "operator-5",
               payload: %{source: "data_sources_test"},
               invalidate_runtime_cache?: false
             )

    assert healthy_event.source_health == :healthy
    assert healthy_event.reason == :source_adapter_probe_unsupported
    assert healthy_event.logical_source == :telemetry
    assert healthy_event.source_binding_id == nil
    assert healthy_event.realm == nil
    assert healthy_event.dataset == nil
    assert healthy_event.payload["source"] == "data_sources_test"
    assert healthy_event.payload["probe_kind"] == "adapter_unsupported"
    assert healthy_event.payload["connection_test_result"] == "unsupported"
    assert healthy_event.payload["connection_test_kind"] == "adapter_capability"
    assert healthy_event.payload["connection_test_message"] =~ "does not implement"
    assert healthy_event.payload["probe_metadata"]["storage"] == "questdb"
    assert healthy_event.payload["probe_metadata"]["probe_enabled?"] == false
    assert healthy_event.payload["probe_metadata"]["source_supports_watermarks?"] == false
    assert healthy_event.payload["probe_metadata"]["source_supported_sampling"] =~ "latest"
    assert is_binary(healthy_event.payload["probe_metadata"]["source_capability_fingerprint"])

    source_capabilities = healthy_event.payload["probe_metadata"]["source_capabilities"]
    assert source_capabilities["adapter"] == "Cadence.Dashboards.Sources.Telemetry"
    assert "latest" in source_capabilities["supported_sampling"]
    assert source_capabilities["data_source_capabilities"]["range_scan?"] == true
    assert healthy_event.payload["actor_id"] == "operator-5"
    assert healthy_status.source_health == :healthy

    assert [latest_status] =
             SourceHealth.list_source_health_statuses("org-dash-source", "mission-dash-source",
               data_source_id: "probe-questdb"
             )

    assert latest_status.source_health == :healthy

    first_fingerprint = healthy_event.payload["probe_metadata"]["source_capability_fingerprint"]

    assert {:ok, _updated_source} =
             DataSources.persist_data_source(%DataSource{
               data_source
               | capabilities: %{range_scan?: false}
             })

    assert {:ok, :unchanged, drift_status} =
             DataSources.probe_data_source(
               "probe-questdb",
               %{observed_at: ~U[2026-06-21 21:10:00Z]},
               actor_id: "operator-5",
               payload: %{source: "data_sources_test"},
               invalidate_runtime_cache?: false
             )

    drift_metadata = drift_status.payload["probe_metadata"]
    assert drift_metadata["source_capability_drift?"] == true
    assert drift_metadata["previous_source_capability_fingerprint"] == first_fingerprint
    assert drift_metadata["current_source_capability_fingerprint"] != first_fingerprint
    assert drift_metadata["previous_source_supported_sampling"] =~ "raw_series"
    refute drift_metadata["current_source_supported_sampling"] =~ "raw_series"

    assert {:ok, _disabled} =
             DataSources.disable_data_source("probe-questdb", %{},
               occurred_at: ~U[2026-06-21 21:30:00Z]
             )

    assert {:ok, unavailable_event, unavailable_status} =
             DataSources.probe_data_source(
               "probe-questdb",
               %{observed_at: ~U[2026-06-21 22:00:00Z]},
               actor_id: "operator-6",
               payload: %{source: "data_sources_test"},
               invalidate_runtime_cache?: false
             )

    assert unavailable_event.source_health == :unavailable
    assert unavailable_event.previous_source_health == :healthy
    assert unavailable_event.reason == :source_disabled
    assert unavailable_event.payload["actor_id"] == "operator-6"
    assert unavailable_status.source_health == :unavailable
  end

  test "QuestDB telemetry probes report backend-derived capabilities from schema evidence" do
    data_source = %DataSource{
      data_source_id: "questdb-schema-probe",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: false, watermarks?: false},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    test_pid = self()

    assert {:ok, healthy_event, healthy_status} =
             DataSources.probe_data_source(
               "questdb-schema-probe",
               %{observed_at: ~U[2026-06-21 22:15:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               questdb_exec_fun: questdb_probe_exec_fun(test_pid, :schema_ok),
               invalidate_runtime_cache?: false
             )

    assert_receive {:questdb_probe_sql, "SELECT 1"}
    assert_receive {:questdb_probe_sql, schema_sql}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_sql =~ "observation_identity_id"
    assert schema_sql =~ "idempotency_key"

    metadata = healthy_event.payload["probe_metadata"]
    assert healthy_event.source_health == :healthy
    assert healthy_status.source_health == :healthy
    assert healthy_event.payload["connection_test_result"] == "succeeded"
    assert healthy_event.payload["connection_test_kind"] == "adapter_io"
    assert healthy_event.payload["connection_test_message"] =~ "succeeded"
    assert metadata["questdb_schema_probe?"] == true
    assert metadata["adapter_reported_capabilities"]["range_scan?"] == true
    assert metadata["adapter_reported_capabilities"]["native_decimation?"] == true
    assert metadata["adapter_reported_capabilities"]["watermarks?"] == true
    assert "observation_identity_id" in metadata["questdb_schema_columns"]
    assert "idempotency_key" in metadata["questdb_schema_columns"]
    assert metadata["source_reported_capability_mismatch?"] == true
    assert metadata["source_reported_supported_sampling"] =~ "decimated_envelope"
    assert metadata["source_reported_supports_watermarks?"] == true
  end

  test "QuestDB telemetry probes degrade old schemas that miss canonical identity columns" do
    data_source = %DataSource{
      data_source_id: "questdb-schema-old",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    assert {:ok, degraded_event, degraded_status} =
             DataSources.probe_data_source(
               "questdb-schema-old",
               %{observed_at: ~U[2026-06-21 22:17:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               questdb_exec_fun: questdb_probe_exec_fun(self(), :schema_missing_identity),
               invalidate_runtime_cache?: false
             )

    metadata = degraded_event.payload["probe_metadata"]
    assert degraded_event.source_health == :degraded
    assert degraded_event.reason == :source_schema_probe_failed
    assert degraded_status.source_health == :degraded
    assert degraded_event.payload["connection_test_result"] == "failed"
    assert metadata["questdb_schema_probe?"] == true
    assert metadata["questdb_schema_table"] == "telemetry_observations"
    assert metadata["questdb_schema_missing_columns"] == ["observation_identity_id"]
    assert metadata["probe_diagnostic_kind"] == "schema_mismatch"
    assert metadata["probe_diagnostic_stage"] == "schema_validation"
    assert metadata["probe_remediation"] == "run_questdb_schema_migration"
    assert metadata["probe_diagnostic_detail"] =~ "observation_identity_id"
    assert metadata["adapter_error"] =~ "observation_identity_id"
    assert metadata["adapter_reported_capabilities"]["bounded_history?"] == false
    assert metadata["adapter_reported_capabilities"]["native_decimation?"] == false
    assert metadata["adapter_reported_capabilities"]["watermarks?"] == false
    assert metadata["source_reported_capability_mismatch?"] == true
  end

  test "QuestDB telemetry probes degrade when the backend schema is unavailable" do
    data_source = %DataSource{
      data_source_id: "questdb-schema-missing",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    assert {:ok, degraded_event, degraded_status} =
             DataSources.probe_data_source(
               "questdb-schema-missing",
               %{observed_at: ~U[2026-06-21 22:20:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               questdb_exec_fun: questdb_probe_exec_fun(self(), :schema_error),
               invalidate_runtime_cache?: false
             )

    metadata = degraded_event.payload["probe_metadata"]
    assert degraded_event.source_health == :degraded
    assert degraded_event.reason == :source_schema_probe_failed
    assert degraded_status.source_health == :degraded
    assert degraded_event.payload["connection_test_result"] == "failed"
    assert degraded_event.payload["connection_test_kind"] == "adapter_io"
    assert degraded_event.payload["connection_test_message"] =~ "failed"
    assert metadata["questdb_schema_probe?"] == false
    assert metadata["probe_diagnostic_kind"] == "schema_unavailable"
    assert metadata["probe_diagnostic_stage"] == "schema_query"
    assert metadata["probe_remediation"] == "check_questdb_schema_access"
    assert metadata["adapter_reported_capabilities"]["range_scan?"] == false
    assert metadata["source_reported_capability_mismatch?"] == true
    assert metadata["source_reported_supports_watermarks?"] == false
  end

  test "QuestDB telemetry probes mark connection failures unavailable with diagnostics" do
    data_source = %DataSource{
      data_source_id: "questdb-connection-failed",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    assert {:ok, unavailable_event, unavailable_status} =
             DataSources.probe_data_source(
               "questdb-connection-failed",
               %{observed_at: ~U[2026-06-21 22:22:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               questdb_exec_fun: questdb_probe_exec_fun(self(), :connection_error),
               invalidate_runtime_cache?: false
             )

    assert unavailable_event.source_health == :unavailable
    assert unavailable_event.reason == :source_connection_failed

    assert_receive {:questdb_probe_sql, "SELECT 1"}
    refute_receive {:questdb_probe_sql, _schema_sql}

    metadata = unavailable_status.payload["probe_metadata"]
    assert unavailable_status.source_health == :unavailable
    assert unavailable_status.reason == :source_connection_failed
    assert unavailable_status.source_health == :unavailable
    assert unavailable_status.payload["connection_test_result"] == "failed"
    assert unavailable_status.payload["connection_test_kind"] == "adapter_io"
    assert unavailable_status.payload["connection_test_message"] =~ "failed"
    assert metadata["adapter"] == "telemetry"
    assert metadata["storage"] == "questdb"
    assert metadata["data_source_id"] == "questdb-connection-failed"
    assert metadata["probe_diagnostic_kind"] == "connection_unreachable"
    assert metadata["probe_diagnostic_stage"] == "connection_test"
    assert metadata["probe_remediation"] == "check_questdb_endpoint"
    assert metadata["adapter_error"] =~ "econnrefused"
    assert metadata["source_supports_watermarks?"] == true
    assert metadata["source_capabilities"]["data_source_capabilities"]["watermarks?"] == true
    refute Map.has_key?(metadata, "questdb_schema_probe?")
  end

  test "QuestDB telemetry probes classify authentication failures separately" do
    data_source = %DataSource{
      data_source_id: "questdb-auth-failed",
      owner: :customer,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :customer_owned,
      credentials_ref: "secret://org-dash-source/dashboard/customer-auth-failed",
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: data_source.credentials_ref,
               organization_id: data_source.organization_id,
               mission_id: data_source.mission_id,
               data_source_id: data_source.data_source_id,
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb"
             })

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    assert {:ok, unavailable_event, _unavailable_status} =
             DataSources.probe_data_source(
               "questdb-auth-failed",
               %{observed_at: ~U[2026-06-21 22:23:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               credential_material_resolver: fn _credential, _opts ->
                 {:ok,
                  %{
                    http_endpoint: "https://customer-questdb.example.test",
                    bearer_token: "secret-token"
                  }}
               end,
               questdb_exec_fun: questdb_probe_exec_fun(self(), :auth_error),
               invalidate_runtime_cache?: false
             )

    assert_receive {:questdb_probe_sql, "SELECT 1"}

    metadata = unavailable_event.payload["probe_metadata"]
    assert unavailable_event.source_health == :unavailable
    assert unavailable_event.reason == :source_connection_failed
    assert metadata["probe_diagnostic_kind"] == "authentication_failed"
    assert metadata["probe_diagnostic_stage"] == "connection_test"
    assert metadata["probe_remediation"] == "check_credential_material"
    assert metadata["adapter_error"] =~ "http_error"
    refute inspect(unavailable_event) =~ "secret-token"
  end

  test "adapter probes can degrade data source health" do
    data_source = %DataSource{
      data_source_id: "adapter-probe-source",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :test}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    assert {:ok, degraded_event, degraded_status} =
             DataSources.probe_data_source(
               "adapter-probe-source",
               %{observed_at: ~U[2026-06-21 21:15:00Z]},
               actor_id: "operator-7",
               probe_mode: :degraded,
               test_pid: self(),
               invalidate_runtime_cache?: false
             )

    assert_receive {:dashboard_source_test_adapter_probe, "adapter-probe-source"}
    assert degraded_event.source_health == :degraded
    assert degraded_event.reason == :source_query_failed
    assert degraded_event.payload["probe_kind"] == "adapter"
    assert degraded_event.payload["connection_test_result"] == "failed"
    assert degraded_event.payload["connection_test_kind"] == "adapter_io"
    assert degraded_event.payload["probe_metadata"]["adapter"] == "test"
    assert degraded_status.source_health == :degraded
  end

  test "adapter probes persist reported capability discovery and mismatch evidence" do
    data_source = %DataSource{
      data_source_id: "adapter-reported-capability-source",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: false},
      metadata: %{storage: :test}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source)

    assert {:ok, healthy_event, healthy_status} =
             DataSources.probe_data_source(
               "adapter-reported-capability-source",
               %{observed_at: ~U[2026-06-21 21:20:00Z]},
               actor_id: "operator-8",
               adapter_reported_capabilities: %{range_scan?: false, watermarks?: true},
               materialize_adapter_capabilities?: true,
               test_pid: self(),
               invalidate_runtime_cache?: false
             )

    assert_receive {:dashboard_source_test_adapter_probe, "adapter-reported-capability-source"}
    metadata = healthy_event.payload["probe_metadata"]
    assert metadata["adapter_reported_capabilities"]["range_scan?"] == false
    assert metadata["adapter_reported_capabilities"]["watermarks?"] == true
    assert metadata["source_reported_capability_mismatch?"] == true
    assert metadata["source_reported_supported_sampling"] =~ "latest"
    refute metadata["source_reported_supported_sampling"] =~ "raw_series"
    assert metadata["source_reported_supports_watermarks?"] == true

    reported_capabilities = metadata["source_reported_capabilities"]
    assert reported_capabilities["adapter"] == "Cadence.Support.DashboardSourceTestAdapter"
    assert reported_capabilities["data_source_capabilities"]["range_scan?"] == false
    assert reported_capabilities["data_source_capabilities"]["watermarks?"] == true

    assert reported_capabilities["capability_fingerprint"] !=
             metadata["source_capability_fingerprint"]

    assert healthy_status.payload["probe_metadata"]["source_reported_capability_mismatch?"] ==
             true

    assert {:ok, materialized_source} =
             DataSources.fetch_data_source("adapter-reported-capability-source")

    assert materialized_source.capabilities["range_scan?"] == false
    assert materialized_source.capabilities["watermarks?"] == true
    assert materialized_source.metadata["adapter_capability_discovery?"] == true
    assert materialized_source.metadata["adapter_capability_discovery_source"] == "probe"
    assert materialized_source.metadata["adapter_capability_discovery_health"] == "healthy"

    assert materialized_source.metadata["adapter_capability_discovery_reason"] ==
             "source_probe_succeeded"

    assert materialized_source.metadata["adapter_capability_discovery_fingerprint"] ==
             reported_capabilities["capability_fingerprint"]

    events =
      DataSources.list_data_source_events("org-dash-source", "mission-dash-source",
        data_source_id: "adapter-reported-capability-source"
      )

    assert registered_event = Enum.find(events, &(&1.event_type == :registered))
    assert changed_event = Enum.find(events, &(&1.event_type == :changed))

    assert registered_event.event_type == :registered
    assert changed_event.event_type == :changed
    assert changed_event.actor_id == "operator-8"
    assert changed_event.previous_capabilities["range_scan?"] == true
    assert changed_event.previous_capabilities["watermarks?"] == false
    assert changed_event.current_capabilities["range_scan?"] == false
    assert changed_event.current_capabilities["watermarks?"] == true
    assert changed_event.payload["adapter_capability_discovery?"] == true
    assert changed_event.payload["source_health_event_id"] == healthy_event.source_health_event_id
    assert changed_event.payload["source_health"] == "healthy"
    assert changed_event.payload["reason"] == "source_probe_succeeded"
    assert changed_event.payload["adapter_reported_capabilities"]["range_scan?"] == false
    assert changed_event.payload["adapter_reported_capabilities"]["watermarks?"] == true
  end

  test "persists customer-owned BYO data sources with indirect credential refs" do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "secret://org-dash-source/dashboard/customer-rehearsal-questdb",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "customer-rehearsal-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/rehearsal"}
             })

    data_source = %DataSource{
      data_source_id: "customer-rehearsal-questdb",
      owner: :customer,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :customer_owned,
      credentials_ref: "secret://org-dash-source/dashboard/customer-rehearsal-questdb",
      capabilities: %{range_scan?: true, watermarks?: false},
      metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/rehearsal"}
    }

    assert {:ok, persisted} = DataSources.persist_data_source(data_source)
    assert persisted.owner == :customer
    assert persisted.kind == :byo_tsdb
    assert persisted.isolation_level == :customer_owned

    assert persisted.credentials_ref ==
             "secret://org-dash-source/dashboard/customer-rehearsal-questdb"

    assert persisted.metadata["endpoint_ref"] == "endpoint://customer/rehearsal"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "customer-rehearsal-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :rehearsal,
               logical_source: :telemetry,
               data_source_id: "customer-rehearsal-questdb",
               dataset: "rehearsal-12",
               priority: 0
             })

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(
               source_request(data_context: %{realm: :rehearsal}),
               persisted?: true
             )

    assert resolved.data_source.data_source_id == "customer-rehearsal-questdb"
    assert resolved.data_source.credentials_ref == persisted.credentials_ref
    assert resolved.data_source.metadata["endpoint_ref"] == "endpoint://customer/rehearsal"
    refute Map.has_key?(resolved.data_source.metadata, "password")
  end

  test "BYO QuestDB probes use redacted credential connection profiles" do
    credentials_ref = "secret://org-dash-source/dashboard/byo-probe-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "byo-probe-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{
                 endpoint_ref: "endpoint://customer/rehearsal",
                 http_endpoint: "http://customer-questdb:9000"
               }
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "byo-probe-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :customer_owned,
               credentials_ref: credentials_ref,
               capabilities: %{range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/rehearsal"}
             })

    test_pid = self()

    assert {:ok, healthy_event, healthy_status} =
             DataSources.probe_data_source(
               "byo-probe-questdb",
               %{observed_at: ~U[2026-06-21 22:25:00Z]},
               actor_id: "operator-byo-questdb",
               questdb_probe?: true,
               questdb_exec_fun: questdb_probe_exec_with_opts_fun(test_pid, :schema_ok),
               invalidate_runtime_cache?: false
             )

    assert_receive {:questdb_probe_sql, "SELECT 1", questdb_opts}
    assert questdb_opts[:http_endpoint] == "http://customer-questdb:9000"

    assert_receive {:questdb_probe_sql, schema_sql, schema_opts}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_opts[:http_endpoint] == "http://customer-questdb:9000"

    metadata = healthy_event.payload["probe_metadata"]
    profile = metadata["source_connection_profile"]

    assert healthy_event.source_health == :healthy
    assert healthy_status.source_health == :healthy
    assert healthy_event.payload["connection_test_result"] == "succeeded"
    assert healthy_event.payload["connection_test_kind"] == "adapter_io"
    assert metadata["http_endpoint"] == "http://customer-questdb:9000"
    assert metadata["connection_profile?"] == true
    assert profile["credentials_ref"] == credentials_ref
    assert profile["credential_provider"] == "questdb"
    assert profile["credential_kind"] == "byo_tsdb_connection"
    assert profile["credential_owner"] == "customer"
    assert profile["credential_version"] == 1
    assert profile["credential_status"] == "active"
    assert profile["data_source_id"] == "byo-probe-questdb"
    assert profile["data_source_kind"] == "byo_tsdb"
    assert profile["data_source_owner"] == "customer"
    assert profile["isolation_level"] == "customer_owned"
    assert profile["physical_isolation"]["isolation_level"] == "customer_owned"
    assert profile["physical_isolation"]["physical_boundary"] == "customer_connection"
    assert profile["physical_isolation"]["organization_id"] == "org-dash-source"
    assert profile["physical_isolation"]["mission_id"] == "mission-dash-source"
    assert profile["physical_isolation"]["storage"] == "questdb"
    assert profile["physical_isolation"]["endpoint_ref"] == "endpoint://customer/rehearsal"
    assert profile["endpoint_ref"] == "endpoint://customer/rehearsal"
    assert profile["http_endpoint"] == "http://customer-questdb:9000"
    assert profile["secret_material?"] == false
    refute Map.has_key?(profile, "password")
    refute Map.has_key?(profile, "token")
  end

  test "BYO QuestDB probes use resolved credential material without persisting secrets" do
    credentials_ref = "secret://org-dash-source/dashboard/byo-material-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "byo-material-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/material"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "byo-material-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :customer_owned,
               credentials_ref: credentials_ref,
               capabilities: %{range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/material"}
             })

    resolver = fn credential, opts ->
      assert credential.credentials_ref == credentials_ref
      assert Keyword.fetch!(opts, :organization_id) == "org-dash-source"
      assert Keyword.fetch!(opts, :mission_id) == "mission-dash-source"
      assert Keyword.fetch!(opts, :data_source_id) == "byo-material-questdb"

      {:ok,
       %{
         http_endpoint: "http://secret-material-questdb:9000",
         username: "quest-user",
         password: "quest-password"
       }}
    end

    test_pid = self()

    assert {:ok, healthy_event, healthy_status} =
             DataSources.probe_data_source(
               "byo-material-questdb",
               %{observed_at: ~U[2026-06-27 20:05:00Z]},
               actor_id: "operator-byo-questdb",
               credential_material_resolver: resolver,
               questdb_probe?: true,
               questdb_exec_fun: questdb_probe_exec_with_opts_fun(test_pid, :schema_ok),
               invalidate_runtime_cache?: false
             )

    expected_auth = "Basic " <> Base.encode64("quest-user:quest-password")

    assert_receive {:questdb_probe_sql, "SELECT 1", questdb_opts}
    assert questdb_opts[:http_endpoint] == "http://secret-material-questdb:9000"
    assert {"authorization", expected_auth} in questdb_opts[:headers]

    assert_receive {:questdb_probe_sql, schema_sql, schema_opts}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_opts[:http_endpoint] == "http://secret-material-questdb:9000"
    assert {"authorization", expected_auth} in schema_opts[:headers]

    metadata = healthy_event.payload["probe_metadata"]
    profile = metadata["source_connection_profile"]

    assert healthy_event.source_health == :healthy
    assert healthy_status.source_health == :healthy
    assert healthy_event.payload["connection_test_result"] == "succeeded"
    assert metadata["http_endpoint"] == "http://secret-material-questdb:9000"
    assert profile["secret_material?"] == true
    assert profile["secret_material_fields"] == ["username", "password"]
    assert profile["http_endpoint"] == "http://secret-material-questdb:9000"
    refute Map.has_key?(profile, "username")
    refute Map.has_key?(profile, "password")
    refute inspect(healthy_event.payload) =~ "quest-password"
    refute inspect(healthy_event.payload) =~ expected_auth
  end

  test "BYO QuestDB source execution uses resolved credential material without exposing secrets" do
    credentials_ref = "secret://org-dash-source/dashboard/byo-exec-questdb"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "byo-exec-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/execution"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "byo-exec-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :customer_owned,
               credentials_ref: credentials_ref,
               capabilities: %{latest?: true, range_scan?: true},
               metadata: %{storage: :questdb, endpoint_ref: "endpoint://customer/execution"}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "byo-exec-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "byo-exec-questdb",
               dataset: "flight",
               priority: 0
             })

    parent = self()

    latest_fun = fn organization_id, mission_id, point_id, opts ->
      send(parent, {:byo_latest_opts, organization_id, mission_id, point_id, opts})
      sample(point_id, "sample-byo-exec", 42.0, ~U[2026-06-27 20:10:00Z], "evidence-byo", [])
    end

    backend = fn credential, opts ->
      assert credential.credentials_ref == credentials_ref
      assert Keyword.fetch!(opts, :organization_id) == "org-dash-source"
      assert Keyword.fetch!(opts, :mission_id) == "mission-dash-source"
      assert Keyword.fetch!(opts, :data_source_id) == "byo-exec-questdb"

      {:ok,
       %{
         http_endpoint: "http://secret-exec-questdb:9000",
         bearer_token: "execution-token",
         headers: [{"x-tenant", "customer-a"}]
       }}
    end

    result =
      SourceRegistry.resolve(
        source_request(sampling: %{mode: :latest}),
        persisted?: true,
        credential_material_authorizer: fn credential, opts ->
          send(parent, {:byo_material_authorized, credential.credentials_ref, opts})
          :ok
        end,
        credential_secret_backend: backend,
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    assert %SourceResult{frames: [_frame], warnings: warnings} = result
    refute result.meta.degraded?
    refute Enum.any?(warnings, &(&1.code == :source_unavailable))

    assert_receive {:byo_latest_opts, "org-dash-source", "mission-dash-source", "HK.counter",
                    opts}

    assert opts[:realm] == :flight
    assert opts[:data_source_id] == "byo-exec-questdb"
    assert opts[:source_binding_id] == "byo-exec-flight"
    assert opts[:dataset] == "flight"
    assert opts[:http_endpoint] == "http://secret-exec-questdb:9000"
    assert {"authorization", "Bearer execution-token"} in opts[:headers]
    assert {"x-tenant", "customer-a"} in opts[:headers]

    profile = Keyword.fetch!(opts, :source_connection_profile)
    assert profile.secret_material? == true
    assert profile.secret_material_fields == ["bearer_token", "headers"]
    assert profile.http_endpoint == "http://secret-exec-questdb:9000"
    assert profile.data_source_id == "byo-exec-questdb"
    refute Map.has_key?(profile, :bearer_token)
    refute Map.has_key?(profile, :headers)
    refute inspect(result) =~ "execution-token"

    assert_receive {:byo_material_authorized, ^credentials_ref, authz_opts}
    assert Keyword.fetch!(authz_opts, :organization_id) == "org-dash-source"
    assert Keyword.fetch!(authz_opts, :mission_id) == "mission-dash-source"
    assert Keyword.fetch!(authz_opts, :data_source_id) == "byo-exec-questdb"
  end

  test "BYO QuestDB source execution fails closed when credential material cannot resolve" do
    credentials_ref = "secret://org-dash-source/dashboard/byo-exec-missing-material"

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: credentials_ref,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               data_source_id: "byo-exec-missing-material",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{endpoint_ref: "endpoint://customer/missing-material"}
             })

    assert {:ok, _persisted} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "byo-exec-missing-material",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :customer_owned,
               credentials_ref: credentials_ref,
               capabilities: %{latest?: true, range_scan?: true},
               metadata: %{
                 storage: :questdb,
                 endpoint_ref: "endpoint://customer/missing-material"
               }
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "byo-exec-missing-material-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "byo-exec-missing-material",
               dataset: "flight",
               priority: 0
             })

    result =
      SourceRegistry.resolve(
        source_request(sampling: %{mode: :latest}),
        persisted?: true,
        credential_material_resolver: fn _credential, _opts -> {:error, :vault_unavailable} end
      )

    assert %SourceResult{frames: [], warnings: [warning]} = result
    assert result.meta.degraded?
    assert warning.code == :source_unavailable
    assert warning.details.data_source_id == "byo-exec-missing-material"
    assert warning.details.binding_id == "byo-exec-missing-material-flight"
    assert warning.details.reason =~ "vault_unavailable"
  end

  test "rejects BYO data sources with unregistered credential refs" do
    data_source = %DataSource{
      data_source_id: "dangling-credential-questdb",
      owner: :customer,
      kind: :byo_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :customer_owned,
      credentials_ref: "secret://org-dash-source/dashboard/missing",
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:error, :credential_reference_not_found} =
             DataSources.persist_data_source(data_source)
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

  test "persists and lists dashboard data bindings" do
    persist_source("mission-questdb", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{reason: :primary}
    }

    assert {:ok, persisted} = DataSources.persist_data_binding(binding)
    assert persisted.binding_id == "mission-flight-telemetry"
    assert persisted.realm == :flight
    assert persisted.logical_source == :telemetry
    assert persisted.dataset == "flight"
    assert persisted.status == :active
    assert persisted.binding_version == 1
    assert is_binary(persisted.current_event_id)
    assert persisted.metadata == %{"reason" => "primary"}

    assert [%DataBindingEvent{} = event] =
             DataSources.list_data_binding_events("mission-flight-telemetry")

    assert event.event_type == :registered
    assert event.current_status == :active
    assert event.current_binding_version == 1
    assert event.current_data_source_id == "mission-questdb"
    assert event.current_dataset == "flight"
    assert event.current_priority == 0
    assert event.current_realm == :flight

    assert [operational_event] =
             OperationalEvents.list_events("org-dash-source", "mission-dash-source",
               category: :data_source,
               kind: :source_binding_registered,
               source_record_kind: :dashboard_data_binding_event,
               source_record_id: event.data_binding_event_id
             )

    assert operational_event.subject == %{kind: :source_binding, id: "mission-flight-telemetry"}
    assert operational_event.scope["logical_source"] == "telemetry"
    assert operational_event.scope["source_binding_id"] == "mission-flight-telemetry"
    assert operational_event.scope["data_source_id"] == "mission-questdb"
    assert operational_event.scope["data_realm"] == "flight"
    assert operational_event.payload["binding_version"] == 1
    assert operational_event.payload["event_type"] == "registered"
    assert operational_event.current["status"] == "active"

    assert [listed] = DataSources.list_data_bindings("org-dash-source", "mission-dash-source")
    assert listed.binding_id == "mission-flight-telemetry"
  end

  test "records changed data binding lifecycle events and skips idempotent upserts" do
    persist_source("mission-questdb", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb",
      dataset: "flight",
      priority: 0
    }

    assert {:ok, registered} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 20:00:00Z],
               payload: %{reason: :initial_binding}
             )

    assert registered.binding_version == 1

    assert {:ok, same_binding} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: ~U[2026-06-21 20:05:00Z]
             )

    assert same_binding.binding_version == 1
    assert [registered_event] = DataSources.list_data_binding_events("mission-flight-telemetry")
    assert registered_event.event_type == :registered

    changed = %DataBinding{binding | dataset: "flight-v2", priority: 1}

    assert {:ok, updated} =
             DataSources.persist_data_binding(changed,
               actor_id: "operator-2",
               occurred_at: ~U[2026-06-21 21:00:00Z],
               payload: %{change_request_id: "CR-42"}
             )

    assert updated.binding_version == 2

    assert [changed_event, first_event] =
             DataSources.list_data_binding_events("mission-flight-telemetry")

    assert changed_event.event_type == :changed
    assert changed_event.previous_binding_version == 1
    assert changed_event.current_binding_version == 2
    assert changed_event.previous_dataset == "flight"
    assert changed_event.current_dataset == "flight-v2"
    assert changed_event.previous_priority == 0
    assert changed_event.current_priority == 1
    assert changed_event.actor_id == "operator-2"
    assert changed_event.payload["change_request_id"] == "CR-42"
    assert first_event.data_binding_event_id == registered_event.data_binding_event_id
  end

  test "disables enables and supersedes data bindings as lifecycle events" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "mission-flight-telemetry",
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 realm: :flight,
                 logical_source: :telemetry,
                 data_source_id: "mission-questdb",
                 dataset: "flight",
                 priority: 0
               },
               occurred_at: ~U[2026-06-21 21:00:00Z]
             )

    assert {:ok, disabled} =
             DataSources.disable_data_binding("mission-flight-telemetry", %{},
               actor_id: "operator-3",
               occurred_at: ~U[2026-06-21 22:00:00Z]
             )

    assert disabled.status == :disabled
    assert disabled.disabled_at == ~U[2026-06-21 22:00:00.000000Z]
    assert disabled.binding_version == 2

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(), persisted?: true)

    assert warning.code == :missing_source_binding

    assert {:ok, enabled} =
             DataSources.enable_data_binding("mission-flight-telemetry", %{},
               actor_id: "operator-4",
               occurred_at: ~U[2026-06-21 23:00:00Z]
             )

    assert enabled.status == :active
    assert enabled.disabled_at == nil
    assert enabled.binding_version == 3
    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "mission-flight-telemetry"

    assert {:ok, superseded} =
             DataSources.supersede_data_binding("mission-flight-telemetry", %{},
               actor_id: "operator-5",
               occurred_at: ~U[2026-06-22 00:00:00Z]
             )

    assert superseded.status == :superseded
    assert superseded.superseded_at == ~U[2026-06-22 00:00:00.000000Z]
    assert superseded.active_to == ~U[2026-06-22 00:00:00.000000Z]
    assert superseded.binding_version == 4

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(), persisted?: true)

    assert warning.code == :missing_source_binding

    assert [superseded_event, enabled_event, disabled_event, registered_event] =
             DataSources.list_data_binding_events("mission-flight-telemetry")

    assert registered_event.event_type == :registered
    assert disabled_event.event_type == :disabled
    assert disabled_event.previous_status == :active
    assert disabled_event.current_status == :disabled
    assert enabled_event.event_type == :enabled
    assert enabled_event.previous_status == :disabled
    assert enabled_event.current_status == :active
    assert superseded_event.event_type == :superseded
    assert superseded_event.previous_status == :active
    assert superseded_event.current_status == :superseded
  end

  test "rolls back data binding projection changes when lifecycle event validation fails" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, %DataBinding{} = binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "flight",
               priority: 0
             })

    assert {:error, %Ecto.Changeset{} = changeset} =
             DataSources.persist_data_binding(%DataBinding{binding | dataset: "flight-v2"},
               payload: %{token: "plaintext"}
             )

    assert "must not embed credentials or secrets" in field_errors(changeset, :payload)

    assert {:ok, fetched} = DataSources.fetch_data_binding("mission-flight-telemetry")
    assert fetched.dataset == "flight"
    assert fetched.binding_version == 1

    assert [event] = DataSources.list_data_binding_events("mission-flight-telemetry")
    assert event.event_type == :registered
  end

  test "persisted binding resolution skips source-wide unavailable health" do
    persist_source("primary-health-questdb", :mission_isolated)
    persist_source("backup-health-questdb", :mission_isolated)

    assert {:ok, _primary_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "primary-health-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "primary-health-questdb",
               dataset: "flight-primary",
               priority: 0
             })

    assert {:ok, _backup_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "backup-health-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "backup-health-questdb",
               dataset: "flight-backup",
               priority: 10
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 logical_source: :telemetry,
                 data_source_id: "primary-health-questdb",
                 source_health: :unavailable,
                 reason: :source_connection_failed,
                 observed_at: DateTime.utc_now()
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, resolved} = DataSources.resolve_binding(source_request())

    assert resolved.binding.binding_id == "backup-health-flight"
    assert resolved.data_source.data_source_id == "backup-health-questdb"

    assert [
             %{
               binding_id: "primary-health-flight",
               decision: :rejected,
               reasons: [:source_unavailable],
               source_health: :unavailable,
               source_health_reason: :source_connection_failed
             },
             %{binding_id: "backup-health-flight", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "persisted binding resolution accepts strict source readiness policy" do
    persist_source("primary-degraded-questdb", :mission_isolated)
    persist_source("backup-degraded-questdb", :mission_isolated)

    assert {:ok, _primary_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "primary-degraded-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "primary-degraded-questdb",
               dataset: "flight-primary",
               priority: 0
             })

    assert {:ok, _backup_binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "backup-degraded-flight",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "backup-degraded-questdb",
               dataset: "flight-backup",
               priority: 10
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 logical_source: :telemetry,
                 data_source_id: "primary-degraded-questdb",
                 source_health: :degraded,
                 reason: :source_schema_probe_failed,
                 observed_at: DateTime.utc_now()
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, resolved} =
             DataSources.resolve_binding(source_request(),
               source_readiness_policy: [
                 policy_id: :strict_ops,
                 block_source_health: [:unavailable, :degraded],
                 block_freshness: [:fresh]
               ]
             )

    assert resolved.binding.binding_id == "backup-degraded-flight"
    assert resolved.data_source.data_source_id == "backup-degraded-questdb"
    assert resolved.source_selection.source_readiness_policy.policy_id == :strict_ops

    assert [
             %{
               binding_id: "primary-degraded-flight",
               decision: :rejected,
               reasons: [:source_degraded],
               source_health: :degraded,
               source_health_reason: :source_schema_probe_failed
             },
             %{binding_id: "backup-degraded-flight", decision: :selected}
           ] = resolved.source_selection.candidates
  end

  test "reconstructs source binding intervals and resolves historical bindings" do
    first_event_at = ~U[2026-06-21 20:00:00Z]
    second_event_at = ~U[2026-06-21 21:00:00Z]

    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, registered} =
             DataSources.persist_data_binding(binding,
               actor_id: "operator-1",
               occurred_at: first_event_at
             )

    assert {:ok, changed} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               actor_id: "operator-2",
               occurred_at: second_event_at
             )

    assert [
             %DataBindingInterval{} = first_interval,
             %DataBindingInterval{} = second_interval
           ] =
             DataSources.list_data_binding_intervals("org-dash-source", "mission-dash-source",
               binding_id: "mission-flight-telemetry"
             )

    assert first_interval.data_binding_event_id == registered.current_event_id
    assert first_interval.data_source_id == "mission-questdb-v1"
    assert first_interval.dataset == "flight-v1"
    assert first_interval.binding_version == 1
    assert DateTime.compare(first_interval.started_at, first_event_at) == :eq
    assert DateTime.compare(first_interval.ended_at, second_event_at) == :eq

    assert second_interval.data_binding_event_id == changed.current_event_id
    assert second_interval.data_source_id == "mission-questdb-v2"
    assert second_interval.dataset == "flight-v2"
    assert second_interval.binding_version == 2
    assert DateTime.compare(second_interval.started_at, second_event_at) == :eq
    assert second_interval.ended_at == nil

    assert {:ok, historical_resolved} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 20:30:00Z]
             )

    assert historical_resolved.data_source.data_source_id == "mission-questdb-v1"
    assert historical_resolved.binding.dataset == "flight-v1"
    assert historical_resolved.binding.binding_version == 1
    assert historical_resolved.binding.current_event_id == registered.current_event_id

    assert historical_resolved.binding_interval.data_binding_event_id ==
             registered.current_event_id

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 19:30:00Z]
             )

    assert warning.code == :missing_source_binding
    assert warning.details.source_binding_at == ~U[2026-06-21 19:30:00Z]

    assert warning.details.source_binding_miss_reason ==
             :source_binding_not_started_at_requested_time

    assert warning.details.nearest_source_binding_id == "mission-flight-telemetry"
    assert warning.details.nearest_data_source_id == "mission-questdb-v1"

    assert DateTime.compare(warning.details.nearest_source_binding_started_at, first_event_at) ==
             :eq

    assert DateTime.compare(warning.details.nearest_source_binding_ended_at, second_event_at) ==
             :eq

    assert %{strategy: :historical_binding, eligible_candidate_count: 0, candidates: candidates} =
             warning.details.source_selection

    assert [
             %{
               binding_id: "mission-flight-telemetry",
               decision: :rejected,
               reasons: [:interval_not_effective]
             },
             %{
               binding_id: "mission-flight-telemetry",
               decision: :rejected,
               reasons: [:interval_not_effective]
             }
           ] = candidates

    assert {:ok, current_resolved} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 21:30:00Z]
             )

    assert current_resolved.data_source.data_source_id == "mission-questdb-v2"
    assert current_resolved.binding.dataset == "flight-v2"
    assert current_resolved.binding.binding_version == 2
    assert current_resolved.binding_interval.data_binding_event_id == changed.current_event_id
  end

  test "historical source binding resolution honors explicit binding context" do
    persist_source("primary-questdb", :mission_isolated)
    persist_source("selected-questdb", :mission_isolated)

    assert {:ok, _primary} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "primary-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "primary-questdb",
               dataset: "primary-flight",
               priority: 0
             })

    assert {:ok, _selected} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "selected-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "selected-questdb",
               dataset: "selected-flight",
               priority: 10
             })

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(
               source_request(
                 data_context: %{realm: :flight, source_binding_id: "selected-flight-telemetry"}
               ),
               persisted?: true,
               source_binding_at: DateTime.utc_now()
             )

    assert resolved.binding.binding_id == "selected-flight-telemetry"
    assert resolved.data_source.data_source_id == "selected-questdb"
    assert resolved.binding.dataset == "selected-flight"
  end

  test "historical range segmentation filters intervals by explicit binding context" do
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]

    persist_source("primary-questdb-v1", :mission_isolated)
    persist_source("primary-questdb-v2", :mission_isolated)
    persist_source("selected-questdb", :mission_isolated)

    primary_binding = %DataBinding{
      binding_id: "primary-segmented-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "primary-questdb-v1",
      dataset: "primary-v1",
      priority: 0
    }

    assert {:ok, _primary_v1} =
             DataSources.persist_data_binding(primary_binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, _primary_v2} =
             DataSources.persist_data_binding(
               %DataBinding{
                 primary_binding
                 | data_source_id: "primary-questdb-v2",
                   dataset: "primary-v2"
               },
               occurred_at: boundary_time
             )

    assert {:ok, selected_binding} =
             DataSources.persist_data_binding(
               %DataBinding{
                 binding_id: "selected-segmented-telemetry",
                 organization_id: "org-dash-source",
                 mission_id: "mission-dash-source",
                 realm: :flight,
                 logical_source: :telemetry,
                 data_source_id: "selected-questdb",
                 dataset: "selected-flight",
                 priority: 10
               },
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, [resolved]} =
             DataSourceRegistry.resolve_segments(
               source_request(
                 data_context: %{
                   realm: :flight,
                   source_binding_id: "selected-segmented-telemetry"
                 }
               ),
               persisted?: true,
               source_binding_at: from_time,
               source_binding_range: %{from: from_time, to: to_time}
             )

    assert resolved.binding.binding_id == "selected-segmented-telemetry"
    assert resolved.binding.current_event_id == selected_binding.current_event_id
    assert resolved.data_source.data_source_id == "selected-questdb"
    assert resolved.segment_from == from_time
    assert resolved.segment_to == to_time
  end

  test "historical range resolution warns when a query crosses source binding intervals" do
    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, _registered} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, _changed} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: ~U[2026-06-21 21:00:00Z]
             )

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               source_binding_at: ~U[2026-06-21 20:15:00Z],
               source_binding_range: %{
                 from: ~U[2026-06-21 20:15:00Z],
                 to: ~U[2026-06-21 21:15:00Z]
               }
             )

    assert warning.code == :source_binding_interval_ambiguous
    assert warning.severity == :error
    assert warning.details.from == ~U[2026-06-21 20:15:00Z]
    assert warning.details.to == ~U[2026-06-21 21:15:00Z]

    assert Enum.map(warning.details.intervals, & &1.data_source_id) == [
             "mission-questdb-v1",
             "mission-questdb-v2"
           ]
  end

  test "source registry segments telemetry history reads across source binding intervals" do
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    parent = self()

    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, first_binding} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, second_binding} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: boundary_time
             )

    history_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:history_opts, opts})

      case Keyword.fetch!(opts, :data_source_id) do
        "mission-questdb-v1" ->
          assert Keyword.fetch!(opts, :from_receipt_time) == from_time
          assert DateTime.compare(Keyword.fetch!(opts, :to_receipt_time), boundary_time) == :eq

          [
            sample(point_id, "sample-v1", 11.0, ~U[2026-06-21 20:30:00Z], "evidence-v1",
              generation_time: ~U[2026-06-21 20:29:59Z]
            )
          ]

        "mission-questdb-v2" ->
          assert DateTime.compare(Keyword.fetch!(opts, :from_receipt_time), boundary_time) == :eq
          assert Keyword.fetch!(opts, :to_receipt_time) == to_time

          [
            sample(point_id, "sample-v2", 22.0, ~U[2026-06-21 21:05:00Z], "evidence-v2",
              generation_time: ~U[2026-06-21 21:04:59Z]
            )
          ]
      end
    end

    result =
      SourceRegistry.resolve(
        source_request(
          sampling: %{mode: :raw_series},
          time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time}
        ),
        persisted?: true,
        source_binding_at: from_time,
        source_binding_range: %{from: from_time, to: to_time},
        source_opts: %{telemetry: [history_fun: history_fun]}
      )

    refute Enum.any?(result.warnings, &(&1.severity == :error))
    assert result.meta.segmented_source_bindings?
    assert result.meta.source_binding_segment_count == 2

    assert Enum.map(result.meta.source_binding_segments, & &1.data_source_id) == [
             "mission-questdb-v1",
             "mission-questdb-v2"
           ]

    assert Enum.map(result.meta.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.segmented_source_bindings?
    assert frame.meta.source_binding_segment_count == 2
    refute Map.has_key?(frame.meta, :source_binding_id)
    assert frame.meta.data_source_ids == ["mission-questdb-v1", "mission-questdb-v2"]
    assert frame.meta.datasets == ["flight-v1", "flight-v2"]

    assert frame.meta.evidence
           |> Enum.filter(&match?(%EvidenceRef{kind: :source_binding_event}, &1))
           |> Enum.map(& &1.id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert [
             %{name: "time", values: [~U[2026-06-21 20:30:00Z], ~U[2026-06-21 21:05:00Z]]},
             %{name: "HK.counter", values: [11.0, 22.0]}
           ] = frame.fields

    assert_received {:history_opts, first_opts}
    assert_received {:history_opts, second_opts}
    assert Keyword.fetch!(first_opts, :data_source_id) == "mission-questdb-v1"
    assert Keyword.fetch!(second_opts, :data_source_id) == "mission-questdb-v2"
  end

  test "segmented telemetry facts carry source binding segments for cache preflight" do
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    parent = self()

    persist_watermarked_source("mission-questdb-v1")
    persist_watermarked_source("mission-questdb-v2")

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, first_binding} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, second_binding} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: boundary_time
             )

    watermark_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:watermark_opts, opts})

      %{
        complete_through: Keyword.fetch!(opts, :to_receipt_time),
        latest_receipt_time: Keyword.fetch!(opts, :to_receipt_time),
        retention_starts_at: Keyword.fetch!(opts, :from_receipt_time),
        point_id: point_id,
        confidence: :best_effort
      }
    end

    assert {:ok, %SourceFacts{} = facts} =
             SourceRegistry.facts(
               source_request(
                 sampling: %{mode: :raw_series},
                 time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time}
               ),
               persisted?: true,
               source_binding_at: from_time,
               source_binding_range: %{from: from_time, to: to_time},
               source_opts: %{telemetry: [watermark_fun: watermark_fun]}
             )

    assert facts.source_binding == nil
    assert facts.data_source == nil
    assert facts.source_health == :healthy
    assert facts.meta.segmented_source_bindings?
    assert facts.meta.source_binding_segment_count == 2
    assert length(facts.watermarks) == 2
    assert facts.watermark.confidence == :best_effort
    assert DateTime.compare(facts.watermark.complete_through, boundary_time) == :eq

    assert Enum.map(facts.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    key =
      SourceFacts.runtime_cache_key(
        source_request(
          sampling: %{mode: :raw_series},
          time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time}
        ),
        facts,
        cache_policy: :snapshot
      )

    refute Map.has_key?(key.parts, :source_binding)
    refute Map.has_key?(key.parts, :data_source)

    assert Enum.map(key.parts.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert_received {:watermark_opts, first_opts}
    assert_received {:watermark_opts, second_opts}
    assert Keyword.fetch!(first_opts, :data_source_id) == "mission-questdb-v1"
    assert Keyword.fetch!(second_opts, :data_source_id) == "mission-questdb-v2"
  end

  test "engine source result cache reuses segmented historical telemetry results" do
    cache = start_supervised!({RuntimeCache, name: nil})
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    parent = self()

    persist_watermarked_source("mission-questdb-v1")
    persist_watermarked_source("mission-questdb-v2")

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, first_binding} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, second_binding} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: boundary_time
             )

    history_fun = fn _organization_id, _mission_id, point_id, opts ->
      data_source_id = Keyword.fetch!(opts, :data_source_id)
      send(parent, {:history_opts, data_source_id, opts})

      {value, receipt_time} =
        case data_source_id do
          "mission-questdb-v1" -> {11.0, ~U[2026-06-21 20:30:00Z]}
          "mission-questdb-v2" -> {22.0, ~U[2026-06-21 21:05:00Z]}
        end

      [
        sample(
          point_id,
          "sample-#{data_source_id}",
          value,
          receipt_time,
          "evidence-#{data_source_id}",
          %{}
        )
      ]
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:watermark_opts, point_id, opts})

      %{
        complete_through: Keyword.fetch!(opts, :to_receipt_time),
        latest_receipt_time: Keyword.fetch!(opts, :to_receipt_time),
        retention_starts_at: Keyword.fetch!(opts, :from_receipt_time),
        point_id: point_id,
        confidence: :best_effort
      }
    end

    document = segmented_history_document()

    request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time},
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
    }

    source_opts = %{telemetry: [history_fun: history_fun, watermark_fun: watermark_fun]}

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        persisted?: true,
        freshness_now: ~U[2026-06-21 21:16:00Z],
        source_opts: source_opts
      )

    assert source_cache_statuses(first) == [:miss]
    assert [%{key: first_key}] = source_cache_entries(first)
    assert first_key.parts.cache_policy == :snapshot
    refute Map.has_key?(first_key.parts, :source_binding)
    refute Map.has_key?(first_key.parts, :data_source)

    assert Enum.map(first_key.parts.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert_receive {:history_opts, "mission-questdb-v1", first_opts}
    assert_receive {:history_opts, "mission-questdb-v2", second_opts}
    assert Keyword.fetch!(first_opts, :from_receipt_time) == from_time
    assert DateTime.compare(Keyword.fetch!(first_opts, :to_receipt_time), boundary_time) == :eq
    assert DateTime.compare(Keyword.fetch!(second_opts, :from_receipt_time), boundary_time) == :eq
    assert Keyword.fetch!(second_opts, :to_receipt_time) == to_time

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        persisted?: true,
        freshness_now: ~U[2026-06-21 21:20:00Z],
        source_opts: source_opts
      )

    assert source_cache_statuses(second) == [:hit]
    assert [%{key: second_key}] = source_cache_entries(second)
    assert second_key.fingerprint == first_key.fingerprint
    refute_receive {:history_opts, _data_source_id, _opts}, 20

    assert %{"placement_power_trend" => placement_frames} = second.frames_by_placement
    assert [%Frame{} = frame] = placement_frames.primary
    assert frame.meta.segmented_source_bindings?

    assert Enum.map(frame.meta.source_binding_segments, & &1.data_source_id) == [
             "mission-questdb-v1",
             "mission-questdb-v2"
           ]

    assert [
             %{name: "time", values: [~U[2026-06-21 20:30:00Z], ~U[2026-06-21 21:05:00Z]]},
             %{name: "HK.counter", values: [11.0, 22.0]}
           ] = frame.fields
  end

  test "source results and frames include historical source binding provenance" do
    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, registered} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, _changed} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: ~U[2026-06-21 21:00:00Z]
             )

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-historical", 12.4, ~U[2026-06-21 20:30:00Z], "evidence-1",
        generation_time: ~U[2026-06-21 20:29:59Z]
      )
    end

    result =
      SourceRegistry.resolve(
        source_request(sampling: %{mode: :latest}),
        persisted?: true,
        source_binding_at: ~U[2026-06-21 20:30:00Z],
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    refute Enum.any?(result.warnings, &(&1.severity == :error))
    assert result.meta.source_binding_id == "mission-flight-telemetry"
    assert result.meta.source_binding_version == 1
    assert result.meta.source_binding_event_id == registered.current_event_id
    assert result.meta.source_binding_interval.data_source_id == "mission-questdb-v1"
    assert result.meta.source_binding_interval.dataset == "flight-v1"

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.source_binding_id == "mission-flight-telemetry"
    assert frame.meta.source_binding_version == 1
    assert frame.meta.source_binding_event_id == registered.current_event_id
    assert frame.meta.source_binding_interval.data_source_id == "mission-questdb-v1"

    assert %EvidenceRef{
             kind: :source_binding_event,
             id: event_id,
             observed_at: observed_at,
             source: :telemetry
           } =
             Enum.find(
               frame.meta.evidence,
               &match?(%EvidenceRef{kind: :source_binding_event}, &1)
             )

    assert event_id == registered.current_event_id
    assert DateTime.compare(observed_at, ~U[2026-06-21 20:00:00Z]) == :eq

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{kind: :source_binding, id: "mission-flight-telemetry"} -> true
             _other -> false
           end)
  end

  test "source result frames include selected operational interval evidence" do
    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source_endpoint_scope("endpoint-sc-001")

    assert {:ok, _event} =
             catalog_revision("catalog-revision-a", revision_number: 1)
             |> Event.from_catalog_revision(~U[2026-06-21 20:00:00Z])
             |> OperationalEvents.persist_event()

    binding_set =
      application_binding_set("runtime-apps-a",
        source_endpoint_ref: "endpoint-sc-001",
        apid: 42,
        metric_name: "packets_v1"
      )

    assert {:ok, _binding_set} = Cadence.persist_binding_set("org-dash-source", binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               "org-dash-source",
               "mission-dash-source",
               binding_set.binding_set_id,
               binding_set.version,
               activated_at: ~U[2026-06-21 20:00:00Z]
             )

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, _registered} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-historical", 12.4, ~U[2026-06-21 20:30:00Z], "evidence-1",
        generation_time: ~U[2026-06-21 20:29:59Z]
      )
    end

    result =
      SourceRegistry.resolve(
        source_request(
          sampling: %{mode: :latest},
          scope_context: %{source_endpoint_id: "endpoint-sc-001"}
        ),
        persisted?: true,
        source_binding_at: ~U[2026-06-21 20:30:00Z],
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    assert [%Frame{} = frame] = result.frames

    assert [
             %{kind: :application_binding, subject_id: "runtime-apps-a-packet-counter-rule"},
             %{kind: :binding_set, subject_id: "runtime-apps-a"},
             %{kind: :catalog_revision, subject_id: "catalog-revision-a"}
           ] =
             frame.meta.selected_operational_intervals
             |> Enum.sort_by(& &1.kind)
             |> Enum.map(&Map.take(&1, [:kind, :subject_id]))

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{kind: :binding_set_interval, id: "effective_interval:binding_set:" <> _} ->
               true

             _other ->
               false
           end)

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{
               kind: :application_binding_interval,
               id: "effective_interval:application_binding:" <> _
             } ->
               true

             _other ->
               false
           end)

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{
               kind: :catalog_revision_interval,
               id: "effective_interval:catalog_revision:" <> _
             } ->
               true

             _other ->
               false
           end)
  end

  test "persists dashboard policy metadata and uses it for concrete source execution policy" do
    data_source = %DataSource{
      data_source_id: "policy-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{
        storage: :questdb,
        dashboard_policy: %{
          execution: %{timeout_ms: :infinity},
          circuit_breaker: %{backoff_ms: 10_000},
          adapter_extension: %{query_pool: "questdb-dashboard"}
        }
      }
    }

    assert {:ok, persisted_source} = DataSources.persist_data_source(data_source)
    assert persisted_source.metadata["dashboard_policy"]["execution"]["timeout_ms"] == "infinity"

    assert persisted_source.metadata["dashboard_policy"]["adapter_extension"]["query_pool"] ==
             "questdb-dashboard"

    binding = %DataBinding{
      binding_id: "policy-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "policy-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{
        dashboard_policy: %{
          circuit_breaker: %{failure_threshold: 2}
        }
      }
    }

    assert {:ok, _persisted_binding} = DataSources.persist_data_binding(binding)

    policy = SourceRegistry.execution_policy(source_request(), persisted?: true)

    assert policy.timeout_ms == :infinity
    assert policy.circuit_failure_threshold == 2
    assert policy.circuit_backoff_ms == 10_000
    assert policy.provenance.data_source_policy?
    assert policy.provenance.binding_policy?
    assert policy.provenance.data_source_id == "policy-questdb"
    assert policy.provenance.source_binding_id == "policy-flight-telemetry"
  end

  test "rejects malformed data source dashboard policy metadata" do
    data_source = %DataSource{
      data_source_id: "bad-policy-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{
        dashboard_policy: %{
          execution: %{timeout_ms: -1},
          circuit_breaker: %{failure_threshold: 0, backoff_ms: -5}
        }
      }
    }

    assert {:error, %Ecto.Changeset{} = changeset} = DataSources.persist_data_source(data_source)

    assert "dashboard_policy.execution.timeout_ms must be a non-negative integer or \"infinity\"" in metadata_errors(
             changeset
           )

    assert "dashboard_policy.circuit_breaker.failure_threshold must be a positive integer" in metadata_errors(
             changeset
           )

    assert "dashboard_policy.circuit_breaker.backoff_ms must be a non-negative integer" in metadata_errors(
             changeset
           )
  end

  test "rejects malformed data binding dashboard policy metadata" do
    persist_source("binding-policy-questdb", :mission_isolated)

    binding = %DataBinding{
      binding_id: "bad-policy-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "binding-policy-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{
        dashboard_policy: %{
          execution: "slow",
          circuit_breaker: %{backoff_ms: -1}
        }
      }
    }

    assert {:error, %Ecto.Changeset{} = changeset} = DataSources.persist_data_binding(binding)

    assert "dashboard_policy.execution must be a map" in metadata_errors(changeset)

    assert "dashboard_policy.circuit_breaker.backoff_ms must be a non-negative integer" in metadata_errors(
             changeset
           )
  end

  test "lists active telemetry data realms for dashboard controls" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-rehearsal-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :rehearsal,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "rehearsal",
               active_from: ~U[2026-01-01 00:00:00Z],
               active_to: ~U[2027-01-01 00:00:00Z],
               priority: 0
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-replay-limits",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :replay,
               logical_source: :limits,
               data_source_id: "mission-questdb",
               dataset: "replay-limits",
               priority: 0
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-future-replay-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :replay,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "future-replay",
               active_from: ~U[2028-01-01 00:00:00Z],
               priority: 0
             })

    assert DataSources.list_data_realms("org-dash-source", "mission-dash-source",
             now: ~U[2026-06-01 00:00:00Z]
           ) == ["rehearsal"]
  end

  test "persisted registry honors binding activation windows" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "flight",
               active_from: ~U[2028-01-01 00:00:00Z],
               priority: 0
             })

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               now: ~U[2026-06-01 00:00:00Z]
             )

    assert warning.code == :missing_source_binding

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               now: ~U[2028-01-01 00:00:01Z]
             )

    assert resolved.binding.binding_id == "mission-flight-telemetry"
  end

  test "data realm listing falls back to flight when no telemetry bindings exist" do
    assert DataSources.list_data_realms("org-dash-source", "mission-dash-source") == ["flight"]
  end

  test "persisted registry selection prefers mission-specific bindings" do
    persist_source("org-questdb", :org_isolated)
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "org-flight-telemetry",
               organization_id: "org-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "org-questdb",
               dataset: "org-flight",
               priority: 0
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "mission-flight",
               priority: 0
             })

    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "mission-flight-telemetry"
    assert resolved.data_source.data_source_id == "mission-questdb"
    assert resolved.data_source.isolation_level == :mission_isolated
    assert resolved.dataset == "mission-flight"

    assert {:ok, context_resolved} = DataSources.resolve_binding(source_request())
    assert context_resolved.binding.binding_id == "mission-flight-telemetry"
  end

  test "bootstraps default managed telemetry source idempotently" do
    assert %{data_source: data_source, data_binding: data_binding} =
             DataSources.ensure_default_managed_sources!()

    assert data_source.data_source_id == "managed_questdb_primary"
    assert data_source.kind == :managed_tsdb
    assert data_source.adapter == Cadence.Dashboards.Sources.Telemetry
    assert data_source.isolation_level == :shared
    assert data_source.metadata["bootstrap_default?"]

    assert data_binding.binding_id == "default_flight_telemetry"
    assert data_binding.realm == :flight
    assert data_binding.logical_source == :telemetry
    assert data_binding.data_source_id == "managed_questdb_primary"
    assert data_binding.dataset == "flight"
    assert data_binding.metadata["bootstrap_default?"]

    assert limits_source =
             Enum.find(
               DataSources.list_data_sources("org-dash-source", "mission-dash-source"),
               &(&1.data_source_id == "managed_limits_projection")
             )

    assert limits_source.kind == :projection
    assert limits_source.adapter == Cadence.Dashboards.Sources.Limits
    assert limits_source.capabilities["latest_state?"]
    assert limits_source.capabilities["definition_intervals?"]
    assert limits_source.metadata["bootstrap_default?"]

    assert limits_binding =
             Enum.find(
               DataSources.list_data_bindings("org-dash-source", "mission-dash-source"),
               &(&1.binding_id == "default_flight_limits")
             )

    assert limits_binding.realm == :flight
    assert limits_binding.logical_source == :limits
    assert limits_binding.data_source_id == "managed_limits_projection"
    assert limits_binding.dataset == "telemetry_latest_limit_states"
    assert limits_binding.metadata["bootstrap_default?"]

    assert events_source =
             Enum.find(
               DataSources.list_data_sources("org-dash-source", "mission-dash-source"),
               &(&1.data_source_id == "managed_events_projection")
             )

    assert events_source.kind == :projection
    assert events_source.adapter == Cadence.Dashboards.Sources.Events
    assert events_source.capabilities["contact_intervals?"]
    assert events_source.capabilities["mission_timeline?"]
    assert events_source.capabilities["source_health_transitions?"]
    assert events_source.metadata["bootstrap_default?"]

    assert events_binding =
             Enum.find(
               DataSources.list_data_bindings("org-dash-source", "mission-dash-source"),
               &(&1.binding_id == "default_flight_events")
             )

    assert events_binding.realm == :flight
    assert events_binding.logical_source == :events
    assert events_binding.data_source_id == "managed_events_projection"
    assert events_binding.dataset == "mission_events"
    assert events_binding.metadata["bootstrap_default?"]

    assert %{data_source: second_source, data_binding: second_binding} =
             DataSources.ensure_default_managed_sources!()

    assert second_source.data_source_id == data_source.data_source_id
    assert second_binding.binding_id == data_binding.binding_id
  end

  test "persisted registry resolves from bootstrapped defaults" do
    _defaults = DataSources.ensure_default_managed_sources!()

    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "default_flight_telemetry"
    assert resolved.data_source.data_source_id == "managed_questdb_primary"
    assert resolved.realm == :flight
    assert resolved.dataset == "flight"

    assert {:ok, limits_resolved} =
             DataSourceRegistry.resolve(
               source_request(logical_source: :limits, sampling: %{mode: :latest_state}),
               persisted?: true
             )

    assert limits_resolved.binding.binding_id == "default_flight_limits"
    assert limits_resolved.data_source.data_source_id == "managed_limits_projection"
    assert limits_resolved.realm == :flight
    assert limits_resolved.dataset == "telemetry_latest_limit_states"

    assert {:ok, events_resolved} =
             DataSourceRegistry.resolve(
               source_request(logical_source: :events, sampling: %{mode: :event_history}),
               persisted?: true
             )

    assert events_resolved.binding.binding_id == "default_flight_events"
    assert events_resolved.data_source.data_source_id == "managed_events_projection"
    assert events_resolved.realm == :flight
    assert events_resolved.dataset == "mission_events"
  end

  test "persisted registry returns missing binding warning when scoped rows exist but no binding matches" do
    persist_source("rehearsal-questdb", :mission_isolated)

    assert {:error, warning} =
             DataSourceRegistry.resolve(
               source_request(data_context: %{realm: :rehearsal}),
               persisted?: true
             )

    assert warning.code == :missing_source_binding
    assert warning.details.realm == :rehearsal
  end

  test "persisting a data binding invalidates matching dashboard runtime caches only" do
    cache = start_supervised!({RuntimeCache, name: nil})
    use_dashboard_runtime_cache!(cache)
    persist_source("mission-questdb", :mission_isolated)
    persist_limits_source("mission-limits")

    matching_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-flight-telemetry",
        data_source_id: "mission-questdb",
        realm: :flight,
        dataset: "mission-flight"
      )

    matching_frame_key = dashboard_frame_key(matching_key, "frame-mission-flight")

    other_realm_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-rehearsal-telemetry",
        data_source_id: "mission-questdb",
        realm: :rehearsal,
        dataset: "mission-rehearsal"
      )

    other_realm_frame_key = dashboard_frame_key(other_realm_key, "frame-rehearsal")

    limits_key =
      dashboard_source_result_key(:limits,
        binding_id: "mission-flight-limits",
        data_source_id: "mission-limits",
        realm: :flight,
        dataset: "telemetry_latest_limit_states"
      )

    limits_frame_key = dashboard_frame_key(limits_key, "frame-limits")

    matching_result = dashboard_source_result(matching_key)
    matching_frames = dashboard_frames(:telemetry, "frame-mission-flight")
    other_realm_result = dashboard_source_result(other_realm_key)
    other_realm_frames = dashboard_frames(:telemetry, "frame-rehearsal")
    limits_result = dashboard_source_result(limits_key)
    limits_frames = dashboard_frames(:limits, "frame-limits")

    assert :ok = RuntimeCache.put_source_result(matching_key, matching_result, cache)
    assert :ok = RuntimeCache.put_frame(matching_frame_key, matching_frames, cache)
    assert :ok = RuntimeCache.put_source_result(other_realm_key, other_realm_result, cache)
    assert :ok = RuntimeCache.put_frame(other_realm_frame_key, other_realm_frames, cache)
    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)
    assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames, cache)

    assert {:ok, binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "mission-flight",
               priority: 0,
               metadata: %{reason: :updated_primary}
             })

    assert RuntimeCache.get_source_result(matching_key, cache) == :miss
    assert RuntimeCache.get_frame(matching_frame_key, cache) == :miss
    assert {:ok, ^other_realm_result} = RuntimeCache.get_source_result(other_realm_key, cache)
    assert {:ok, ^other_realm_frames} = RuntimeCache.get_frame(other_realm_frame_key, cache)
    assert {:ok, ^limits_result} = RuntimeCache.get_source_result(limits_key, cache)
    assert {:ok, ^limits_frames} = RuntimeCache.get_frame(limits_frame_key, cache)

    assert [event] = DataSources.list_data_binding_events("mission-flight-telemetry")
    assert event.event_type == :registered
    assert binding.current_event_id == event.data_binding_event_id
  end

  test "persisting a data source invalidates all dashboard caches for that source id" do
    cache = start_supervised!({RuntimeCache, name: nil})
    use_dashboard_runtime_cache!(cache)
    persist_source("mission-questdb", :mission_isolated)
    persist_limits_source("mission-limits")

    flight_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-flight-telemetry",
        data_source_id: "mission-questdb",
        realm: :flight,
        dataset: "mission-flight"
      )

    flight_frame_key = dashboard_frame_key(flight_key, "frame-flight")

    rehearsal_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-rehearsal-telemetry",
        data_source_id: "mission-questdb",
        realm: :rehearsal,
        dataset: "mission-rehearsal"
      )

    rehearsal_frame_key = dashboard_frame_key(rehearsal_key, "frame-rehearsal")

    limits_key =
      dashboard_source_result_key(:limits,
        binding_id: "mission-flight-limits",
        data_source_id: "mission-limits",
        realm: :flight,
        dataset: "telemetry_latest_limit_states"
      )

    limits_frame_key = dashboard_frame_key(limits_key, "frame-limits")

    flight_result = dashboard_source_result(flight_key)
    flight_frames = dashboard_frames(:telemetry, "frame-flight")
    rehearsal_result = dashboard_source_result(rehearsal_key)
    rehearsal_frames = dashboard_frames(:telemetry, "frame-rehearsal")
    limits_result = dashboard_source_result(limits_key)
    limits_frames = dashboard_frames(:limits, "frame-limits")

    assert :ok = RuntimeCache.put_source_result(flight_key, flight_result, cache)
    assert :ok = RuntimeCache.put_frame(flight_frame_key, flight_frames, cache)
    assert :ok = RuntimeCache.put_source_result(rehearsal_key, rehearsal_result, cache)
    assert :ok = RuntimeCache.put_frame(rehearsal_frame_key, rehearsal_frames, cache)
    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)
    assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames, cache)

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "mission-questdb",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb, reason: :updated_capabilities}
             })

    assert RuntimeCache.get_source_result(flight_key, cache) == :miss
    assert RuntimeCache.get_frame(flight_frame_key, cache) == :miss
    assert RuntimeCache.get_source_result(rehearsal_key, cache) == :miss
    assert RuntimeCache.get_frame(rehearsal_frame_key, cache) == :miss
    assert {:ok, ^limits_result} = RuntimeCache.get_source_result(limits_key, cache)
    assert {:ok, ^limits_frames} = RuntimeCache.get_frame(limits_frame_key, cache)
  end

  defp persist_source(data_source_id, isolation_level) do
    assert {:ok, data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id:
                 if(isolation_level == :mission_isolated, do: "mission-dash-source", else: nil),
               isolation_level: isolation_level,
               capabilities: %{range_scan?: true},
               metadata: %{storage: :questdb}
             })

    data_source
  end

  defp persist_watermarked_source(data_source_id) do
    assert {:ok, data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    data_source
  end

  defp source_cache_entries(result) do
    result.plan_metadata
    |> get_in([:cache, :source_result_cache_by_request_id])
    |> Map.values()
  end

  defp source_cache_statuses(result) do
    result
    |> source_cache_entries()
    |> Enum.map(& &1.status)
    |> Enum.sort()
  end

  defp segmented_history_document do
    "time_series_with_limits.v1.json"
    |> load_fixture_map!()
    |> Map.put("organization_id", "org-dash-source")
    |> Map.put("mission_id", "mission-dash-source")
    |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "observables"], [
      "HK.counter"
    ])
    |> put_in(
      ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
      "raw_series"
    )
    |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
    |> Document.from_map()
  end

  defp load_fixture_map!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  defp persist_limits_source(data_source_id) do
    assert {:ok, data_source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :projection,
               adapter: Cadence.Dashboards.Sources.Limits,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest_state?: true,
                 event_history?: true,
                 definition_intervals?: true,
                 watermarks?: true
               },
               metadata: %{storage: :postgres_projection}
             })

    data_source
  end

  defp use_dashboard_runtime_cache!(cache) do
    previous_config = Application.get_env(:cadence, :dashboard_runtime_invalidation, [])

    Application.put_env(:cadence, :dashboard_runtime_invalidation,
      enabled?: true,
      runtime_cache: cache
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_runtime_invalidation, previous_config)
    end)
  end

  defp dashboard_source_result_key(logical_source, opts) do
    request = dashboard_source_request(logical_source, opts)

    RuntimeCacheKey.source_result(request,
      source_binding: dashboard_source_binding(logical_source, opts),
      data_source: dashboard_data_source(logical_source, opts),
      watermark: dashboard_watermark(logical_source, opts)
    )
  end

  defp dashboard_frame_key(%RuntimeCacheKey{} = source_key, frame_id) do
    RuntimeCacheKey.frame(source_key,
      placement_id: "placement-#{frame_id}",
      placement_size: %{width_px: 320, height_px: 120},
      display: %{density: :normal},
      frame_shape: :scalar
    )
  end

  defp dashboard_source_request(logical_source, opts) do
    binding_id = Keyword.fetch!(opts, :binding_id)

    %PlannedSourceRequest{
      request_id: "source-request-#{binding_id}",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      logical_source: logical_source,
      observables: [Keyword.get(opts, :observable, "HK.counter")],
      data_context: %{realm: Keyword.fetch!(opts, :realm)},
      sampling: %{mode: :latest}
    }
  end

  defp dashboard_source_binding(logical_source, opts) do
    %DataBinding{
      binding_id: Keyword.fetch!(opts, :binding_id),
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: Keyword.fetch!(opts, :realm),
      logical_source: logical_source,
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      dataset: Keyword.fetch!(opts, :dataset),
      priority: 0
    }
  end

  defp dashboard_data_source(logical_source, opts) do
    %DataSource{
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      owner: :cadence,
      kind: dashboard_source_kind(logical_source),
      adapter: dashboard_source_adapter(logical_source),
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{latest?: true, latest_state?: true, event_history?: true, watermarks?: true}
    }
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

  defp dashboard_watermark(logical_source, opts) do
    %SourceWatermark{
      logical_source: logical_source,
      request_id: "source-request-#{Keyword.fetch!(opts, :binding_id)}",
      source_binding_id: Keyword.fetch!(opts, :binding_id),
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      realm: Keyword.fetch!(opts, :realm),
      dataset: Keyword.fetch!(opts, :dataset),
      complete_through: ~U[2026-06-17 12:00:00Z],
      latest_receipt_time: ~U[2026-06-17 12:00:00Z],
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: :best_effort,
      freshness_state: :fresh
    }
  end

  defp dashboard_source_kind(:limits), do: :projection
  defp dashboard_source_kind(_logical_source), do: :managed_tsdb

  defp dashboard_source_adapter(:limits), do: Cadence.Dashboards.Sources.Limits
  defp dashboard_source_adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry

  defp catalog_revision(catalog_revision_id, opts) do
    Revision.new(%{
      catalog_revision_id: catalog_revision_id,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      catalog_database_id: "bus-catalog",
      revision_number: Keyword.fetch!(opts, :revision_number),
      revision_label: Keyword.get(opts, :revision_label, "FSW 3.6"),
      catalog_family: :telemetry,
      artifact_id: "#{catalog_revision_id}-artifact",
      import_run_id: "#{catalog_revision_id}-import-run",
      telemetry_snapshot_id: "#{catalog_revision_id}-telemetry-snapshot",
      command_snapshot_id: nil,
      content_sha256: "#{catalog_revision_id}-sha",
      created_by: %{"service_identity_id" => "svc-importer"},
      metadata: %{"source_artifact_name" => "#{catalog_revision_id}.json"}
    })
  end

  defp application_binding_set(binding_set_id, opts) do
    source_endpoint_ref = Keyword.fetch!(opts, :source_endpoint_ref)
    apid = Keyword.fetch!(opts, :apid)
    metric_name = Keyword.fetch!(opts, :metric_name)

    BindingSet.new(%{
      mission_id: "mission-dash-source",
      binding_set_id: binding_set_id,
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "#{binding_set_id}-packet-counter",
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => metric_name,
              "flush_interval_ms" => 25
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "#{binding_set_id}-packet-counter-rule",
          capability_instance_id: "#{binding_set_id}-packet-counter",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: apid}
          },
          priority: 10,
          fanout_mode: :multi
        })
      ]
    })
  end

  defp persist_source_endpoint_scope(source_endpoint_ref) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: "org-dash-source",
        mission_id: "mission-dash-source",
        display_name: "SC-001"
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft("org-dash-source", spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_ref,
        organization_id: "org-dash-source",
        mission_id: "mission-dash-source",
        spacecraft_id: "sc-001",
        source_ref: "provider/#{source_endpoint_ref}"
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint("org-dash-source", source_endpoint)
  end

  defp metadata_errors(%Ecto.Changeset{} = changeset) do
    field_errors(changeset, :metadata)
  end

  defp field_errors(%Ecto.Changeset{} = changeset, field) do
    for {^field, {message, _opts}} <- changeset.errors, do: message
  end

  defp questdb_probe_exec_fun(test_pid, mode) do
    fn sql, _opts ->
      send(test_pid, {:questdb_probe_sql, sql})

      questdb_probe_response(sql, mode)
    end
  end

  defp questdb_probe_exec_with_opts_fun(test_pid, mode) do
    fn sql, opts ->
      send(test_pid, {:questdb_probe_sql, sql, opts})

      questdb_probe_response(sql, mode)
    end
  end

  defp questdb_probe_response("SELECT 1", :connection_error), do: {:error, :econnrefused}

  defp questdb_probe_response("SELECT 1", :auth_error),
    do: {:error, {:http_error, 403, %{"error" => "forbidden", "token" => "secret-token"}}}

  defp questdb_probe_response("SELECT 1", _mode),
    do: {:ok, %{"columns" => [%{"name" => "1"}], "dataset" => [[1]]}}

  defp questdb_probe_response(sql, mode) do
    cond do
      mode == :schema_ok and String.contains?(sql, "FROM telemetry_observations") ->
        {:ok, %{"columns" => questdb_probe_columns(), "dataset" => []}}

      mode == :schema_missing_identity and String.contains?(sql, "FROM telemetry_observations") ->
        columns = Enum.reject(questdb_probe_columns(), &(&1["name"] == "observation_identity_id"))
        {:ok, %{"columns" => columns, "dataset" => []}}

      mode == :schema_error and String.contains?(sql, "FROM telemetry_observations") ->
        {:error, %{"error" => "table does not exist"}}
    end
  end

  defp questdb_probe_columns do
    writer_columns =
      ObservationRow.columns()
      |> Enum.map(&Atom.to_string/1)

    (ObservationReader.select_columns() ++ writer_columns)
    |> Enum.uniq()
    |> Enum.map(&%{"name" => &1})
  end

  defp sample(point_id, sample_id, value, receipt_time, evidence_id, overrides) do
    %Sample{
      sample_id: sample_id,
      mission_id: "mission-dash-source",
      spacecraft_id: "sc-1",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: evidence_id,
      raw_value: value,
      engineering_value: value,
      quality_state: :good,
      generation_time: nil,
      receipt_time: receipt_time,
      provenance: %{}
    }
    |> struct!(overrides)
  end

  defp source_request(overrides \\ []) do
    attrs = %{
      request_id: "source-request-1",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{realm: :flight},
      sampling: %{mode: :raw_series}
    }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end
end
