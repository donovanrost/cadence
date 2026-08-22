defmodule Cadence.Dashboards.DataSourcesProbeTest do
  use Cadence.DataCase, async: true
  use GenServer

  import Cadence.DataSourcesFixtures

  alias Cadence.Control.DataSources, as: DataSourceControl
  alias Cadence.Control.DataSources.Probes.QuestDB
  alias Cadence.DataSources.{DataSource, DataSourceEvent, Facts, SourceHealthEvent}
  alias Cadence.Management.DataSources
  alias Cadence.Platform.EventBus
  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  @organization_id "org-dash-source-probe"
  @mission_id "mission-dash-source-probe"
  @event_bus __MODULE__.UnusedEventBus
  @fact_topic {:cadence, :data_sources, :facts}

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "probes data source descriptors into source health" do
    data_source = %DataSource{
      data_source_id: "probe-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)

    assert {:ok, healthy_event, healthy_status} =
             DataSourceControl.probe(
               "probe-questdb",
               %{observed_at: ~U[2026-06-21 21:00:00Z]},
               actor_id: "operator-5",
               payload: %{source: "data_sources_test"},
               event_bus: @event_bus,
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
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id,
               data_source_id: "probe-questdb"
             )

    assert latest_status.source_health == :healthy

    first_fingerprint = healthy_event.payload["probe_metadata"]["source_capability_fingerprint"]

    assert {:ok, _updated_source} =
             DataSources.persist_data_source(
               %DataSource{
                 data_source
                 | capabilities: %{range_scan?: false}
               },
               event_bus: @event_bus
             )

    assert {:ok, :unchanged, drift_status} =
             DataSourceControl.probe(
               "probe-questdb",
               %{observed_at: ~U[2026-06-21 21:10:00Z]},
               actor_id: "operator-5",
               payload: %{source: "data_sources_test"},
               event_bus: @event_bus,
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
               occurred_at: ~U[2026-06-21 21:30:00Z],
               event_bus: @event_bus
             )

    assert {:ok, unavailable_event, unavailable_status} =
             DataSourceControl.probe(
               "probe-questdb",
               %{observed_at: ~U[2026-06-21 22:00:00Z]},
               actor_id: "operator-6",
               payload: %{source: "data_sources_test"},
               event_bus: @event_bus,
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
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: false, watermarks?: false},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)

    test_pid = self()

    assert {:ok, healthy_event, healthy_status} =
             DataSourceControl.probe(
               "questdb-schema-probe",
               %{observed_at: ~U[2026-06-21 22:15:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               data_source_probe_policy: QuestDB.policy([]),
               questdb_exec_fun: questdb_probe_exec_fun(test_pid, :schema_ok),
               event_bus: @event_bus,
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
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)

    assert {:ok, degraded_event, degraded_status} =
             DataSourceControl.probe(
               "questdb-schema-old",
               %{observed_at: ~U[2026-06-21 22:17:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               data_source_probe_policy: QuestDB.policy([]),
               questdb_exec_fun: questdb_probe_exec_fun(self(), :schema_missing_identity),
               event_bus: @event_bus,
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
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)

    assert {:ok, degraded_event, degraded_status} =
             DataSourceControl.probe(
               "questdb-schema-missing",
               %{observed_at: ~U[2026-06-21 22:20:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               data_source_probe_policy: QuestDB.policy([]),
               questdb_exec_fun: questdb_probe_exec_fun(self(), :schema_error),
               event_bus: @event_bus,
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
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)

    assert {:ok, unavailable_event, unavailable_status} =
             DataSourceControl.probe(
               "questdb-connection-failed",
               %{observed_at: ~U[2026-06-21 22:22:00Z]},
               actor_id: "operator-questdb",
               questdb_probe?: true,
               data_source_probe_policy: QuestDB.policy([]),
               questdb_exec_fun: questdb_probe_exec_fun(self(), :connection_error),
               event_bus: @event_bus,
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

  test "adapter probes can degrade data source health" do
    data_source = %DataSource{
      data_source_id: "adapter-probe-source",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :test}
    }

    assert {:ok, _persisted} = DataSources.persist_data_source(data_source, event_bus: @event_bus)

    assert {:ok, degraded_event, degraded_status} =
             DataSourceControl.probe(
               "adapter-probe-source",
               %{observed_at: ~U[2026-06-21 21:15:00Z]},
               actor_id: "operator-7",
               probe_mode: :degraded,
               test_pid: self(),
               event_bus: @event_bus,
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

  test "adapter probes persist capability discovery and publish through the selected event bus" do
    selected_bus = start_bus()
    other_bus = start_bus()

    start_fact_forwarder(:selected, selected_bus)
    start_fact_forwarder(:other, other_bus)

    data_source = %DataSource{
      data_source_id: "adapter-reported-capability-source",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: false},
      metadata: %{storage: :test}
    }

    assert {:ok, _persisted} =
             DataSources.persist_data_source(data_source, event_bus: selected_bus)

    assert_receive {:fact_delivery, :selected, @fact_topic,
                    %DataSourceEvent{event_type: :registered}}

    refute_any_fact()

    assert {:ok, healthy_event, healthy_status} =
             DataSourceControl.probe(
               "adapter-reported-capability-source",
               %{observed_at: ~U[2026-06-21 21:20:00Z]},
               actor_id: "operator-8",
               adapter_reported_capabilities: %{range_scan?: false, watermarks?: true},
               materialize_adapter_capabilities?: true,
               test_pid: self(),
               event_bus: selected_bus,
               publish_facts?: true,
               invalidate_runtime_cache?: false
             )

    assert_receive {:dashboard_source_test_adapter_probe, "adapter-reported-capability-source"}

    assert_receive {:fact_delivery, :selected, @fact_topic,
                    %SourceHealthEvent{} = published_health_event}

    assert published_health_event == healthy_event

    assert_receive {:fact_delivery, :selected, @fact_topic,
                    %DataSourceEvent{event_type: :changed} = materialized_event}

    refute_any_fact()

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
      DataSources.list_data_source_events(@organization_id, @mission_id,
        data_source_id: "adapter-reported-capability-source"
      )

    assert registered_event = Enum.find(events, &(&1.event_type == :registered))
    assert changed_event = Enum.find(events, &(&1.event_type == :changed))

    assert registered_event.event_type == :registered
    assert changed_event.event_type == :changed
    assert changed_event.data_source_event_id == materialized_event.data_source_event_id
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

  defp start_bus do
    start_supervised!(%{
      id: {:data_sources_probe_event_bus, make_ref()},
      start: {EventBus, :start_link, [[name: nil, delivery: :sync, before_notify: nil]]},
      restart: :temporary
    })
  end

  defp start_fact_forwarder(bus_tag, event_bus) do
    owner = self()

    forwarder =
      start_supervised!(%{
        id: {:data_sources_probe_fact_forwarder, bus_tag, make_ref()},
        start:
          {__MODULE__, :start_link, [[owner: owner, bus_tag: bus_tag, event_bus: event_bus]]},
        restart: :temporary
      })

    assert_receive {:fact_forwarder_ready, ^bus_tag, ^forwarder}
    forwarder
  end

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    bus_tag = Keyword.fetch!(opts, :bus_tag)
    event_bus = Keyword.fetch!(opts, :event_bus)

    :ok = Facts.subscribe(event_bus, self())
    send(owner, {:fact_forwarder_ready, bus_tag, self()})

    {:ok, %{owner: owner, bus_tag: bus_tag}}
  end

  @impl true
  def handle_call({:cadence_fact, topic, fact}, _from, state) do
    send(state.owner, {:fact_delivery, state.bus_tag, topic, fact})
    {:reply, :ok, state}
  end

  defp refute_any_fact do
    refute_received {:fact_delivery, _bus_tag, _topic, _fact}
  end
end
