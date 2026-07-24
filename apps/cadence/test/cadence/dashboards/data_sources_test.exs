defmodule Cadence.Dashboards.DataSourcesTest do
  use Cadence.ConfigCase, async: false

  import Cadence.Dashboards.DataSourcesFixtures

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSourceEvent,
    DataSourceRegistry,
    DataSources,
    SourceCredentials,
    SourceHealth,
    SourceRegistry,
    SourceResult
  }

  alias Cadence.Projections.DataSourceHealth

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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
             DataSourceHealth.probe(
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
end
