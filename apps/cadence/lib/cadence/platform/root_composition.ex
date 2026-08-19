defmodule Cadence.Platform.RootComposition do
  @moduledoc """
  Immutable process addresses and policies owned by one Cadence subsystem root.

  `from_application/1` is the compatibility boundary for process-wide
  configuration. Supervisors and their long-lived children receive the
  resulting value explicitly so one running root cannot observe configuration
  captured for another root.
  """

  alias Cadence.Commanding.ProcessNamespace, as: CommandProcessNamespace
  alias Cadence.Control.ProcessNamespace, as: ControlProcessNamespace
  alias Cadence.Dashboards.{RuntimeCache, RuntimeComposition, SourceCircuitBreaker}
  alias Cadence.IngressArchive
  alias Cadence.IngressJournal.FileSystem, as: IngressJournal
  alias Cadence.Protocol.RecordArchive
  alias Cadence.Runtime.{IngressArchiveConsumer, Persistence}
  alias Cadence.Runtime.ProcessNamespace, as: RuntimeProcessNamespace
  alias Cadence.Telemetry.{CurrentValueStore, DataManagement, HistoryStore, Storage}

  @enforce_keys [
    :platform_supervisor_name,
    :platform_children,
    :event_bus,
    :event_bus_child_opts,
    :runtime_process_namespace,
    :control_process_namespace,
    :command_process_namespace,
    :projections_supervisor_name,
    :current_value_store_policy,
    :telemetry_storage_policy,
    :history_store_policy,
    :ingress_archive_policy,
    :record_archive_policy,
    :runtime_persistence_policy,
    :ingress_archive_consumer_policy,
    :data_management_policy,
    :profiler_child_opts,
    :runtime_health_child_opts,
    :dashboard_runtime_composition,
    :dashboard_runtime_fact_consumer_opts,
    :control_contact_fact_consumer_opts,
    :control_runtime_fact_consumer_opts,
    :projections_runtime_fact_consumer_opts,
    :projections_telemetry_fact_consumer_opts,
    :projections_domain_fact_consumer_opts,
    :contact_scheduler_config,
    :contact_scheduler_global_safety_config,
    :provider_reservation_reconciler_config,
    :provider_event_ingestion_config,
    :command_dispatch_supervisor_enabled?,
    :command_dispatch_supervisor_child_opts,
    :command_verifier_scheduler_enabled?,
    :command_verifier_scheduler_child_opts,
    :ingress_journal_policy,
    :data_source_probe_scheduler_config,
    :mission_health_observability_children
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @doc """
  Builds a root composition without reading application configuration.

  Alternate roots should provide existing atoms for every registered process
  and unique backend addresses or storage paths in their explicit policies.
  """
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) when is_list(opts) do
    event_bus = Keyword.get(opts, :event_bus, Cadence.Platform.EventBus)

    event_bus_child_opts =
      opts
      |> Keyword.get(:event_bus_child_opts, [])
      |> Keyword.put(:name, event_bus)
      |> Keyword.put_new(:delivery, :async)
      |> Keyword.put_new(:before_notify, nil)

    current_value_store_policy =
      Keyword.get_lazy(opts, :current_value_store_policy, fn ->
        opts
        |> Keyword.get(:current_value_store_config, [])
        |> CurrentValueStore.policy()
      end)

    telemetry_storage_policy =
      Keyword.get_lazy(opts, :telemetry_storage_policy, fn ->
        opts
        |> Keyword.get(:telemetry_storage_config, [])
        |> Storage.policy(
          current_value_store_policy: current_value_store_policy,
          event_bus: event_bus
        )
      end)
      |> Map.put(:current_value_store_policy, current_value_store_policy)
      |> Map.put(:event_bus, event_bus)

    history_store_policy =
      Keyword.get_lazy(opts, :history_store_policy, fn ->
        opts
        |> Keyword.get(:history_store_config, [])
        |> HistoryStore.policy(storage_policy: telemetry_storage_policy)
      end)
      |> Map.put(:storage_policy, telemetry_storage_policy)

    ingress_archive_policy =
      Keyword.get_lazy(opts, :ingress_archive_policy, fn ->
        opts
        |> Keyword.get(:ingress_archive_config, [])
        |> IngressArchive.policy()
      end)

    record_archive_policy =
      Keyword.get_lazy(opts, :record_archive_policy, fn ->
        opts
        |> Keyword.get(:record_archive_config, [])
        |> RecordArchive.policy()
      end)

    runtime_persistence_policy =
      Keyword.get_lazy(opts, :runtime_persistence_policy, fn ->
        Persistence.policy(
          ingress_archive_policy,
          record_archive_policy,
          telemetry_storage_policy,
          event_bus: event_bus
        )
      end)
      |> Map.put(:ingress_archive, ingress_archive_policy)
      |> Map.put(:record_archive, record_archive_policy)
      |> Map.put(:telemetry_storage, telemetry_storage_policy)
      |> Map.put(:event_bus, event_bus)

    ingress_archive_consumer_policy =
      Keyword.get_lazy(opts, :ingress_archive_consumer_policy, fn ->
        IngressArchiveConsumer.policy(
          Keyword.get(opts, :ingress_archive_consumer_config, []),
          ingress_archive_policy
        )
      end)
      |> Map.put(:archive_policy, ingress_archive_policy)

    ingress_journal_policy =
      Keyword.get_lazy(opts, :ingress_journal_policy, fn ->
        opts
        |> Keyword.get(:ingress_journal_config, [])
        |> IngressJournal.policy()
      end)

    data_management_policy =
      Keyword.get_lazy(opts, :data_management_policy, fn ->
        DataManagement.policy(telemetry_storage_policy, history_store_policy)
      end)
      |> Map.put(:storage, telemetry_storage_policy)
      |> Map.put(:history_store, history_store_policy)

    dashboard_runtime_composition =
      opts
      |> Keyword.get_lazy(:dashboard_runtime_composition, fn ->
        default_dashboard_runtime_composition(
          current_value_store_policy,
          telemetry_storage_policy,
          history_store_policy
        )
      end)
      |> align_dashboard_telemetry_policies(
        current_value_store_policy,
        telemetry_storage_policy,
        history_store_policy
      )
      |> align_dashboard_resource_names()

    profiler_child_opts =
      opts
      |> Keyword.get(:profiler_child_opts, [])
      |> Keyword.put_new(:name, Cadence.Telemetry.Profiler)
      |> Keyword.put(:ingress_archive_policy, ingress_archive_policy)
      |> Keyword.put(:record_archive_policy, record_archive_policy)

    runtime_health_child_opts =
      opts
      |> Keyword.get(:runtime_health_child_opts, [])
      |> Keyword.put_new(:name, Cadence.Telemetry.RuntimeHealth)
      |> Keyword.put_new(:event_route, :default)

    runtime_process_namespace =
      Keyword.get_lazy(opts, :runtime_process_namespace, &RuntimeProcessNamespace.default/0)

    control_process_namespace =
      Keyword.get_lazy(opts, :control_process_namespace, &ControlProcessNamespace.default/0)

    command_process_namespace =
      Keyword.get_lazy(opts, :command_process_namespace, &CommandProcessNamespace.default/0)

    command_dispatcher_config = Keyword.get(opts, :command_dispatcher_config, [])

    command_dispatch_supervisor_child_opts =
      opts
      |> Keyword.get(
        :command_dispatch_supervisor_child_opts,
        Keyword.delete(command_dispatcher_config, :enabled)
      )
      |> Keyword.put(:process_namespace, command_process_namespace)

    command_verifier_scheduler_config =
      Keyword.get(opts, :command_verifier_scheduler_config, [])

    command_verifier_scheduler_child_opts =
      opts
      |> Keyword.get(
        :command_verifier_scheduler_child_opts,
        Keyword.delete(command_verifier_scheduler_config, :enabled)
      )
      |> Keyword.put(:process_namespace, command_process_namespace)
      |> Keyword.put(:name, command_process_namespace.verifier_scheduler)

    %__MODULE__{
      platform_supervisor_name:
        Keyword.get(opts, :platform_supervisor_name, Cadence.Platform.Supervisor),
      platform_children:
        Keyword.get(opts, :platform_children, [
          Cadence.Repo,
          {Phoenix.PubSub, name: Cadence.PubSub}
        ]),
      event_bus: event_bus,
      event_bus_child_opts: event_bus_child_opts,
      runtime_process_namespace: runtime_process_namespace,
      control_process_namespace: control_process_namespace,
      command_process_namespace: command_process_namespace,
      projections_supervisor_name:
        Keyword.get(opts, :projections_supervisor_name, Cadence.Projections.Supervisor),
      current_value_store_policy: current_value_store_policy,
      telemetry_storage_policy: telemetry_storage_policy,
      history_store_policy: history_store_policy,
      ingress_archive_policy: ingress_archive_policy,
      record_archive_policy: record_archive_policy,
      runtime_persistence_policy: runtime_persistence_policy,
      ingress_archive_consumer_policy: ingress_archive_consumer_policy,
      data_management_policy: data_management_policy,
      profiler_child_opts: profiler_child_opts,
      runtime_health_child_opts: runtime_health_child_opts,
      dashboard_runtime_composition: dashboard_runtime_composition,
      dashboard_runtime_fact_consumer_opts:
        consumer_opts(
          opts,
          :dashboard_runtime_fact_consumer_opts,
          Cadence.Dashboards.RuntimeFactConsumer,
          event_bus
        ),
      control_contact_fact_consumer_opts:
        consumer_opts(
          opts,
          :control_contact_fact_consumer_opts,
          control_process_namespace.contact_fact_consumer,
          event_bus
        )
        |> Keyword.put(:name, control_process_namespace.contact_fact_consumer),
      control_runtime_fact_consumer_opts:
        consumer_opts(
          opts,
          :control_runtime_fact_consumer_opts,
          control_process_namespace.runtime_fact_consumer,
          event_bus
        )
        |> Keyword.put(:name, control_process_namespace.runtime_fact_consumer),
      projections_runtime_fact_consumer_opts:
        consumer_opts(
          opts,
          :projections_runtime_fact_consumer_opts,
          Cadence.Projections.RuntimeFactConsumer,
          event_bus
        ),
      projections_telemetry_fact_consumer_opts:
        consumer_opts(
          opts,
          :projections_telemetry_fact_consumer_opts,
          Cadence.Projections.TelemetryFactConsumer,
          event_bus
        ),
      projections_domain_fact_consumer_opts:
        consumer_opts(
          opts,
          :projections_domain_fact_consumer_opts,
          Cadence.Projections.DomainFactConsumer,
          event_bus
        ),
      contact_scheduler_config: Keyword.get(opts, :contact_scheduler_config, []),
      contact_scheduler_global_safety_config:
        Keyword.get(opts, :contact_scheduler_global_safety_config, []),
      provider_reservation_reconciler_config:
        Keyword.get(opts, :provider_reservation_reconciler_config, []),
      provider_event_ingestion_config: Keyword.get(opts, :provider_event_ingestion_config, []),
      command_dispatch_supervisor_enabled?:
        Keyword.get(
          opts,
          :command_dispatch_supervisor_enabled?,
          Keyword.get(command_dispatcher_config, :enabled, true) == true
        ),
      command_dispatch_supervisor_child_opts: command_dispatch_supervisor_child_opts,
      command_verifier_scheduler_enabled?:
        Keyword.get(
          opts,
          :command_verifier_scheduler_enabled?,
          Keyword.get(command_verifier_scheduler_config, :enabled, true) == true
        ),
      command_verifier_scheduler_child_opts: command_verifier_scheduler_child_opts,
      ingress_journal_policy: ingress_journal_policy,
      data_source_probe_scheduler_config:
        Keyword.get(opts, :data_source_probe_scheduler_config, []),
      mission_health_observability_children:
        Keyword.get(opts, :mission_health_observability_children, [])
    }
  end

  @doc """
  Captures the production-compatible root composition from application config.

  Explicit options replace captured values and are intended for tests and
  alternate subsystem roots.
  """
  @spec from_application(keyword()) :: t()
  def from_application(opts \\ []) when is_list(opts) do
    event_bus = Keyword.get(opts, :event_bus, Cadence.Platform.EventBus)

    ingress_journal_policy =
      Keyword.get_lazy(opts, :ingress_journal_policy, fn ->
        opts
        |> Keyword.get(
          :ingress_journal_config,
          Application.get_env(:cadence, :ingress_journal, [])
        )
        |> IngressJournal.policy()
      end)

    dashboard_runtime_composition =
      Keyword.get_lazy(opts, :dashboard_runtime_composition, fn ->
        RuntimeComposition.from_application(
          runtime_cache_server: Keyword.get(opts, :dashboard_runtime_cache_server, RuntimeCache),
          source_circuit_breaker_server:
            Keyword.get(opts, :dashboard_source_circuit_breaker_server, SourceCircuitBreaker)
        )
      end)

    contact_scheduler_config =
      case Keyword.fetch(opts, :contact_scheduler_config) do
        {:ok, config} ->
          config

        :error ->
          :cadence
          |> Application.get_env(:contact_scheduler, [])
          |> Keyword.merge(Keyword.get(opts, :contact_scheduler_opts, []))
          |> maybe_put_enabled(opts, :contact_scheduler_enabled?)
      end

    captured_opts = [
      event_bus: event_bus,
      event_bus_child_opts: Application.get_env(:cadence, :event_bus, []),
      ingress_archive_config: Application.get_env(:cadence, :ingress_archive, []),
      record_archive_config: Application.get_env(:cadence, :protocol_record_archive, []),
      current_value_store_config:
        Application.get_env(:cadence, :telemetry_current_value_store, []),
      telemetry_storage_config: Application.get_env(:cadence, :telemetry_storage, []),
      history_store_config: Application.get_env(:cadence, :telemetry_history_store, []),
      ingress_archive_consumer_config:
        Application.get_env(:cadence, :ingress_archive_consumer, []),
      dashboard_runtime_composition: dashboard_runtime_composition,
      contact_scheduler_config: contact_scheduler_config,
      contact_scheduler_global_safety_config:
        Application.get_env(:cadence, :contact_scheduler_global_safety, []),
      provider_reservation_reconciler_config:
        Application.get_env(:cadence, :provider_reservation_reconciler, []),
      provider_event_ingestion_config:
        Application.get_env(:cadence, :provider_event_ingestion, []),
      command_dispatcher_config: Application.get_env(:cadence, :command_dispatcher, []),
      command_verifier_scheduler_config:
        Application.get_env(:cadence, :command_verifier_scheduler, []),
      ingress_journal_policy: ingress_journal_policy,
      data_source_probe_scheduler_config:
        Application.get_env(:cadence, :data_source_probe_scheduler, []),
      platform_children: configured_platform_children(),
      mission_health_observability_children: configured_mission_health_children()
    ]

    captured_opts
    |> Keyword.merge(opts)
    |> new!()
  end

  defp default_dashboard_runtime_composition(
         current_value_store_policy,
         telemetry_storage_policy,
         history_store_policy
       ) do
    cache = RuntimeCache.client(RuntimeCache)

    RuntimeComposition.new!(
      runtime_cache_enabled?: true,
      runtime_cache: cache,
      runtime_invalidation_cache: cache,
      telemetry_current_value_store_policy: current_value_store_policy,
      telemetry_storage_policy: telemetry_storage_policy,
      telemetry_history_store_policy: history_store_policy
    )
  end

  defp align_dashboard_telemetry_policies(
         %RuntimeComposition{} = composition,
         current_value_store_policy,
         telemetry_storage_policy,
         history_store_policy
       ) do
    %{
      composition
      | telemetry_current_value_store_policy: current_value_store_policy,
        telemetry_storage_policy: telemetry_storage_policy,
        telemetry_history_store_policy: history_store_policy
    }
  end

  defp align_dashboard_resource_names(
         %RuntimeComposition{runtime_cache_enabled?: true, runtime_cache: %RuntimeCache{} = cache} =
           composition
       ) do
    cache_server = RuntimeCache.server(cache)
    validate_invalidation_cache!(composition.runtime_invalidation_cache, cache_server)

    composition
    |> Map.put(
      :runtime_cache_child_opts,
      Keyword.put(composition.runtime_cache_child_opts, :name, cache_server)
    )
    |> align_source_circuit_breaker_name()
  end

  defp align_dashboard_resource_names(%RuntimeComposition{runtime_cache_enabled?: true}) do
    raise ArgumentError,
          "dashboard runtime cache must be an explicit RuntimeCache client when enabled"
  end

  defp align_dashboard_resource_names(%RuntimeComposition{} = composition),
    do: align_source_circuit_breaker_name(composition)

  defp align_source_circuit_breaker_name(
         %RuntimeComposition{
           source_circuit_breaker_enabled?: true,
           source_circuit_breaker: server
         } = composition
       )
       when not is_nil(server) do
    Map.put(
      composition,
      :source_circuit_breaker_child_opts,
      Keyword.put(composition.source_circuit_breaker_child_opts, :name, server)
    )
  end

  defp align_source_circuit_breaker_name(%RuntimeComposition{
         source_circuit_breaker_enabled?: true
       }) do
    raise ArgumentError,
          "dashboard source circuit breaker must have an explicit server when enabled"
  end

  defp align_source_circuit_breaker_name(%RuntimeComposition{} = composition), do: composition

  defp validate_invalidation_cache!(false, _cache_server), do: :ok
  defp validate_invalidation_cache!(nil, _cache_server), do: :ok

  defp validate_invalidation_cache!(%RuntimeCache{} = cache, cache_server) do
    if RuntimeCache.server(cache) == cache_server do
      :ok
    else
      raise ArgumentError,
            "dashboard runtime invalidation cache must use the composed runtime cache server"
    end
  end

  defp validate_invalidation_cache!(other, cache_server) do
    if other == cache_server do
      :ok
    else
      raise ArgumentError,
            "dashboard runtime invalidation cache must use the composed runtime cache server"
    end
  end

  defp consumer_opts(opts, key, default_name, event_bus) do
    opts
    |> Keyword.get(key, [])
    |> Keyword.put_new(:name, default_name)
    |> Keyword.put(:event_bus, event_bus)
  end

  defp maybe_put_enabled(config, opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, enabled?} -> Keyword.put(config, :enabled, enabled?)
      :error -> config
    end
  end

  defp configured_platform_children do
    [
      Cadence.Observability.log_exporter_child_spec(),
      Cadence.Observability.metrics_reporter_child_spec(),
      Cadence.Observability.metrics_sampler_child_spec(),
      Cadence.Repo,
      {Phoenix.PubSub, name: Cadence.PubSub}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp configured_mission_health_children do
    [Cadence.Observability.mission_health_sampler_child_spec()]
    |> Enum.reject(&is_nil/1)
  end
end
