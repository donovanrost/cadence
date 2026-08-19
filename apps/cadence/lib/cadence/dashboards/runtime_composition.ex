defmodule Cadence.Dashboards.RuntimeComposition do
  @moduledoc """
  Immutable dashboard runtime dependencies captured at a composition boundary.

  Projection startup and LiveView mount each build this value once. Request,
  fact-consumer, tick, and async execution paths receive the captured policies
  explicitly and therefore do not observe later process-wide config changes.
  """

  alias Cadence.Dashboards.{
    RuntimeCache,
    SourceCircuitBreaker,
    SourceExecutionPolicy,
    SourceReadiness
  }

  alias Cadence.Telemetry.{CurrentValueStore, HistoryStore, Storage}

  @enforce_keys [
    :runtime_cache_enabled?,
    :runtime_cache,
    :runtime_cache_child_opts,
    :plan_cache?,
    :source_result_cache?,
    :frame_cache?,
    :runtime_invalidation?,
    :runtime_invalidation_cache,
    :source_execution_defaults,
    :source_readiness_policy,
    :source_circuit_breaker_enabled?,
    :source_circuit_breaker,
    :source_circuit_breaker_child_opts,
    :source_health_events?,
    :record_source_health_events?,
    :source_health_freshness,
    :source_watermark_events?,
    :data_sources_persisted?,
    :telemetry_current_value_store_policy,
    :telemetry_storage_policy,
    :telemetry_history_store_policy
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          runtime_cache_enabled?: boolean(),
          runtime_cache: false | RuntimeCache.t(),
          runtime_cache_child_opts: keyword(),
          plan_cache?: boolean(),
          source_result_cache?: boolean(),
          frame_cache?: boolean(),
          runtime_invalidation?: boolean(),
          runtime_invalidation_cache: false | RuntimeCache.t(),
          source_execution_defaults: SourceExecutionPolicy.t(),
          source_readiness_policy: SourceReadiness.policy(),
          source_circuit_breaker_enabled?: boolean(),
          source_circuit_breaker: GenServer.server() | nil,
          source_circuit_breaker_child_opts: keyword(),
          source_health_events?: boolean(),
          record_source_health_events?: boolean(),
          source_health_freshness: keyword() | map(),
          source_watermark_events?: boolean(),
          data_sources_persisted?: boolean(),
          telemetry_current_value_store_policy: CurrentValueStore.policy(),
          telemetry_storage_policy: Storage.policy(),
          telemetry_history_store_policy: HistoryStore.policy()
        }

  @doc """
  Builds a pure runtime composition from explicit dependencies.

  Defaults are process-independent and match the dashboard production
  fallbacks. Tests should use this constructor instead of mutating application
  configuration.
  """
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) when is_list(opts) do
    current_value_store_policy =
      Keyword.get_lazy(opts, :telemetry_current_value_store_policy, fn ->
        CurrentValueStore.policy([])
      end)

    telemetry_storage_policy =
      Keyword.get_lazy(opts, :telemetry_storage_policy, fn ->
        Storage.policy([], current_value_store_policy: current_value_store_policy)
      end)

    telemetry_history_store_policy =
      Keyword.get_lazy(opts, :telemetry_history_store_policy, fn ->
        HistoryStore.policy([], storage_policy: telemetry_storage_policy)
      end)

    runtime_cache = Keyword.get(opts, :runtime_cache, false)
    runtime_cache_enabled? = Keyword.get(opts, :runtime_cache_enabled?, runtime_cache != false)
    circuit_server = Keyword.get(opts, :source_circuit_breaker)

    source_health_events? = Keyword.get(opts, :source_health_events?, true)

    %__MODULE__{
      runtime_cache_enabled?: runtime_cache_enabled?,
      runtime_cache: runtime_cache,
      runtime_cache_child_opts: Keyword.get(opts, :runtime_cache_child_opts, []),
      plan_cache?: Keyword.get(opts, :plan_cache?, runtime_cache != false),
      source_result_cache?: Keyword.get(opts, :source_result_cache?, runtime_cache != false),
      frame_cache?: Keyword.get(opts, :frame_cache?, runtime_cache != false),
      runtime_invalidation?: Keyword.get(opts, :runtime_invalidation?, true),
      runtime_invalidation_cache: Keyword.get(opts, :runtime_invalidation_cache, runtime_cache),
      source_execution_defaults:
        Keyword.get(opts, :source_execution_defaults, SourceExecutionPolicy.default()),
      source_readiness_policy:
        opts
        |> Keyword.get(:source_readiness_policy, SourceReadiness.default_policy())
        |> SourceReadiness.normalize_policy(),
      source_circuit_breaker_enabled?:
        Keyword.get(opts, :source_circuit_breaker_enabled?, not is_nil(circuit_server)),
      source_circuit_breaker: circuit_server,
      source_circuit_breaker_child_opts:
        Keyword.get(opts, :source_circuit_breaker_child_opts, []),
      source_health_events?: source_health_events?,
      record_source_health_events?:
        Keyword.get(opts, :record_source_health_events?, source_health_events?),
      source_health_freshness: Keyword.get(opts, :source_health_freshness, []),
      source_watermark_events?: Keyword.get(opts, :source_watermark_events?, true),
      data_sources_persisted?: Keyword.get(opts, :data_sources_persisted?, false),
      telemetry_current_value_store_policy: current_value_store_policy,
      telemetry_storage_policy: telemetry_storage_policy,
      telemetry_history_store_policy: telemetry_history_store_policy
    }
  end

  @doc """
  Captures dashboard runtime configuration from the application environment.

  The optional server values are resolved by the owning boundary. Projection
  startup passes stable registered names before children start; LiveView mount
  passes only processes that exist for that mounted runtime.
  """
  @spec from_application(keyword()) :: t()
  def from_application(opts \\ []) when is_list(opts) do
    cache_config = Application.get_env(:cadence, :dashboard_runtime_cache, [])
    invalidation_config = Application.get_env(:cadence, :dashboard_runtime_invalidation, [])
    circuit_config = Application.get_env(:cadence, :dashboard_source_circuit_breaker, [])
    health_config = Application.get_env(:cadence, :data_source_health_events, [])
    watermark_config = Application.get_env(:cadence, :data_source_watermark_events, [])
    data_sources_config = Application.get_env(:cadence, :data_sources, [])

    current_value_store_policy =
      :cadence
      |> Application.get_env(:telemetry_current_value_store, [])
      |> CurrentValueStore.policy()

    telemetry_storage_policy =
      :cadence
      |> Application.get_env(:telemetry_storage, [])
      |> Storage.policy(current_value_store_policy: current_value_store_policy)

    telemetry_history_store_policy =
      :cadence
      |> Application.get_env(:telemetry_history_store, [])
      |> HistoryStore.policy(storage_policy: telemetry_storage_policy)

    runtime_cache_enabled? = Keyword.get(cache_config, :enabled?, true) == true
    runtime_cache_server = Keyword.get(opts, :runtime_cache_server, RuntimeCache)

    runtime_cache =
      if runtime_cache_enabled? and not is_nil(runtime_cache_server) do
        RuntimeCache.client(runtime_cache_server, cache_config)
      else
        false
      end

    runtime_invalidation_cache =
      case Keyword.get(invalidation_config, :runtime_cache, runtime_cache) do
        nil -> runtime_cache
        false -> false
        %RuntimeCache{} = cache -> cache
        server -> RuntimeCache.client(server, cache_config)
      end

    source_circuit_breaker_server =
      Keyword.get(opts, :source_circuit_breaker_server, SourceCircuitBreaker)

    source_circuit_breaker_enabled? =
      Keyword.get(circuit_config, :enabled?, false) == true and
        not is_nil(source_circuit_breaker_server)

    %__MODULE__{
      runtime_cache_enabled?: runtime_cache_enabled?,
      runtime_cache: runtime_cache,
      runtime_cache_child_opts: cache_config,
      plan_cache?: runtime_cache != false,
      source_result_cache?:
        runtime_cache != false and Keyword.get(cache_config, :source_result_cache?, true) == true,
      frame_cache?:
        runtime_cache != false and Keyword.get(cache_config, :frame_cache?, true) == true,
      runtime_invalidation?: Keyword.get(invalidation_config, :enabled?, true) == true,
      runtime_invalidation_cache: runtime_invalidation_cache,
      source_execution_defaults: SourceExecutionPolicy.configured_defaults(),
      source_readiness_policy: SourceReadiness.configured_policy(),
      source_circuit_breaker_enabled?: source_circuit_breaker_enabled?,
      source_circuit_breaker:
        if(source_circuit_breaker_enabled?, do: source_circuit_breaker_server),
      source_circuit_breaker_child_opts: Keyword.put(circuit_config, :runtime_composed?, true),
      source_health_events?: Keyword.get(health_config, :enabled?, true) == true,
      record_source_health_events?: Keyword.get(health_config, :enabled?, true) == true,
      source_health_freshness: Keyword.get(health_config, :freshness, []),
      source_watermark_events?: Keyword.get(watermark_config, :enabled?, true) == true,
      data_sources_persisted?: Keyword.get(data_sources_config, :persisted?, false) == true,
      telemetry_current_value_store_policy: current_value_store_policy,
      telemetry_storage_policy: telemetry_storage_policy,
      telemetry_history_store_policy: telemetry_history_store_policy
    }
  end

  @doc """
  Adds captured policies to explicit source execution options.

  Caller-provided values retain precedence so focused tests and alternate
  runtime roots can inject collaborators without process-wide mutation.
  """
  @spec source_execution_opts(t(), keyword()) :: keyword()
  def source_execution_opts(%__MODULE__{} = composition, opts \\ []) when is_list(opts) do
    opts
    |> Keyword.put_new(:source_execution_defaults, composition.source_execution_defaults)
    |> Keyword.put_new(:source_readiness_policy, composition.source_readiness_policy)
    |> Keyword.put_new(:source_circuit_breaker?, composition.source_circuit_breaker_enabled?)
    |> maybe_put_new(:source_circuit_breaker, composition.source_circuit_breaker)
    |> Keyword.put_new(:source_health_events?, composition.source_health_events?)
    |> Keyword.put_new(
      :record_source_health_events?,
      composition.record_source_health_events?
    )
    |> Keyword.put_new(:source_health_freshness, composition.source_health_freshness)
    |> Keyword.put_new(:source_watermark_events?, composition.source_watermark_events?)
    |> put_telemetry_read_policies(composition)
  end

  defp put_telemetry_read_policies(opts, %__MODULE__{} = composition) do
    source_opts = normalize_source_opts(Keyword.get(opts, :source_opts, %{}))
    telemetry_opts = normalize_adapter_opts(Map.get(source_opts, :telemetry, []))

    telemetry_opts =
      telemetry_opts
      |> Keyword.put_new(
        :current_value_store_policy,
        composition.telemetry_current_value_store_policy
      )
      |> Keyword.put_new(:history_store_policy, composition.telemetry_history_store_policy)

    Keyword.put(opts, :source_opts, Map.put(source_opts, :telemetry, telemetry_opts))
  end

  defp normalize_source_opts(source_opts) when is_map(source_opts), do: source_opts
  defp normalize_source_opts(_source_opts), do: %{}

  defp normalize_adapter_opts(adapter_opts) when is_list(adapter_opts), do: adapter_opts
  defp normalize_adapter_opts(_adapter_opts), do: []

  defp maybe_put_new(opts, _key, nil), do: opts
  defp maybe_put_new(opts, key, value), do: Keyword.put_new(opts, key, value)
end
