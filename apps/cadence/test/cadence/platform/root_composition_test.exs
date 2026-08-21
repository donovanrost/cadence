defmodule Cadence.Platform.RootCompositionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Commanding.ProcessNamespace, as: CommandProcessNamespace
  alias Cadence.Control.ProcessNamespace, as: ControlProcessNamespace
  alias Cadence.Dashboards.{RuntimeCache, RuntimeComposition}
  alias Cadence.Platform.RootComposition
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace

  test "two explicit compositions retain distinct process and storage ownership" do
    alpha = composition(:alpha)
    bravo = composition(:bravo)

    assert alpha.event_bus == __MODULE__.AlphaEventBus
    assert bravo.event_bus == __MODULE__.BravoEventBus
    assert alpha.event_bus_child_opts[:name] == alpha.event_bus
    assert bravo.event_bus_child_opts[:name] == bravo.event_bus
    assert alpha.profiler == __MODULE__.AlphaProfiler
    assert bravo.profiler == __MODULE__.BravoProfiler

    assert alpha.ingress_archive_policy.backend_opts[:base_path] ==
             "/tmp/cadence-root-composition-alpha/ingress"

    assert bravo.ingress_archive_policy.backend_opts[:base_path] ==
             "/tmp/cadence-root-composition-bravo/ingress"

    assert alpha.record_archive_policy.backend_opts[:base_path] ==
             "/tmp/cadence-root-composition-alpha/records"

    assert bravo.record_archive_policy.backend_opts[:base_path] ==
             "/tmp/cadence-root-composition-bravo/records"

    assert alpha.current_value_store_policy.backend_opts[:table_name] ==
             :cadence_root_composition_alpha_current_values

    assert bravo.current_value_store_policy.backend_opts[:table_name] ==
             :cadence_root_composition_bravo_current_values

    assert alpha.history_store_policy.backend_opts[:table_name] ==
             :cadence_root_composition_alpha_history

    assert bravo.history_store_policy.backend_opts[:table_name] ==
             :cadence_root_composition_bravo_history

    assert alpha.runtime_persistence_policy.event_bus == alpha.event_bus
    assert bravo.runtime_persistence_policy.event_bus == bravo.event_bus
    assert alpha.runtime_persistence_policy.ingress_archive == alpha.ingress_archive_policy
    assert bravo.runtime_persistence_policy.record_archive == bravo.record_archive_policy

    assert alpha.ingress_archive_consumer_policy.archive_policy ==
             alpha.ingress_archive_policy

    assert bravo.data_management_policy.storage == bravo.telemetry_storage_policy
    assert bravo.data_management_policy.history_store == bravo.history_store_policy

    assert alpha.telemetry_storage_policy.current_value_store_policy ==
             alpha.current_value_store_policy

    assert bravo.telemetry_storage_policy.current_value_store_policy ==
             bravo.current_value_store_policy

    assert RuntimeCache.server(alpha.dashboard_runtime_composition.runtime_cache) ==
             __MODULE__.AlphaDashboardCache

    assert RuntimeCache.server(bravo.dashboard_runtime_composition.runtime_cache) ==
             __MODULE__.BravoDashboardCache

    assert alpha.control_contact_fact_consumer_opts[:event_bus] == alpha.event_bus
    assert bravo.projections_runtime_fact_consumer_opts[:event_bus] == bravo.event_bus

    assert alpha.control_contact_fact_consumer_opts[:name] ==
             alpha.control_process_namespace.contact_fact_consumer

    assert alpha.control_contact_fact_consumer_opts[:process_namespace] ==
             alpha.command_process_namespace

    assert bravo.control_contact_fact_consumer_opts[:process_namespace] ==
             bravo.command_process_namespace

    assert alpha.control_runtime_fact_consumer_opts[:process_namespace] ==
             alpha.command_process_namespace

    assert bravo.control_runtime_fact_consumer_opts[:process_namespace] ==
             bravo.command_process_namespace

    assert bravo.control_runtime_fact_consumer_opts[:name] ==
             bravo.control_process_namespace.runtime_fact_consumer

    assert alpha.command_dispatch_supervisor_child_opts[:process_namespace] ==
             alpha.command_process_namespace

    assert bravo.command_verifier_scheduler_child_opts[:process_namespace] ==
             bravo.command_process_namespace

    assert alpha.command_verifier_scheduler_child_opts[:name] ==
             alpha.command_process_namespace.verifier_scheduler

    assert bravo.command_verifier_scheduler_child_opts[:name] ==
             bravo.command_process_namespace.verifier_scheduler

    assert alpha.ingress_journal_policy.file_system_opts[:base_path] ==
             "/tmp/cadence-root-composition-alpha/journal"

    assert bravo.ingress_journal_policy.file_system_opts[:base_path] ==
             "/tmp/cadence-root-composition-bravo/journal"

    incompatible_dashboard =
      RuntimeComposition.new!(
        runtime_cache: RuntimeCache.client(__MODULE__.AlphaDashboardCache),
        runtime_invalidation_cache: RuntimeCache.client(__MODULE__.BravoDashboardCache)
      )

    assert_raise ArgumentError, ~r/invalidation cache must use the composed runtime cache/, fn ->
      RootComposition.new!(dashboard_runtime_composition: incompatible_dashboard)
    end
  end

  defp composition(owner) do
    addresses = addresses(owner)
    cache = RuntimeCache.client(addresses.dashboard_cache, call_timeout_ms: 250)

    dashboard_runtime =
      RuntimeComposition.new!(
        runtime_cache: cache,
        runtime_cache_child_opts: [
          id: addresses.dashboard_cache,
          name: addresses.dashboard_cache
        ],
        runtime_invalidation_cache: cache,
        source_circuit_breaker: addresses.source_circuit_breaker,
        source_circuit_breaker_child_opts: [
          id: addresses.source_circuit_breaker,
          name: addresses.source_circuit_breaker,
          runtime_composed?: true
        ]
      )

    RootComposition.new!(
      platform_supervisor_name: addresses.platform_supervisor,
      platform_children: [],
      event_bus: addresses.event_bus,
      event_bus_child_opts: [
        name: addresses.wrong_event_bus,
        delivery: :sync,
        before_notify: nil
      ],
      runtime_process_namespace: runtime_process_namespace(owner),
      control_process_namespace: control_process_namespace(owner),
      command_process_namespace: command_process_namespace(owner),
      projections_supervisor_name: addresses.projections_supervisor,
      ingress_archive_config: [
        module: Cadence.IngressArchive.FileSystem,
        name: addresses.ingress_writer,
        instance_id: addresses.ingress_instance_id,
        base_path: addresses.ingress_path
      ],
      record_archive_config: [
        module: Cadence.Protocol.RecordArchive.FileSystem,
        name: addresses.record_writer,
        instance_id: addresses.record_instance_id,
        base_path: addresses.record_path
      ],
      current_value_store_config: [
        module: Cadence.Telemetry.CurrentValueStore.ETS,
        name: addresses.current_store,
        child_id: addresses.current_child_id,
        table_name: addresses.current_table
      ],
      telemetry_storage_config: [writer: Cadence.Telemetry.Storage.Writers.Noop],
      history_store_config: [
        module: Cadence.Telemetry.HistoryStore.ETS,
        name: addresses.history_store,
        child_id: addresses.history_child_id,
        table_name: addresses.history_table,
        config_table_name: addresses.history_config_table
      ],
      runtime_persistence_policy: %{
        event_bus: addresses.wrong_event_bus,
        ingress_archive: :wrong_ingress_archive,
        record_archive: :wrong_record_archive,
        telemetry_storage: :wrong_telemetry_storage
      },
      ingress_archive_consumer_policy: %{archive_policy: :wrong_ingress_archive},
      data_management_policy: %{
        storage: :wrong_telemetry_storage,
        history_store: :wrong_history_store
      },
      profiler_child_opts: [name: addresses.profiler],
      runtime_health_child_opts: [
        name: addresses.runtime_health,
        event_route: addresses.runtime_health_route
      ],
      dashboard_runtime_composition: dashboard_runtime,
      dashboard_runtime_fact_consumer_opts: [name: addresses.dashboard_fact_consumer],
      control_contact_fact_consumer_opts: [
        name: addresses.control_contact_consumer,
        event_bus: addresses.wrong_event_bus,
        process_namespace: CommandProcessNamespace.default()
      ],
      control_runtime_fact_consumer_opts: [
        name: addresses.control_runtime_consumer,
        event_bus: addresses.wrong_event_bus,
        process_namespace: CommandProcessNamespace.default()
      ],
      projections_runtime_fact_consumer_opts: [
        name: addresses.projections_runtime_consumer,
        event_bus: addresses.wrong_event_bus
      ],
      projections_telemetry_fact_consumer_opts: [
        name: addresses.projections_telemetry_consumer
      ],
      projections_domain_fact_consumer_opts: [name: addresses.projections_domain_consumer],
      command_dispatch_supervisor_child_opts: [auto_schedule?: false],
      command_verifier_scheduler_child_opts: [auto_schedule?: false],
      ingress_journal_config: [base_path: addresses.journal_path],
      data_source_probe_scheduler_config: [enabled?: false],
      mission_health_observability_children: []
    )
  end

  defp runtime_process_namespace(:alpha) do
    RuntimeProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaRuntimeSupervisor,
      registry: __MODULE__.AlphaRuntimeRegistry,
      mission_supervisor: __MODULE__.AlphaRuntimeMissionSupervisor,
      capability_registry: __MODULE__.AlphaRuntimeCapabilityRegistry
    )
  end

  defp runtime_process_namespace(:bravo) do
    RuntimeProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoRuntimeSupervisor,
      registry: __MODULE__.BravoRuntimeRegistry,
      mission_supervisor: __MODULE__.BravoRuntimeMissionSupervisor,
      capability_registry: __MODULE__.BravoRuntimeCapabilityRegistry
    )
  end

  defp control_process_namespace(:alpha) do
    ControlProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaControlSupervisor,
      registry: __MODULE__.AlphaControlRegistry,
      mission_supervisor: __MODULE__.AlphaControlMissionSupervisor,
      mission_recovery: __MODULE__.AlphaMissionRecovery,
      contact_fact_consumer: __MODULE__.AlphaContactFactConsumer,
      runtime_fact_consumer: __MODULE__.AlphaControlRuntimeFactConsumer
    )
  end

  defp control_process_namespace(:bravo) do
    ControlProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoControlSupervisor,
      registry: __MODULE__.BravoControlRegistry,
      mission_supervisor: __MODULE__.BravoControlMissionSupervisor,
      mission_recovery: __MODULE__.BravoMissionRecovery,
      contact_fact_consumer: __MODULE__.BravoContactFactConsumer,
      runtime_fact_consumer: __MODULE__.BravoControlRuntimeFactConsumer
    )
  end

  defp command_process_namespace(:alpha) do
    CommandProcessNamespace.new!(
      root_supervisor: __MODULE__.AlphaCommandSupervisor,
      registry: __MODULE__.AlphaCommandRegistry,
      lane_supervisor: __MODULE__.AlphaCommandLaneSupervisor,
      dispatcher: __MODULE__.AlphaCommandDispatcher,
      verifier_scheduler: __MODULE__.AlphaCommandVerifierScheduler
    )
  end

  defp command_process_namespace(:bravo) do
    CommandProcessNamespace.new!(
      root_supervisor: __MODULE__.BravoCommandSupervisor,
      registry: __MODULE__.BravoCommandRegistry,
      lane_supervisor: __MODULE__.BravoCommandLaneSupervisor,
      dispatcher: __MODULE__.BravoCommandDispatcher,
      verifier_scheduler: __MODULE__.BravoCommandVerifierScheduler
    )
  end

  defp addresses(:alpha) do
    %{
      platform_supervisor: __MODULE__.AlphaPlatformSupervisor,
      event_bus: __MODULE__.AlphaEventBus,
      wrong_event_bus: __MODULE__.WrongAlphaEventBus,
      projections_supervisor: __MODULE__.AlphaProjectionsSupervisor,
      ingress_writer: __MODULE__.AlphaIngressWriter,
      ingress_instance_id: "root-composition-alpha-ingress",
      ingress_path: "/tmp/cadence-root-composition-alpha/ingress",
      record_writer: __MODULE__.AlphaRecordWriter,
      record_instance_id: "root-composition-alpha-records",
      record_path: "/tmp/cadence-root-composition-alpha/records",
      current_store: __MODULE__.AlphaCurrentStore,
      current_child_id: {__MODULE__, :alpha_current_store},
      current_table: :cadence_root_composition_alpha_current_values,
      history_store: __MODULE__.AlphaHistoryStore,
      history_child_id: {__MODULE__, :alpha_history_store},
      history_table: :cadence_root_composition_alpha_history,
      history_config_table: :cadence_root_composition_alpha_history_config,
      profiler: __MODULE__.AlphaProfiler,
      runtime_health: __MODULE__.AlphaRuntimeHealth,
      runtime_health_route: {__MODULE__, :alpha_runtime_health},
      dashboard_cache: __MODULE__.AlphaDashboardCache,
      source_circuit_breaker: __MODULE__.AlphaSourceCircuitBreaker,
      dashboard_fact_consumer: __MODULE__.AlphaDashboardFactConsumer,
      control_contact_consumer: __MODULE__.AlphaControlContactConsumer,
      control_runtime_consumer: __MODULE__.AlphaControlRuntimeConsumer,
      projections_runtime_consumer: __MODULE__.AlphaProjectionsRuntimeConsumer,
      projections_telemetry_consumer: __MODULE__.AlphaProjectionsTelemetryConsumer,
      projections_domain_consumer: __MODULE__.AlphaProjectionsDomainConsumer,
      journal_path: "/tmp/cadence-root-composition-alpha/journal"
    }
  end

  defp addresses(:bravo) do
    %{
      platform_supervisor: __MODULE__.BravoPlatformSupervisor,
      event_bus: __MODULE__.BravoEventBus,
      wrong_event_bus: __MODULE__.WrongBravoEventBus,
      projections_supervisor: __MODULE__.BravoProjectionsSupervisor,
      ingress_writer: __MODULE__.BravoIngressWriter,
      ingress_instance_id: "root-composition-bravo-ingress",
      ingress_path: "/tmp/cadence-root-composition-bravo/ingress",
      record_writer: __MODULE__.BravoRecordWriter,
      record_instance_id: "root-composition-bravo-records",
      record_path: "/tmp/cadence-root-composition-bravo/records",
      current_store: __MODULE__.BravoCurrentStore,
      current_child_id: {__MODULE__, :bravo_current_store},
      current_table: :cadence_root_composition_bravo_current_values,
      history_store: __MODULE__.BravoHistoryStore,
      history_child_id: {__MODULE__, :bravo_history_store},
      history_table: :cadence_root_composition_bravo_history,
      history_config_table: :cadence_root_composition_bravo_history_config,
      profiler: __MODULE__.BravoProfiler,
      runtime_health: __MODULE__.BravoRuntimeHealth,
      runtime_health_route: {__MODULE__, :bravo_runtime_health},
      dashboard_cache: __MODULE__.BravoDashboardCache,
      source_circuit_breaker: __MODULE__.BravoSourceCircuitBreaker,
      dashboard_fact_consumer: __MODULE__.BravoDashboardFactConsumer,
      control_contact_consumer: __MODULE__.BravoControlContactConsumer,
      control_runtime_consumer: __MODULE__.BravoControlRuntimeConsumer,
      projections_runtime_consumer: __MODULE__.BravoProjectionsRuntimeConsumer,
      projections_telemetry_consumer: __MODULE__.BravoProjectionsTelemetryConsumer,
      projections_domain_consumer: __MODULE__.BravoProjectionsDomainConsumer,
      journal_path: "/tmp/cadence-root-composition-bravo/journal"
    }
  end
end
