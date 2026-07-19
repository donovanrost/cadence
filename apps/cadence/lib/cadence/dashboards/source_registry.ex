defmodule Cadence.Dashboards.SourceRegistry do
  @moduledoc """
  Dispatches planned dashboard source requests to logical source adapters.

  This is intentionally small until source bindings and data-source registry
  records exist. The engine depends on this dispatcher, not concrete adapters.
  """

  alias Cadence.Dashboards.{
    DashboardContract,
    DataBindingInterval,
    DataContext,
    DataLink,
    DataLinks,
    DataSourceRegistry,
    DataSources,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolvedSourceCredential,
    ResolveWarning,
    RuntimeCacheKey,
    ScopeContext,
    SourceActions,
    SourceCapabilities,
    SourceCircuitBreaker,
    SourceCredentialMaterial,
    SourceCredentials,
    SourceExecutionPolicy,
    SourceFacts,
    SourceHealth,
    SourceHealthEvent,
    SourceHealthStatus,
    SourceResult,
    SourceWatermark,
    SourceWatermarks,
    SourceWatermarkStatus
  }

  alias Cadence.Dashboards.SourceRegistry.{
    CapabilityPosture,
    FactsAggregation,
    SegmentResultMerge
  }

  alias Cadence.Dashboards.Sources.{Events, Limits, OperationalObservables, Telemetry}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.EffectiveInterval

  @type adapter :: module()
  @type adapter_map :: %{optional(atom()) => adapter()}
  @type capability_context :: %{
          capabilities: SourceCapabilities.t(),
          provenance: map()
        }

  @default_adapters %{
    telemetry: Telemetry,
    limits: Limits,
    events: Events,
    operational_observables: OperationalObservables
  }

  @spec capability_fingerprint(keyword()) :: binary()
  def capability_fingerprint(opts \\ []) when is_list(opts) do
    "source-capabilities:" <>
      RuntimeCacheKey.fingerprint(%{
        logical_capabilities: logical_capabilities(opts),
        registry_data: registry_data_for_fingerprint(opts)
      })
  end

  @spec capabilities(atom() | PlannedSourceRequest.t(), keyword()) ::
          SourceCapabilities.t()
          | nil
          | {:ok, SourceCapabilities.t()}
          | {:error, ResolveWarning.t()}
  def capabilities(logical_source_or_request, opts \\ [])

  def capabilities(logical_source, opts) when is_atom(logical_source) and is_list(opts) do
    with {:ok, adapter} <- adapter_for_logical_source(logical_source, opts),
         {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :capabilities, 0) do
      adapter.capabilities()
      |> SourceCapabilities.normalize()
      |> validate_source_capabilities_contract!(opts)
    else
      _other -> nil
    end
  end

  def capabilities(%PlannedSourceRequest{} = request, opts) when is_list(opts) do
    request = validate_planned_source_request_contract!(request, opts)

    with {:ok, %{capabilities: %SourceCapabilities{} = capabilities}} <-
           capability_context(request, opts) do
      {:ok, capabilities}
    end
  end

  @spec capability_context(PlannedSourceRequest.t(), keyword()) ::
          {:ok, capability_context()} | {:error, ResolveWarning.t()}
  def capability_context(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    request = validate_planned_source_request_contract!(request, opts)

    if segmentable_source_request?(request, opts) do
      segmented_capability_context(request, opts)
    else
      single_capability_context(request, opts)
    end
  end

  defp single_capability_context(%PlannedSourceRequest{} = request, opts) do
    with {:ok, resolved_binding} <- DataSourceRegistry.resolve(request, opts) do
      resolved_binding_capability_context(request, resolved_binding, opts)
    end
  end

  defp segmented_capability_context(%PlannedSourceRequest{} = request, opts) do
    with {:ok, resolved_bindings} <- DataSourceRegistry.resolve_segments(request, opts),
         {:ok, segment_contexts} <-
           resolved_bindings_capability_contexts(request, resolved_bindings, opts) do
      [first_context | _rest] = segment_contexts
      capabilities = merge_segment_capabilities(Enum.map(segment_contexts, & &1.capabilities))
      adapter = first_context.adapter

      {:ok,
       %{
         capabilities: capabilities,
         provenance:
           segmented_capability_provenance(request, resolved_bindings, adapter, capabilities)
       }}
    end
  end

  defp resolved_bindings_capability_contexts(%PlannedSourceRequest{} = request, bindings, opts) do
    bindings
    |> Enum.reduce_while({:ok, []}, fn resolved_binding, {:ok, contexts} ->
      case resolved_binding_capability_context(request, resolved_binding, opts) do
        {:ok, context} -> {:cont, {:ok, contexts ++ [context]}}
        {:error, warning} -> {:halt, {:error, warning}}
      end
    end)
  end

  defp resolved_binding_capability_context(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    with {:ok, adapter} <- adapter_for(resolved_binding, opts),
         {:ok, adapter_capabilities} <- adapter_capabilities(adapter, request, opts) do
      capabilities =
        SourceCapabilities.with_data_source_capabilities(
          adapter_capabilities,
          resolved_binding.data_source
        )
        |> SourceCapabilities.normalize()
        |> validate_source_capabilities_contract!(opts)

      {:ok,
       %{
         adapter: adapter,
         capabilities: capabilities,
         provenance: capability_provenance(request, resolved_binding, adapter, capabilities)
       }}
    else
      {:error, %ResolveWarning{} = warning} -> {:error, warning}
      :error -> {:error, unsupported_adapter_warning(request)}
    end
  end

  defp capability_provenance(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         adapter,
         %SourceCapabilities{} = capabilities
       ) do
    binding = resolved_binding.binding
    data_source = resolved_binding.data_source

    provenance =
      %{
        logical_source: request.logical_source,
        binding_id: Map.get(binding, :binding_id),
        data_source_id: Map.get(data_source, :data_source_id),
        realm: resolved_binding.realm,
        dataset: resolved_binding.dataset,
        source_binding_version: Map.get(binding, :binding_version),
        source_binding_event_id: Map.get(binding, :current_event_id),
        source_binding_interval: source_binding_interval_metadata(resolved_binding),
        source_selection: non_empty_source_selection(resolved_binding),
        adapter: adapter,
        supported_sampling: capabilities.supported_sampling,
        supported_products: capabilities.supported_products,
        supported_time_axes: capabilities.supported_time_axes,
        supported_value_types: capabilities.supported_value_types,
        supported_shapes: capabilities.supported_shapes,
        supports_watermarks?: capabilities.supports_watermarks?,
        completeness: capabilities.completeness,
        capability_posture: CapabilityPosture.build(request, capabilities),
        data_source_capabilities:
          get_in(capabilities.metadata, [:data_source_capabilities]) || %{}
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.put(
      provenance,
      :capability_fingerprint,
      "source-capability:" <> RuntimeCacheKey.fingerprint(provenance)
    )
  end

  defp segmented_capability_provenance(
         %PlannedSourceRequest{} = request,
         resolved_bindings,
         adapter,
         %SourceCapabilities{} = capabilities
       ) do
    segments = Enum.map(resolved_bindings, &source_binding_segment_metadata/1)

    provenance =
      %{
        logical_source: request.logical_source,
        segmented_source_bindings?: true,
        source_binding_segment_count: length(segments),
        source_binding_segments: segments,
        source_selections:
          resolved_bindings
          |> Enum.map(&non_empty_source_selection/1)
          |> Enum.reject(&is_nil/1),
        adapter: adapter,
        supported_sampling: capabilities.supported_sampling,
        supported_products: capabilities.supported_products,
        supported_time_axes: capabilities.supported_time_axes,
        supported_value_types: capabilities.supported_value_types,
        supported_shapes: capabilities.supported_shapes,
        supports_watermarks?: capabilities.supports_watermarks?,
        completeness: capabilities.completeness,
        capability_posture: CapabilityPosture.build(request, capabilities),
        segment_data_source_capabilities:
          get_in(capabilities.metadata, [:segment_data_source_capabilities]) || []
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
      |> Map.new()

    Map.put(
      provenance,
      :capability_fingerprint,
      "source-capability:" <> RuntimeCacheKey.fingerprint(provenance)
    )
  end

  defp logical_capabilities(opts) do
    opts
    |> logical_sources_for_fingerprint()
    |> Map.new(fn logical_source ->
      {logical_source, capabilities(logical_source, opts)}
    end)
  end

  defp logical_sources_for_fingerprint(opts) do
    adapter_sources =
      opts
      |> Keyword.get(:adapters, %{})
      |> Map.keys()

    binding_sources =
      opts
      |> Keyword.get(:data_bindings, default_data_bindings_for_fingerprint())
      |> Enum.map(&Map.get(&1, :logical_source))
      |> Enum.reject(&is_nil/1)

    @default_adapters
    |> Map.keys()
    |> Kernel.++(adapter_sources)
    |> Kernel.++(binding_sources)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp registry_data_for_fingerprint(opts) do
    %{
      data_sources: Keyword.get(opts, :data_sources, default_data_sources_for_fingerprint()),
      data_bindings: Keyword.get(opts, :data_bindings, default_data_bindings_for_fingerprint()),
      adapters: Keyword.get(opts, :adapters, %{})
    }
  end

  defp default_data_sources_for_fingerprint do
    [
      DataSources.default_managed_data_source(),
      DataSources.default_limits_data_source(),
      DataSources.default_operational_observables_data_source(),
      DataSources.default_events_data_source()
    ]
  end

  defp default_data_bindings_for_fingerprint do
    [
      DataSources.default_flight_telemetry_binding(),
      DataSources.default_flight_limits_binding(),
      DataSources.default_flight_operational_observables_binding(),
      DataSources.default_flight_events_binding()
    ]
  end

  @spec resolve(PlannedSourceRequest.t(), keyword()) :: SourceResult.t()
  def resolve(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    request = validate_planned_source_request_contract!(request, opts)

    if segmentable_source_request?(request, opts) do
      resolve_segmented_or_single_source(request, opts)
    else
      resolve_single_source(request, opts)
    end
  end

  defp resolve_single_source(%PlannedSourceRequest{} = request, opts) do
    case DataSourceRegistry.resolve(request, opts) do
      {:ok, resolved_binding} -> resolve_bound_source(request, resolved_binding, opts)
      {:error, warning} -> source_error(request, warning)
    end
  end

  defp resolve_segmented_or_single_source(%PlannedSourceRequest{} = request, opts) do
    case DataSourceRegistry.resolve_segments(request, opts) do
      {:ok, [resolved_binding]} ->
        resolve_bound_source(request, resolved_binding, opts)

      {:ok, resolved_bindings} ->
        resolve_segmented_source(request, resolved_bindings, opts)

      {:error, warning} ->
        source_error(request, warning)
    end
  end

  @spec unavailable(PlannedSourceRequest.t(), term(), keyword()) :: SourceResult.t()
  def unavailable(%PlannedSourceRequest{} = request, reason, opts \\ []) when is_list(opts) do
    request = validate_planned_source_request_contract!(request, opts)

    case DataSourceRegistry.resolve(request, opts) do
      {:ok, resolved_binding} ->
        source_policy = SourceExecutionPolicy.resolve(request, resolved_binding, opts)
        source_key = SourceCircuitBreaker.source_key(request, resolved_binding)
        result = source_unavailable(request, resolved_binding, reason)

        record_source_circuit_result(
          request,
          resolved_binding,
          source_key,
          result,
          source_policy,
          opts
        )

        result

      {:error, warning} ->
        source_error(request, warning)
    end
  end

  @spec facts(PlannedSourceRequest.t(), keyword()) ::
          {:ok, SourceFacts.t()} | {:error, ResolveWarning.t()}
  def facts(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    request = validate_planned_source_request_contract!(request, opts)

    if segmentable_source_request?(request, opts) do
      segmented_or_single_facts(request, opts)
    else
      single_facts(request, opts)
    end
  end

  defp single_facts(%PlannedSourceRequest{} = request, opts) do
    with {:ok, resolved_binding} <- DataSourceRegistry.resolve(request, opts) do
      facts_for_resolved_binding(request, resolved_binding, opts)
    end
  end

  defp segmented_or_single_facts(%PlannedSourceRequest{} = request, opts) do
    case DataSourceRegistry.resolve_segments(request, opts) do
      {:ok, [resolved_binding]} ->
        segment_request = source_binding_segment_request(request, resolved_binding)
        facts_for_resolved_binding(segment_request, resolved_binding, opts)

      {:ok, resolved_bindings} ->
        segmented_facts(request, resolved_bindings, opts)

      {:error, %ResolveWarning{} = warning} ->
        {:error, warning}
    end
  end

  defp segmented_facts(%PlannedSourceRequest{} = request, resolved_bindings, opts) do
    resolved_bindings
    |> Enum.reduce_while({:ok, []}, fn resolved_binding, {:ok, segment_facts} ->
      segment_request = source_binding_segment_request(request, resolved_binding)

      case facts_for_resolved_binding(segment_request, resolved_binding, opts) do
        {:ok, %SourceFacts{} = facts} ->
          {:cont, {:ok, segment_facts ++ [{resolved_binding, facts}]}}

        {:error, %ResolveWarning{} = warning} ->
          {:halt, {:error, warning}}
      end
    end)
    |> case do
      {:ok, segment_facts} ->
        {:ok, FactsAggregation.merge(request, segment_facts, &source_binding_segment_metadata/1)}

      {:error, warning} ->
        {:error, warning}
    end
  end

  defp facts_for_resolved_binding(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    with {:ok, adapter} <- adapter_for(resolved_binding, opts),
         {:ok, facts} <- adapter_facts(adapter, request, resolved_binding, opts),
         {:ok, %{provenance: capability_provenance}} <-
           resolved_binding_capability_context(request, resolved_binding, opts) do
      {:ok,
       facts
       |> merge_persisted_source_watermark(request, resolved_binding, opts)
       |> merge_persisted_source_health(request, resolved_binding, opts)
       |> put_source_facts_provenance(resolved_binding, capability_provenance)
       |> validate_source_facts_contract!(opts)}
    else
      {:error, %ResolveWarning{} = warning} -> {:error, warning}
      :error -> {:error, unsupported_adapter_warning(request)}
    end
  end

  @spec execution_policy(PlannedSourceRequest.t(), keyword()) :: SourceExecutionPolicy.t()
  def execution_policy(%PlannedSourceRequest{} = request, opts \\ []) when is_list(opts) do
    case DataSourceRegistry.resolve(request, opts) do
      {:ok, resolved_binding} -> SourceExecutionPolicy.resolve(request, resolved_binding, opts)
      {:error, _warning} -> SourceExecutionPolicy.resolve(opts)
    end
  end

  defp adapter_for_logical_source(logical_source, opts) do
    adapters = Keyword.get(opts, :adapters, %{})

    case Map.fetch(adapters, logical_source) do
      {:ok, adapter} when is_atom(adapter) -> {:ok, adapter}
      :error -> Map.fetch(@default_adapters, logical_source)
    end
  end

  defp validate_planned_source_request_contract!(%PlannedSourceRequest{} = request, opts) do
    request = PlannedSourceRequest.normalize(request)

    if validate_dashboard_contract?(opts) do
      request
      |> DashboardContract.validate_planned_source_request()
      |> raise_contract_violations!(:planned_source_request)
    end

    request
  end

  defp validate_source_capabilities_contract!(%SourceCapabilities{} = capabilities, opts) do
    capabilities = SourceCapabilities.normalize(capabilities)

    if validate_dashboard_contract?(opts) do
      capabilities
      |> DashboardContract.validate_source_capabilities()
      |> raise_contract_violations!(:source_capabilities)
    end

    capabilities
  end

  defp validate_source_capabilities_contract!(other, opts) do
    if validate_dashboard_contract?(opts) do
      other
      |> DashboardContract.validate_source_capabilities()
      |> raise_contract_violations!(:source_capabilities)
    end

    other
  end

  defp validate_source_facts_contract!(%SourceFacts{} = facts, opts) do
    facts = SourceFacts.normalize(facts)

    if validate_dashboard_contract?(opts) do
      facts
      |> DashboardContract.validate_source_facts()
      |> raise_contract_violations!(:source_facts)
    end

    facts
  end

  defp validate_source_result_contract!(%SourceResult{} = result, opts) do
    result = SourceResult.normalize(result)

    if validate_dashboard_contract?(opts) do
      result
      |> DashboardContract.validate_source_result()
      |> raise_contract_violations!(:source_result)
    end

    result
  end

  defp validate_dashboard_contract?(opts),
    do: Keyword.get(opts, :validate_dashboard_contract?, false) == true

  defp raise_contract_violations!(:ok, _boundary), do: :ok

  defp raise_contract_violations!({:error, violations}, boundary) do
    raise ArgumentError,
          "dashboard #{boundary} contract violated: " <> format_contract_violations(violations)
  end

  defp format_contract_violations(violations) do
    violations
    |> Enum.map_join("; ", fn violation ->
      path =
        violation
        |> Map.get(:path, [])
        |> Enum.map_join(".", &to_string/1)

      "#{path}: #{Map.get(violation, :code)}"
    end)
  end

  defp adapter_capabilities(adapter, %PlannedSourceRequest{} = request, opts) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :capabilities, 0) do
      case SourceCapabilities.normalize(adapter.capabilities()) do
        %SourceCapabilities{} = capabilities ->
          {:ok, validate_source_capabilities_contract!(capabilities, opts)}

        _other ->
          {:error, unsupported_adapter_warning(request)}
      end
    else
      _other -> {:error, unsupported_adapter_warning(request)}
    end
  end

  defp adapter_facts(adapter, %PlannedSourceRequest{} = request, resolved_binding, opts) do
    with {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :facts, 2),
         {:ok, adapter_opts} <- adapter_opts(request, resolved_binding, opts) do
      request
      |> adapter.facts(adapter_opts)
      |> normalize_adapter_facts_result(request, resolved_binding, opts)
    else
      {:error, reason} -> {:error, source_unavailable_warning(request, resolved_binding, reason)}
      _other -> {:error, unsupported_adapter_warning(request, resolved_binding)}
    end
  end

  defp normalize_adapter_facts_result({:ok, facts}, request, resolved_binding, opts) do
    case SourceFacts.normalize(facts) do
      %SourceFacts{} = normalized_facts ->
        {:ok, validate_source_facts_contract!(normalized_facts, opts)}

      _other ->
        {:error, unsupported_adapter_warning(request, resolved_binding)}
    end
  end

  defp normalize_adapter_facts_result(
         {:error, %ResolveWarning{} = warning},
         _request,
         _binding,
         _opts
       ),
       do: {:error, warning}

  defp normalize_adapter_facts_result(_other, request, resolved_binding, _opts),
    do: {:error, unsupported_adapter_warning(request, resolved_binding)}

  defp merge_persisted_source_health(
         %SourceFacts{} = facts,
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    if SourceHealth.enabled?(opts) do
      case fetch_source_health_status(request, resolved_binding, opts) do
        {:ok, status} ->
          classification =
            SourceHealth.classify_status(status, resolved_binding.data_source, opts)

          interval = source_health_interval(request, resolved_binding, status, opts)

          merge_source_health_classification(facts, classification, interval)

        {:error, :source_health_status_not_found} ->
          classification =
            SourceHealth.classify_status(nil, resolved_binding.data_source, opts)

          merge_source_health_classification(facts, classification, nil)
      end
    else
      facts
    end
  end

  defp merge_source_health_classification(%SourceFacts{} = facts, classification, interval) do
    meta =
      facts.meta
      |> source_health_classification_meta(classification, interval)

    facts =
      SourceFacts.new(%{
        facts
        | source_health: classification.source_health,
          meta: meta,
          watermark: put_source_health_meta(facts.watermark, meta),
          watermarks: Enum.map(facts.watermarks, &put_source_health_meta(&1, meta))
      })

    facts
  end

  defp source_health_classification_meta(meta, classification, interval) do
    status = Map.get(classification, :status)

    meta
    |> ensure_map()
    |> Map.put(:source_health, classification.source_health)
    |> Map.put(:source_health_freshness, classification.freshness)
    |> Map.put(:source_health_reason, classification.reason)
    |> Map.put(:source_health_observed_at, classification.observed_at)
    |> Map.put(:source_health_last_seen_at, classification.last_seen_at)
    |> Map.put(:source_health_age_ms, classification.age_ms)
    |> Map.put(:source_health_max_age_ms, classification.max_age_ms)
    |> Map.put(:source_health_raw_source_health, classification.raw_source_health)
    |> Map.put(:source_health_raw_reason, classification.raw_reason)
    |> maybe_put(:source_health_probe_kind, source_health_payload_value(status, :probe_kind))
    |> maybe_put(
      :source_health_probe_message,
      source_health_payload_value(status, :probe_message)
    )
    |> maybe_put(
      :source_health_probe_metadata,
      source_health_payload_value(status, :probe_metadata)
    )
    |> maybe_put(
      :source_health_connection_test_result,
      source_health_payload_value(status, :connection_test_result)
    )
    |> maybe_put(
      :source_health_connection_test_kind,
      source_health_payload_value(status, :connection_test_kind)
    )
    |> maybe_put(
      :source_health_connection_test_message,
      source_health_payload_value(status, :connection_test_message)
    )
    |> maybe_put(:durable_source_health?, not is_nil(status))
    |> maybe_put(:source_health_event_id, status && status.source_health_event_id)
    |> put_source_health_interval_meta(interval)
  end

  defp put_source_health_interval_meta(meta, %EffectiveInterval{} = interval) do
    interval_metadata = EffectiveInterval.metadata(interval)

    meta
    |> Map.put(:source_health_interval_id, interval.interval_id)
    |> Map.put(:source_health_interval_source_event_id, interval.source_event_id)
    |> Map.put(:source_health_interval, interval_metadata)
  end

  defp put_source_health_interval_meta(meta, _interval), do: meta

  defp source_health_payload_value(%{payload: payload}, key) when is_map(payload) do
    Map.get(payload, Atom.to_string(key), Map.get(payload, key))
  end

  defp source_health_payload_value(_status, _key), do: nil

  defp put_source_health_meta(nil, _meta), do: nil

  defp put_source_health_meta(%SourceWatermark{} = watermark, meta) when is_map(meta) do
    %SourceWatermark{
      watermark
      | meta:
          watermark.meta
          |> ensure_map()
          |> maybe_put(:source_health_event_id, Map.get(meta, :source_health_event_id))
          |> maybe_put(:source_health_reason, Map.get(meta, :source_health_reason))
          |> maybe_put(:source_health_probe_kind, Map.get(meta, :source_health_probe_kind))
          |> maybe_put(:source_health_probe_message, Map.get(meta, :source_health_probe_message))
          |> maybe_put(
            :source_health_probe_metadata,
            Map.get(meta, :source_health_probe_metadata)
          )
          |> maybe_put(
            :source_health_connection_test_result,
            Map.get(meta, :source_health_connection_test_result)
          )
          |> maybe_put(
            :source_health_connection_test_kind,
            Map.get(meta, :source_health_connection_test_kind)
          )
          |> maybe_put(
            :source_health_connection_test_message,
            Map.get(meta, :source_health_connection_test_message)
          )
    }
  end

  defp put_source_health_meta(watermark, _meta), do: watermark

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp merge_persisted_source_watermark(
         %SourceFacts{} = facts,
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    if SourceWatermarks.enabled?(opts) do
      case SourceWatermarks.fetch_status_for_source(request, resolved_binding) do
        {:ok, status} ->
          watermark =
            SourceWatermarkStatus.to_source_watermark(status,
              request_id: request.request_id,
              scope: request.scope_context
            )

          meta =
            facts.meta
            |> Map.put(:durable_source_watermark?, true)
            |> Map.put(:source_watermark_event_id, status.source_watermark_event_id)
            |> Map.put(:source_watermark_observed_at, status.observed_at)
            |> Map.put(:source_watermark_last_seen_at, status.last_seen_at)
            |> Map.put(:source_watermark_reason, status.reason)

          SourceFacts.new(%{facts | watermark: watermark, watermarks: [watermark], meta: meta})

        {:error, :source_watermark_status_not_found} ->
          facts
      end
    else
      facts
    end
  end

  defp merge_segment_capabilities([%SourceCapabilities{} = first | _rest] = capabilities) do
    SourceCapabilities.new(%{
      first
      | supported_sampling: intersect_capability_values(capabilities, :supported_sampling),
        supported_products: intersect_capability_values(capabilities, :supported_products),
        supported_time_axes: intersect_capability_values(capabilities, :supported_time_axes),
        supported_value_types: intersect_capability_values(capabilities, :supported_value_types),
        supported_shapes: intersect_capability_values(capabilities, :supported_shapes),
        supports_watermarks?: Enum.all?(capabilities, & &1.supports_watermarks?),
        completeness: aggregate_capability_completeness(capabilities),
        metadata:
          first.metadata
          |> Map.put(
            :segment_data_source_capabilities,
            Enum.map(capabilities, &get_in(&1.metadata, [:data_source_capabilities]))
          )
    })
  end

  defp intersect_capability_values([%SourceCapabilities{} = first | rest], key) do
    Enum.reduce(rest, Map.fetch!(first, key), fn capabilities, acc ->
      Enum.filter(acc, &(&1 in Map.fetch!(capabilities, key)))
    end)
  end

  defp aggregate_capability_completeness(capabilities) do
    completeness = Enum.map(capabilities, & &1.completeness)

    cond do
      :unknown in completeness -> :unknown
      :partial in completeness -> :partial
      true -> :known
    end
  end

  defp adapter_for(resolved_binding, opts) do
    adapters = Keyword.get(opts, :adapters, %{})
    logical_source = resolved_binding.binding.logical_source

    case Map.fetch(adapters, logical_source) do
      {:ok, adapter} ->
        {:ok, adapter}

      :error ->
        case resolved_binding.data_source.adapter do
          adapter when is_atom(adapter) and not is_nil(adapter) -> {:ok, adapter}
          _other -> :error
        end
    end
  end

  defp adapter_opts(%PlannedSourceRequest{} = request, resolved_binding, opts) do
    source_opts = Keyword.get(opts, :source_opts, %{})

    adapter_opts =
      case Map.get(source_opts, request.logical_source, []) do
        opts when is_list(opts) -> opts
        _other -> []
      end

    adapter_opts
    |> maybe_put_adapter_opt(:freshness_policy, Keyword.get(opts, :freshness_policy))
    |> maybe_put_adapter_opt(:freshness_now, Keyword.get(opts, :freshness_now))
    |> maybe_put_adapter_opt(:persisted?, Keyword.get(opts, :persisted?))
    |> put_source_capability_opts(request, resolved_binding, opts)
    |> Keyword.put(:source_binding, resolved_binding)
    |> put_source_connection_opts(resolved_binding, opts)
  end

  defp put_source_capability_opts(
         adapter_opts,
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    case resolved_binding_capability_context(request, resolved_binding, opts) do
      {:ok, %{capabilities: %SourceCapabilities{} = capabilities}} ->
        adapter_opts
        |> maybe_put_adapter_opt(:source_capabilities, capabilities)
        |> maybe_put_adapter_opt(:supported_time_axes, capabilities.supported_time_axes)

      _other ->
        adapter_opts
    end
  end

  defp maybe_put_adapter_opt(opts, _key, nil), do: opts
  defp maybe_put_adapter_opt(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp put_source_connection_opts(adapter_opts, resolved_binding, opts) do
    data_source = resolved_binding.data_source

    case Map.get(data_source, :credentials_ref) do
      credentials_ref when is_binary(credentials_ref) and credentials_ref != "" ->
        with {:ok, credential} <- resolve_source_credential(data_source, opts) do
          {:ok, merge_source_connection_opts(adapter_opts, data_source, credential)}
        end

      _other ->
        {:ok, adapter_opts}
    end
  end

  defp resolve_source_credential(data_source, opts) do
    resolver_opts = credential_resolver_opts(data_source, opts)

    if credential_material_resolver_configured?(opts) do
      SourceCredentials.resolve_material(data_source.credentials_ref, resolver_opts)
    else
      SourceCredentials.resolve(data_source.credentials_ref, resolver_opts)
    end
  end

  defp credential_resolver_opts(data_source, opts) do
    opts
    |> Keyword.take([
      :credential_material_resolver,
      :credential_material_authorizer,
      :credential_secret_backend,
      :secret_backend,
      :env_material_profiles,
      :env_reader
    ])
    |> Keyword.merge(
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      data_source_id: data_source.data_source_id
    )
  end

  defp credential_material_resolver_configured?(opts) do
    configured = Application.get_env(:cadence, :dashboard_source_credentials, [])

    Keyword.has_key?(opts, :credential_material_resolver) ||
      Keyword.has_key?(opts, :credential_secret_backend) ||
      Keyword.has_key?(opts, :secret_backend) ||
      Keyword.has_key?(configured, :material_resolver) ||
      Keyword.has_key?(configured, :secret_backend)
  end

  defp merge_source_connection_opts(
         adapter_opts,
         data_source,
         %ResolvedSourceCredential{} = credential
       ) do
    profile = ResolvedSourceCredential.connection_profile(credential, data_source)

    adapter_opts
    |> Keyword.put(:source_connection_profile, profile)
    |> put_public_connection_opts(profile)
  end

  defp merge_source_connection_opts(
         adapter_opts,
         data_source,
         %SourceCredentialMaterial{} = credential_material
       ) do
    profile =
      SourceCredentialMaterial.redacted_connection_profile(credential_material, data_source)

    material = SourceCredentialMaterial.adapter_options(credential_material)

    adapter_opts
    |> Keyword.put(:source_connection_profile, profile)
    |> Keyword.put(:source_connection_material, material)
    |> put_public_connection_opts(profile)
    |> put_secret_connection_opts(material)
  end

  defp put_public_connection_opts(opts, %{http_endpoint: http_endpoint})
       when is_binary(http_endpoint) do
    Keyword.put_new(opts, :http_endpoint, http_endpoint)
  end

  defp put_public_connection_opts(opts, _profile), do: opts

  defp put_secret_connection_opts(opts, material) when is_list(material) do
    opts
    |> maybe_put_adapter_opt(:http_endpoint, Keyword.get(material, :http_endpoint))
    |> maybe_put_adapter_opt(:headers, connection_headers(material))
  end

  defp connection_headers(material) when is_list(material) do
    headers = material |> Keyword.get(:headers, []) |> normalize_headers()

    cond do
      bearer_token = Keyword.get(material, :bearer_token) ->
        [{"authorization", "Bearer #{bearer_token}"} | headers]

      username = Keyword.get(material, :username) ->
        case Keyword.get(material, :password) do
          password when is_binary(password) ->
            [{"authorization", "Basic #{Base.encode64("#{username}:#{password}")}"} | headers]

          _other ->
            headers
        end

      true ->
        headers
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {key, value} -> [{to_string(key), to_string(value)}]
      _other -> []
    end)
  end

  defp normalize_headers(_headers), do: []

  defp source_error(%PlannedSourceRequest{} = request, %ResolveWarning{} = warning) do
    SourceResult.new(%{
      request_id: request.request_id,
      warnings: [warning],
      meta: %{
        logical_source: request.logical_source,
        returned_frame_count: 0,
        degraded?: true
      }
    })
  end

  defp unsupported_adapter(%PlannedSourceRequest{} = request, resolved_binding) do
    source_error(
      request,
      unsupported_adapter_warning(request, resolved_binding)
    )
  end

  defp unsupported_adapter_warning(%PlannedSourceRequest{} = request) do
    %ResolveWarning{
      code: :unsupported_source_adapter,
      severity: :error,
      scope: :dashboard,
      message: "Source binding resolved to a data source without a dashboard adapter",
      details:
        %{
          source_request_id: request.request_id,
          logical_source: request.logical_source
        }
        |> SourceActions.put_source_request_context(request)
        |> SourceActions.put_source_warning_actions(),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp unsupported_adapter_warning(%PlannedSourceRequest{} = request, resolved_binding) do
    %ResolveWarning{
      code: :unsupported_source_adapter,
      severity: :error,
      scope: :dashboard,
      message: "Source binding resolved to a data source without a dashboard adapter",
      details: source_details(request, resolved_binding),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp segmentable_source_request?(%PlannedSourceRequest{} = request, opts) do
    not is_nil(source_binding_range(opts)) and request.logical_source == :telemetry and
      sampling_mode(request) in [:raw_series, :bounded_history, :bounded_raw_series]
  end

  defp resolve_segmented_source(
         %PlannedSourceRequest{} = request,
         resolved_bindings,
         opts
       ) do
    segment_results =
      Enum.map(resolved_bindings, fn resolved_binding ->
        segment_request = source_binding_segment_request(request, resolved_binding)
        {resolved_binding, resolve_bound_source(segment_request, resolved_binding, opts)}
      end)

    case SegmentResultMerge.merge(
           request,
           segment_results,
           &source_binding_segment_metadata/1
         ) do
      {:ok, %SourceResult{} = result} ->
        result

      {:error, warning} ->
        source_error(request, warning)
    end
  end

  defp source_binding_segment_request(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       ) do
    %PlannedSourceRequest{
      request
      | time_context:
          put_time_context_bounds(
            request.time_context,
            resolved_binding.segment_from,
            resolved_binding.segment_to
          ),
        metadata:
          request.metadata
          |> ensure_map()
          |> Map.put(:source_binding_segment, source_binding_segment_metadata(resolved_binding))
    }
  end

  defp put_time_context_bounds(time_context, %DateTime{} = from, %DateTime{} = to)
       when is_map(time_context) do
    time_context
    |> Map.put(:from, from)
    |> Map.put(:to, to)
    |> Map.put(:start, from)
    |> Map.put(:end, to)
    |> Map.put(:start_time, from)
    |> Map.put(:end_time, to)
  end

  defp put_time_context_bounds(time_context, _from, _to), do: time_context

  defp resolve_bound_source(%PlannedSourceRequest{} = request, resolved_binding, opts) do
    source_policy = SourceExecutionPolicy.resolve(request, resolved_binding, opts)
    source_key = SourceCircuitBreaker.source_key(request, resolved_binding)

    case source_circuit_allow(source_key, source_policy, opts) do
      {:blocked, status} ->
        result = source_degraded(request, resolved_binding, status, opts)

        record_source_health_result(
          request,
          resolved_binding,
          result,
          :source_degraded,
          status,
          opts
        )

        merge_persisted_source_result_health(result, request, resolved_binding, opts)

      {:allow, _status} ->
        result = execute_adapter(request, resolved_binding, opts)

        record_source_circuit_result(
          request,
          resolved_binding,
          source_key,
          result,
          source_policy,
          opts
        )

        merge_persisted_source_result_health(result, request, resolved_binding, opts)
    end
  end

  defp execute_adapter(%PlannedSourceRequest{} = request, resolved_binding, opts) do
    case adapter_for(resolved_binding, opts) do
      {:ok, adapter} ->
        adapter
        |> execute_adapter_result(request, resolved_binding, opts)
        |> validate_source_result_contract!(opts)

      :error ->
        unsupported_adapter(request, resolved_binding)
    end
  end

  defp execute_adapter_result(adapter, %PlannedSourceRequest{} = request, resolved_binding, opts) do
    case adapter_opts(request, resolved_binding, opts) do
      {:ok, adapter_opts} ->
        request
        |> adapter.resolve(adapter_opts)
        |> SourceResult.normalize()
        |> merge_persisted_source_result_watermark(request, resolved_binding, opts)
        |> put_source_result_provenance(resolved_binding, request, opts)

      {:error, reason} ->
        source_unavailable(request, resolved_binding, reason, opts)
    end
  rescue
    exception ->
      source_unavailable(request, resolved_binding, {:exception, exception}, opts)
  catch
    kind, reason ->
      source_unavailable(request, resolved_binding, {kind, reason}, opts)
  end

  defp source_circuit_allow(source_key, %SourceExecutionPolicy{} = source_policy, opts) do
    case source_circuit_breaker(opts) do
      {:ok, server} ->
        SourceCircuitBreaker.allow?(server, source_key, source_circuit_opts(opts, source_policy))

      :disabled ->
        {:allow, %{}}
    end
  end

  defp record_source_circuit_result(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         source_key,
         %SourceResult{} = result,
         %SourceExecutionPolicy{} = source_policy,
         opts
       ) do
    failure_reason = source_failure_reason(result)

    circuit_status =
      case source_circuit_breaker(opts) do
        {:ok, server} ->
          case failure_reason do
            nil ->
              SourceCircuitBreaker.record_success(
                server,
                source_key,
                source_circuit_opts(opts, source_policy)
              )

              nil

            reason ->
              SourceCircuitBreaker.record_failure(
                server,
                source_key,
                reason,
                source_circuit_opts(opts, source_policy)
              )
          end

        :disabled ->
          nil
      end

    record_source_health_result(
      request,
      resolved_binding,
      result,
      failure_reason,
      circuit_status,
      opts
    )

    :ok
  end

  defp source_circuit_breaker(opts) do
    cond do
      Keyword.get(opts, :source_circuit_breaker?) == false ->
        :disabled

      server = Keyword.get(opts, :source_circuit_breaker) ->
        {:ok, server}

      dashboard_source_circuit_breaker_enabled?() and Process.whereis(SourceCircuitBreaker) ->
        {:ok, SourceCircuitBreaker}

      true ->
        :disabled
    end
  end

  defp source_circuit_opts(opts, %SourceExecutionPolicy{} = source_policy) do
    [
      failure_threshold: source_policy.circuit_failure_threshold,
      backoff_ms: source_policy.circuit_backoff_ms,
      now_ms: Keyword.get(opts, :now_ms)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp dashboard_source_circuit_breaker_enabled? do
    :cadence
    |> Application.get_env(:dashboard_source_circuit_breaker, [])
    |> Keyword.get(:enabled?, false)
  end

  defp source_failure_reason(%SourceResult{warnings: warnings}) do
    warnings
    |> Enum.find(&(&1.severity == :error))
    |> case do
      nil -> nil
      warning -> warning.code
    end
  end

  defp record_source_health_result(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         %SourceResult{} = result,
         failure_reason,
         circuit_status,
         opts
       ) do
    if source_health_recording_enabled?(opts) do
      do_record_source_health_result(
        request,
        resolved_binding,
        result,
        failure_reason,
        circuit_status,
        opts
      )
    else
      :ok
    end
  end

  defp do_record_source_health_result(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         %SourceResult{} = result,
         failure_reason,
         circuit_status,
         opts
       ) do
    source_health =
      case failure_reason do
        nil -> :healthy
        :source_degraded -> :degraded
        :source_unavailable -> :unavailable
        _other -> :degraded
      end

    reason =
      case failure_reason do
        nil -> :source_recovered
        reason -> reason
      end

    attrs =
      request
      |> source_health_attrs(resolved_binding, source_health, reason)
      |> Map.put(:payload, source_health_payload(result, circuit_status))

    case SourceHealth.maybe_record_source_health(attrs, opts) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp source_health_recording_enabled?(opts) do
    Keyword.get(opts, :record_source_health_events?, SourceHealth.enabled?(opts))
  end

  defp source_degraded(%PlannedSourceRequest{} = request, resolved_binding, status, opts) do
    source_error(
      request,
      source_degraded_warning(request, resolved_binding, status)
    )
    |> put_source_result_provenance(resolved_binding, request, opts)
  end

  defp source_unavailable(%PlannedSourceRequest{} = request, resolved_binding, reason) do
    source_error(
      request,
      source_unavailable_warning(request, resolved_binding, reason)
    )
    |> put_source_result_provenance(resolved_binding, request, [])
  end

  defp source_unavailable(%PlannedSourceRequest{} = request, resolved_binding, reason, opts) do
    source_error(
      request,
      source_unavailable_warning(request, resolved_binding, reason)
    )
    |> put_source_result_provenance(resolved_binding, request, opts)
  end

  defp source_degraded_warning(%PlannedSourceRequest{} = request, resolved_binding, status) do
    %ResolveWarning{
      code: :source_degraded,
      severity: :error,
      scope: :dashboard,
      message: "Source circuit is open after repeated failures",
      details:
        source_details(request, resolved_binding)
        |> Map.merge(%{
          circuit_state: Map.get(status, :state),
          failure_count: Map.get(status, :failure_count),
          failure_threshold: Map.get(status, :failure_threshold),
          backoff_ms: Map.get(status, :backoff_ms),
          retry_after_ms: Map.get(status, :retry_after_ms),
          last_failure_reason: Map.get(status, :last_failure_reason)
        }),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp source_unavailable_warning(%PlannedSourceRequest{} = request, resolved_binding, reason) do
    %ResolveWarning{
      code: :source_unavailable,
      severity: :error,
      scope: :dashboard,
      message: "Source adapter failed while resolving dashboard data",
      details:
        source_details(request, resolved_binding)
        |> Map.put(:reason, inspect_source_failure(reason)),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp source_details(%PlannedSourceRequest{} = request, resolved_binding) do
    details = %{
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      binding_id: resolved_binding.binding.binding_id,
      data_source_id: resolved_binding.data_source.data_source_id,
      realm: resolved_binding.realm,
      dataset: resolved_binding.dataset
    }

    details
    |> Map.merge(source_binding_provenance(resolved_binding))
    |> SourceActions.put_source_request_context(request)
    |> SourceActions.put_source_warning_actions()
  end

  defp put_source_facts_provenance(
         %SourceFacts{} = facts,
         resolved_binding,
         capability_provenance
       ) do
    facts = SourceFacts.normalize(facts)

    SourceFacts.new(%{
      facts
      | meta:
          facts.meta
          |> ensure_map()
          |> Map.merge(source_binding_provenance(resolved_binding))
          |> maybe_put(:capability_provenance, capability_provenance)
          |> maybe_put(:capability_posture, Map.get(capability_provenance, :capability_posture))
    })
  end

  defp put_source_result_provenance(
         %SourceResult{} = result,
         resolved_binding,
         request,
         opts
       ) do
    result = SourceResult.normalize(result)

    interval_provenance =
      selected_operational_interval_provenance(request, resolved_binding, opts, result)

    provenance =
      resolved_binding
      |> source_binding_provenance()
      |> Map.merge(interval_provenance)

    link_context = source_link_context(request, resolved_binding)

    evidence =
      source_binding_evidence_refs(resolved_binding, request) ++
        operational_interval_evidence_refs(interval_provenance, request) ++
        source_status_evidence_refs(result)

    SourceResult.new(%{
      result
      | meta:
          result.meta
          |> ensure_map()
          |> Map.merge(provenance)
          |> merge_evidence_refs(evidence),
        warnings:
          Enum.map(result.warnings, fn warning ->
            put_warning_provenance(warning, resolved_binding, request)
          end),
        frames:
          Enum.map(result.frames, &put_frame_provenance(&1, provenance, link_context, evidence))
    })
  end

  defp put_warning_provenance(
         %ResolveWarning{} = warning,
         %ResolvedSourceBinding{} = resolved_binding,
         %PlannedSourceRequest{} = request
       ) do
    details =
      warning.details
      |> ensure_map()
      |> Map.merge(source_warning_provenance_details(request, resolved_binding))
      |> SourceActions.put_source_warning_actions()

    links =
      warning
      |> warning_links_or_request_links(request, resolved_binding)
      |> enrich_data_links(source_link_context(request, resolved_binding))

    %ResolveWarning{warning | details: details, links: links}
  end

  defp put_warning_provenance(warning, _resolved_binding, _request), do: warning

  defp source_warning_provenance_details(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       ) do
    %{
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      binding_id: resolved_binding.binding.binding_id,
      data_source_id: resolved_binding.data_source.data_source_id,
      realm: resolved_binding.realm,
      dataset: resolved_binding.dataset
    }
    |> Map.merge(source_binding_provenance(resolved_binding))
    |> SourceActions.put_source_request_context(request)
  end

  defp merge_persisted_source_result_watermark(
         %SourceResult{} = result,
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    if SourceWatermarks.enabled?(opts) do
      case SourceWatermarks.fetch_status_for_source(request, resolved_binding) do
        {:ok, status} ->
          watermark =
            SourceWatermarkStatus.to_source_watermark(status,
              request_id: request.request_id,
              scope: request.scope_context
            )

          meta =
            result.meta
            |> ensure_map()
            |> Map.put(:durable_source_watermark?, true)
            |> Map.put(:source_watermark_event_id, status.source_watermark_event_id)
            |> Map.put(:source_watermark_observed_at, status.observed_at)
            |> Map.put(:source_watermark_last_seen_at, status.last_seen_at)
            |> Map.put(:source_watermark_reason, status.reason)

          result
          |> clear_unknown_watermark_warnings(watermark)
          |> then(&SourceResult.new(%{&1 | watermarks: [watermark], meta: meta}))

        {:error, :source_watermark_status_not_found} ->
          result
      end
    else
      result
    end
  end

  defp clear_unknown_watermark_warnings(
         %SourceResult{} = result,
         %SourceWatermark{confidence: confidence}
       )
       when confidence in [:authoritative, :best_effort] do
    %SourceResult{
      result
      | warnings: Enum.reject(result.warnings, &watermark_unknown_warning?/1),
        frames: Enum.map(result.frames, &clear_frame_warning_code(&1, :watermark_unknown))
    }
  end

  defp clear_unknown_watermark_warnings(%SourceResult{} = result, _watermark), do: result

  defp watermark_unknown_warning?(%ResolveWarning{code: code}),
    do: normalize_warning_code(code) == :watermark_unknown

  defp watermark_unknown_warning?(warning) when is_map(warning),
    do: warning |> map_value(:code) |> normalize_warning_code() == :watermark_unknown

  defp watermark_unknown_warning?(_warning), do: false

  defp clear_frame_warning_code(%Frame{meta: meta} = frame, code) when is_map(meta) do
    warning_codes =
      meta
      |> Map.get(:warning_codes, Map.get(meta, "warning_codes", []))
      |> List.wrap()
      |> Enum.reject(&(normalize_warning_code(&1) == code))

    %Frame{frame | meta: Map.put(meta, :warning_codes, warning_codes)}
  end

  defp clear_frame_warning_code(frame, _code), do: frame

  defp normalize_warning_code(code) when is_atom(code), do: code

  defp normalize_warning_code(code) when is_binary(code) do
    code
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_warning_code(_code), do: nil

  defp map_value(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp merge_persisted_source_result_health(
         %SourceResult{} = result,
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    if SourceHealth.enabled?(opts) do
      case fetch_source_health_status(request, resolved_binding, opts) do
        {:ok, status} ->
          classification =
            SourceHealth.classify_status(status, resolved_binding.data_source, opts)

          interval = source_health_interval(request, resolved_binding, status, opts)

          meta =
            result.meta
            |> source_health_classification_meta(classification, interval)

          evidence =
            DataLinks.source_health_event_evidence_refs([status_metadata(meta)]) ++
              DataLinks.operational_interval_evidence_refs([interval],
                source: request.logical_source
              )

          SourceResult.new(%{
            result
            | meta:
                meta
                |> maybe_mark_source_health_degraded()
                |> merge_evidence_refs(evidence),
              watermarks: Enum.map(result.watermarks, &put_source_health_meta(&1, meta)),
              frames:
                Enum.map(
                  result.frames,
                  &put_frame_source_health_meta(&1, meta, evidence)
                )
          })

        {:error, :source_health_status_not_found} ->
          result
      end
    else
      result
    end
  end

  defp put_frame_source_health_meta(%Frame{} = frame, source_health_meta, evidence) do
    meta =
      frame.meta
      |> ensure_map()
      |> Map.merge(source_health_meta)
      |> maybe_mark_source_health_degraded()
      |> merge_evidence_refs(evidence)

    Frame.new(%{frame | meta: meta})
  end

  defp put_frame_source_health_meta(frame, _source_health_meta, _evidence), do: frame

  defp maybe_mark_source_health_degraded(%{source_health: source_health} = meta)
       when source_health in [:degraded, :unavailable, :unknown],
       do: Map.put(meta, :degraded?, true)

  defp maybe_mark_source_health_degraded(meta), do: meta

  defp fetch_source_health_status(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    case injected_source_health_status(request, resolved_binding, opts) do
      %SourceHealthStatus{} = status -> {:ok, status}
      nil -> SourceHealth.fetch_status_for_source(request, resolved_binding)
    end
  end

  defp injected_source_health_status(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    opts
    |> Keyword.get(:source_health_statuses, [])
    |> List.wrap()
    |> source_health_status_for(request, resolved_binding)
  end

  defp source_health_status_for([], %PlannedSourceRequest{}, _resolved_binding), do: nil

  defp source_health_status_for(
         source_health_statuses,
         %PlannedSourceRequest{} = request,
         binding
       ) do
    exact_key =
      request
      |> source_health_identity(binding)
      |> SourceHealthEvent.source_health_key()

    source_key =
      request
      |> source_health_identity(binding)
      |> Map.merge(%{source_binding_id: nil, realm: nil, replay_run_id: nil, dataset: nil})
      |> SourceHealthEvent.source_health_key()

    Enum.find(
      source_health_statuses,
      &(source_health_status_value(&1, :source_health_key) == exact_key)
    ) ||
      Enum.find(
        source_health_statuses,
        &(source_health_status_value(&1, :source_health_key) == source_key)
      )
  end

  defp source_health_identity(%PlannedSourceRequest{} = request, resolved_binding) do
    binding = resolved_binding.binding
    data_source = resolved_binding.data_source

    %{
      organization_id:
        request.organization_id || Map.get(binding, :organization_id) ||
          Map.get(data_source, :organization_id),
      mission_id:
        request.mission_id || Map.get(binding, :mission_id) || Map.get(data_source, :mission_id),
      logical_source: request.logical_source || Map.get(binding, :logical_source),
      data_source_id: Map.get(data_source, :data_source_id),
      source_binding_id: Map.get(binding, :binding_id),
      realm: Map.get(binding, :realm),
      replay_run_id: requested_replay_run_id(request),
      dataset: Map.get(binding, :dataset)
    }
  end

  defp source_health_status_value(%SourceHealthStatus{} = status, key), do: Map.get(status, key)

  defp source_health_status_value(status, key) when is_map(status),
    do: Map.get(status, key, Map.get(status, Atom.to_string(key)))

  defp source_health_status_value(_status, _key), do: nil

  defp source_health_interval(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         %SourceHealthStatus{} = status,
         opts
       ) do
    identity = source_health_identity(request, resolved_binding)

    if source_health_interval_lookup_enabled?(opts) do
      interval_opts =
        [
          at: status.last_seen_at || status.observed_at,
          logical_source: Map.get(identity, :logical_source),
          data_source_id: Map.get(identity, :data_source_id),
          source_binding_id: Map.get(identity, :source_binding_id),
          realm: Map.get(identity, :realm),
          dataset: Map.get(identity, :dataset),
          replay_run_id: Map.get(identity, :replay_run_id)
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      request.organization_id
      |> operational_intervals(:source_health, request.mission_id, interval_opts, opts)
      |> source_health_interval_for_status(status)
    end
  end

  defp source_health_interval(%PlannedSourceRequest{}, _resolved_binding, _status, _opts), do: nil

  defp source_health_interval_lookup_enabled?(opts) do
    Keyword.get(opts, :persisted?, false) == true or
      is_function(operational_interval_reader(:source_health, opts), 3)
  end

  defp source_health_interval_for_status(intervals, %SourceHealthStatus{} = status) do
    Enum.find(List.wrap(intervals), fn interval ->
      source_health_interval_matches_status?(interval, status)
    end) || unique_interval(List.wrap(intervals))
  end

  defp source_health_interval_matches_status?(
         %EffectiveInterval{} = interval,
         %SourceHealthStatus{} = status
       ) do
    payload = interval.payload || %{}

    map_value(payload, :source_health_event_id) == status.source_health_event_id or
      interval.source_event_id == source_health_operational_event_id(status)
  end

  defp source_health_interval_matches_status?(_interval, _status), do: false

  defp source_health_operational_event_id(%SourceHealthStatus{} = status) do
    replay_run_id = source_health_status_value(status, :replay_run_id)
    source_health_event_id = source_health_status_value(status, :source_health_event_id)

    cond do
      is_binary(replay_run_id) and replay_run_id != "" and is_binary(source_health_event_id) ->
        "operational_event:source_health_event:#{replay_run_id}:#{source_health_event_id}"

      is_binary(source_health_event_id) ->
        "operational_event:source_health_event:#{source_health_event_id}"

      true ->
        nil
    end
  end

  defp put_frame_provenance(%Frame{} = frame, provenance, link_context, evidence) do
    meta =
      frame.meta
      |> ensure_map()
      |> Map.merge(provenance)
      |> merge_evidence_refs(evidence)
      |> enrich_link_container(link_context)

    fields = Enum.map(frame.fields, &put_field_link_provenance(&1, link_context))

    Frame.new(%{frame | meta: meta, fields: fields})
  end

  defp put_frame_provenance(frame, _provenance, _link_context, _evidence), do: frame

  defp put_field_link_provenance(%Field{} = field, link_context) do
    Field.new(%{field | metadata: enrich_link_container(field.metadata, link_context)})
  end

  defp put_field_link_provenance(field, _link_context), do: field

  defp warning_links_or_request_links(
         %ResolveWarning{links: links},
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       )
       when links in [nil, []] do
    DataLinks.request_observable_links(request,
      source: :warning,
      source_binding: resolved_binding
    )
  end

  defp warning_links_or_request_links(%ResolveWarning{links: links}, _request, _resolved_binding),
    do: links

  defp enrich_link_container(container, link_context) when is_map(container) do
    cond do
      Map.has_key?(container, :links) ->
        Map.put(container, :links, enrich_data_links(Map.get(container, :links), link_context))

      Map.has_key?(container, "links") ->
        Map.put(container, "links", enrich_data_links(Map.get(container, "links"), link_context))

      true ->
        container
    end
  end

  defp enrich_link_container(container, _link_context), do: container

  defp enrich_data_links(links, link_context) when is_list(links) do
    Enum.map(links, &enrich_data_link(&1, link_context))
  end

  defp enrich_data_links(links, _link_context), do: links

  defp enrich_data_link(%DataLink{} = link, link_context) do
    %DataLink{link | context: merge_data_link_context(link.context, link_context)}
  end

  defp enrich_data_link(link, _link_context), do: link

  defp merge_data_link_context(context, link_context) do
    context = ensure_map(context)

    Map.merge(context, link_context, fn
      :data, left, right -> Map.merge(ensure_map(left), ensure_map(right))
      _key, _left, right -> right
    end)
  end

  defp source_link_context(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding
       ) do
    %{
      source_request_id: request.request_id,
      logical_source: request.logical_source,
      data: %{
        realm: resolved_binding.realm,
        data_source_id: resolved_binding.data_source.data_source_id,
        source_binding_id: resolved_binding.binding.binding_id,
        dataset: resolved_binding.dataset
      }
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp source_binding_provenance(%ResolvedSourceBinding{} = resolved_binding) do
    binding = resolved_binding.binding

    %{
      source_binding_id: binding.binding_id,
      source_binding_version: binding.binding_version,
      source_binding_event_id: binding.current_event_id,
      source_binding_interval: source_binding_interval_metadata(resolved_binding),
      source_binding_segment: source_binding_segment_metadata(resolved_binding),
      source_selection: non_empty_source_selection(resolved_binding)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp selected_operational_interval_provenance(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding,
         opts,
         %SourceResult{} = result
       ) do
    with true <- Keyword.get(opts, :persisted?, false) == true,
         %DateTime{} = at <-
           selected_operational_interval_at(request, resolved_binding, opts, result),
         mission_id when is_binary(mission_id) <- request.mission_id do
      organization_id = request.organization_id

      intervals =
        [
          selected_binding_set_interval(organization_id, mission_id, at, opts),
          selected_application_binding_interval(
            organization_id,
            mission_id,
            request,
            at,
            opts,
            result
          ),
          selected_catalog_revision_interval(organization_id, mission_id, request, at, opts)
        ]
        |> Enum.reject(&is_nil/1)

      case intervals do
        [] ->
          %{}

        intervals ->
          %{
            selected_operational_interval_at: at,
            selected_operational_intervals: Enum.map(intervals, &EffectiveInterval.metadata/1)
          }
      end
    else
      _other -> %{}
    end
  end

  defp selected_operational_interval_at(
         %PlannedSourceRequest{},
         %ResolvedSourceBinding{segment_from: %DateTime{} = from},
         _opts,
         _result
       ),
       do: from

  defp selected_operational_interval_at(
         %PlannedSourceRequest{},
         _resolved_binding,
         opts,
         %SourceResult{} = result
       ) do
    case Keyword.get(opts, :operational_interval_at) || Keyword.get(opts, :source_binding_at) do
      %DateTime{} = at -> at
      _other -> source_result_interval_at(result)
    end
  end

  defp source_result_interval_at(%SourceResult{frames: frames}) when is_list(frames) do
    Enum.find_value(frames, &frame_interval_at/1)
  end

  defp source_result_interval_at(_result), do: nil

  defp frame_interval_at(%Frame{fields: fields}) when is_list(fields) do
    fields
    |> Enum.sort_by(&frame_interval_field_sort_key/1)
    |> Enum.find_value(fn
      %Field{values: values} when is_list(values) ->
        Enum.find(values, &match?(%DateTime{}, &1))

      _field ->
        nil
    end)
  end

  defp frame_interval_at(_frame), do: nil

  defp frame_interval_field_sort_key(%Field{name: name}) when name in ["time", :time], do: 0

  defp frame_interval_field_sort_key(%Field{name: name})
       when name in ["observed_at", :observed_at], do: 1

  defp frame_interval_field_sort_key(%Field{name: name})
       when name in ["receipt_time", :receipt_time], do: 2

  defp frame_interval_field_sort_key(%Field{name: name})
       when name in ["generation_time", :generation_time], do: 3

  defp frame_interval_field_sort_key(_field), do: 10

  defp selected_binding_set_interval(organization_id, mission_id, %DateTime{} = at, opts) do
    organization_id
    |> operational_intervals(:binding_set, mission_id, [at: at], opts)
    |> unique_interval()
  end

  defp selected_application_binding_interval(
         organization_id,
         mission_id,
         %PlannedSourceRequest{} = request,
         %DateTime{} = at,
         opts,
         %SourceResult{} = result
       ) do
    case source_endpoint_scope_id(request) || source_endpoint_result_id(result) do
      nil ->
        nil

      source_endpoint_ref ->
        organization_id
        |> operational_intervals(
          :application_binding,
          mission_id,
          [at: at, source_endpoint_ref: source_endpoint_ref],
          opts
        )
        |> unique_interval()
    end
  end

  defp selected_catalog_revision_interval(
         organization_id,
         mission_id,
         %PlannedSourceRequest{} = request,
         %DateTime{} = at,
         opts
       ) do
    case catalog_family_for_request(request) do
      nil ->
        nil

      catalog_family ->
        organization_id
        |> operational_intervals(
          :catalog_revision,
          mission_id,
          [at: at, catalog_family: catalog_family],
          opts
        )
        |> unique_interval()
    end
  end

  defp operational_intervals(organization_id, kind, mission_id, interval_opts, registry_opts) do
    case operational_interval_reader(kind, registry_opts) do
      fun when is_function(fun, 3) ->
        fun.(organization_id, mission_id, interval_opts)

      nil ->
        default_operational_intervals(organization_id, kind, mission_id, interval_opts)
    end
  end

  defp default_operational_intervals(organization_id, :binding_set, mission_id, opts)
       when is_binary(organization_id),
       do: OperationalEvents.binding_set_intervals(organization_id, mission_id, opts)

  defp default_operational_intervals(_organization_id, :binding_set, mission_id, opts),
    do: OperationalEvents.binding_set_intervals(mission_id, opts)

  defp default_operational_intervals(organization_id, :application_binding, mission_id, opts)
       when is_binary(organization_id),
       do: OperationalEvents.application_binding_intervals(organization_id, mission_id, opts)

  defp default_operational_intervals(_organization_id, :application_binding, mission_id, opts),
    do: OperationalEvents.application_binding_intervals(mission_id, opts)

  defp default_operational_intervals(organization_id, :catalog_revision, mission_id, opts)
       when is_binary(organization_id),
       do: OperationalEvents.catalog_revision_intervals(organization_id, mission_id, opts)

  defp default_operational_intervals(_organization_id, :catalog_revision, mission_id, opts),
    do: OperationalEvents.catalog_revision_intervals(mission_id, opts)

  defp default_operational_intervals(organization_id, :source_health, mission_id, opts)
       when is_binary(organization_id),
       do: OperationalEvents.source_health_intervals(organization_id, mission_id, opts)

  defp default_operational_intervals(_organization_id, :source_health, mission_id, opts),
    do: OperationalEvents.source_health_intervals(mission_id, opts)

  defp operational_interval_reader(:binding_set, opts) do
    Keyword.get(opts, :binding_set_intervals_fun) ||
      operational_interval_reader_from_map(opts, :binding_set)
  end

  defp operational_interval_reader(:application_binding, opts) do
    Keyword.get(opts, :application_binding_intervals_fun) ||
      operational_interval_reader_from_map(opts, :application_binding)
  end

  defp operational_interval_reader(:catalog_revision, opts) do
    Keyword.get(opts, :catalog_revision_intervals_fun) ||
      operational_interval_reader_from_map(opts, :catalog_revision)
  end

  defp operational_interval_reader(:source_health, opts) do
    Keyword.get(opts, :source_health_intervals_fun) ||
      operational_interval_reader_from_map(opts, :source_health)
  end

  defp operational_interval_reader_from_map(opts, kind) do
    case Keyword.get(opts, :operational_interval_funs) do
      funs when is_map(funs) -> Map.get(funs, kind) || Map.get(funs, Atom.to_string(kind))
      funs when is_list(funs) -> Keyword.get(funs, kind)
      _other -> nil
    end
  end

  defp unique_interval([%EffectiveInterval{} = interval]), do: interval
  defp unique_interval(_intervals), do: nil

  defp catalog_family_for_request(%PlannedSourceRequest{logical_source: logical_source})
       when logical_source in [:telemetry, :limits],
       do: :telemetry

  defp catalog_family_for_request(%PlannedSourceRequest{}), do: nil

  defp operational_interval_evidence_refs(interval_provenance, %PlannedSourceRequest{} = request) do
    interval_provenance
    |> Map.get(:selected_operational_intervals, [])
    |> DataLinks.operational_interval_evidence_refs(source: request.logical_source)
  end

  defp source_endpoint_scope_id(%PlannedSourceRequest{scope_context: scope_context}) do
    ScopeContext.scope_id(scope_context, :source_endpoint)
  end

  defp source_endpoint_result_id(%SourceResult{frames: frames}) when is_list(frames) do
    Enum.find_value(frames, fn
      %Frame{meta: meta} ->
        non_empty_text(
          get_attr(meta, :source_endpoint_id) || get_attr(meta, :source_endpoint_ref)
        ) || source_endpoint_frame_field_id(frames)

      _frame ->
        nil
    end)
  end

  defp source_endpoint_result_id(%SourceResult{}), do: nil

  defp source_endpoint_frame_field_id(frames) when is_list(frames) do
    frames
    |> Enum.flat_map(&source_endpoint_frame_field_values/1)
    |> Enum.map(&non_empty_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [source_endpoint_id] -> source_endpoint_id
      _other -> nil
    end
  end

  defp source_endpoint_frame_field_values(%Frame{fields: fields}) when is_list(fields) do
    fields
    |> Enum.filter(fn
      %Field{name: name} -> name in ["source_endpoint_id", "source_endpoint_ref"]
      _field -> false
    end)
    |> Enum.flat_map(fn %Field{values: values} -> List.wrap(values) end)
  end

  defp source_endpoint_frame_field_values(_frame), do: []

  defp non_empty_text(value) when is_binary(value) and value != "", do: value
  defp non_empty_text(_value), do: nil

  defp non_empty_source_selection(%ResolvedSourceBinding{source_selection: selection})
       when is_map(selection) and map_size(selection) > 0,
       do: selection

  defp non_empty_source_selection(%ResolvedSourceBinding{}), do: nil

  defp source_binding_segment_metadata(
         %ResolvedSourceBinding{
           segment_from: %DateTime{} = from,
           segment_to: %DateTime{} = to
         } = resolved_binding
       ) do
    binding = resolved_binding.binding

    %{
      from: from,
      to: to,
      binding_id: binding.binding_id,
      binding_version: binding.binding_version,
      data_binding_event_id: binding.current_event_id,
      data_source_id: resolved_binding.data_source.data_source_id,
      dataset: resolved_binding.dataset,
      realm: resolved_binding.realm,
      interval: source_binding_interval_metadata(resolved_binding)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp source_binding_segment_metadata(%ResolvedSourceBinding{}), do: nil

  defp source_binding_interval_metadata(%ResolvedSourceBinding{
         binding_interval: %DataBindingInterval{} = interval
       }) do
    DataBindingInterval.metadata(interval)
  end

  defp source_binding_interval_metadata(%ResolvedSourceBinding{}), do: nil

  defp source_binding_evidence_refs(
         %ResolvedSourceBinding{} = resolved_binding,
         %PlannedSourceRequest{} = request
       ) do
    resolved_binding
    |> source_binding_evidence_metadata()
    |> List.wrap()
    |> DataLinks.source_binding_interval_evidence_refs(source: request.logical_source)
  end

  defp source_binding_evidence_metadata(%ResolvedSourceBinding{} = resolved_binding) do
    case source_binding_interval_metadata(resolved_binding) do
      nil ->
        binding = resolved_binding.binding

        %{
          binding_id: binding.binding_id,
          data_binding_event_id: binding.current_event_id,
          started_at: binding.active_from,
          active_from: binding.active_from
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      metadata ->
        metadata
    end
  end

  defp source_status_evidence_refs(%SourceResult{} = result) do
    result
    |> source_status_evidence_metadata()
    |> then(fn metadata ->
      DataLinks.source_watermark_event_evidence_refs(metadata) ++
        DataLinks.source_health_event_evidence_refs(metadata)
    end)
    |> dedupe_evidence_refs()
  end

  defp source_status_evidence_metadata(%SourceResult{} = result) do
    [
      status_metadata(result.meta)
      | Enum.map(List.wrap(result.watermarks), &watermark_status_metadata/1)
    ]
  end

  defp watermark_status_metadata(%SourceWatermark{} = watermark) do
    status_metadata(watermark.meta)
  end

  defp watermark_status_metadata(_watermark), do: %{}

  defp status_metadata(metadata) do
    metadata = ensure_map(metadata)

    Map.put_new(
      metadata,
      :observed_at,
      Map.get(metadata, :source_watermark_observed_at) ||
        Map.get(metadata, :source_health_observed_at)
    )
  end

  defp merge_evidence_refs(meta, []), do: meta

  defp merge_evidence_refs(meta, evidence) when is_map(meta) and is_list(evidence) do
    Map.put(
      meta,
      :evidence,
      dedupe_evidence_refs(existing_evidence_refs(meta) ++ evidence)
    )
  end

  defp existing_evidence_refs(meta) when is_map(meta) do
    List.wrap(Map.get(meta, :evidence)) ++
      List.wrap(Map.get(meta, "evidence")) ++
      List.wrap(Map.get(meta, :evidence_refs)) ++
      List.wrap(Map.get(meta, "evidence_refs"))
  end

  defp dedupe_evidence_refs(evidence) do
    Enum.uniq_by(evidence, &evidence_ref_identity/1)
  end

  defp evidence_ref_identity(%{kind: kind, id: id}), do: {kind, id}

  defp evidence_ref_identity(%{} = ref) do
    {Map.get(ref, :kind, Map.get(ref, "kind")), Map.get(ref, :id, Map.get(ref, "id"))}
  end

  defp evidence_ref_identity(ref), do: ref

  defp source_health_attrs(
         %PlannedSourceRequest{} = request,
         resolved_binding,
         source_health,
         reason
       ) do
    %{
      organization_id:
        request.organization_id || resolved_binding.binding.organization_id ||
          resolved_binding.data_source.organization_id,
      mission_id:
        request.mission_id || resolved_binding.binding.mission_id ||
          resolved_binding.data_source.mission_id,
      logical_source: request.logical_source || resolved_binding.binding.logical_source,
      data_source_id: resolved_binding.data_source.data_source_id,
      source_binding_id: resolved_binding.binding.binding_id,
      realm: resolved_binding.realm,
      dataset: resolved_binding.dataset,
      source_health: source_health,
      reason: reason
    }
  end

  defp source_health_payload(%SourceResult{} = result, circuit_status) do
    %{
      degraded?: Map.get(result.meta, :degraded?),
      returned_frame_count: Map.get(result.meta, :returned_frame_count),
      warning_codes: Enum.map(result.warnings, & &1.code),
      circuit: circuit_status_payload(circuit_status)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp circuit_status_payload(nil), do: nil

  defp circuit_status_payload(status) when is_map(status) do
    status
    |> Map.take([
      :state,
      :failure_count,
      :failure_threshold,
      :backoff_ms,
      :retry_after_ms,
      :last_failure_reason
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp inspect_source_failure({:exception, exception}) do
    Exception.message(exception)
  end

  defp inspect_source_failure({:timeout, timeout_ms}) when is_integer(timeout_ms) do
    "timeout after #{timeout_ms}ms"
  end

  defp inspect_source_failure({:source_execution_exit, reason}) do
    "source execution exited: #{inspect(reason)}"
  end

  defp inspect_source_failure({kind, reason}) when kind in [:exit, :throw, :error] do
    "#{kind}: #{inspect(reason)}"
  end

  defp inspect_source_failure(reason), do: inspect(reason)

  defp source_binding_range(opts) do
    opts
    |> Keyword.get(:source_binding_range)
    |> normalize_source_binding_range()
  end

  defp normalize_source_binding_range(%{from: %DateTime{} = from, to: %DateTime{} = to}) do
    ordered_range(from, to)
  end

  defp normalize_source_binding_range(%{"from" => %DateTime{} = from, "to" => %DateTime{} = to}) do
    ordered_range(from, to)
  end

  defp normalize_source_binding_range(range) when is_list(range) do
    from = Keyword.get(range, :from)
    to = Keyword.get(range, :to)

    case {from, to} do
      {%DateTime{} = from, %DateTime{} = to} -> ordered_range(from, to)
      _other -> nil
    end
  end

  defp normalize_source_binding_range(_range), do: nil

  defp ordered_range(%DateTime{} = from, %DateTime{} = to) do
    if DateTime.compare(from, to) == :lt, do: {from, to}
  end

  defp sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> get_attr(:mode)
    |> normalize_atom()
  end

  defp requested_replay_run_id(%PlannedSourceRequest{} = request) do
    DataContext.source_value(request.data_context, request.logical_source, :replay_run_id) ||
      get_attr(request.time_context, :replay_run_id)
  end

  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> maybe_existing_atom()
  end

  defp normalize_atom(value), do: value

  defp maybe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(attrs, key) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}
end
