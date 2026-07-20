defmodule Cadence.Dashboards.SourceRegistry do
  @moduledoc """
  Dispatches planned dashboard source requests to logical source adapters.

  This is intentionally small until source bindings and data-source registry
  records exist. The engine depends on this dispatcher, not concrete adapters.
  """

  alias Cadence.Dashboards.{
    DashboardContract,
    DataLinks,
    DataSourceRegistry,
    DataSources,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolvedSourceCredential,
    ResolveWarning,
    RuntimeCacheKey,
    SourceActions,
    SourceCapabilities,
    SourceCredentialMaterial,
    SourceCredentials,
    SourceExecutionPolicy,
    SourceFacts,
    SourceHealth,
    SourceResult,
    SourceWatermarks
  }

  alias Cadence.Dashboards.SourceRegistry.{
    CapabilityPosture,
    ExecutionMonitoring,
    FactsAggregation,
    HealthMerge,
    Provenance,
    SegmentResultMerge,
    SourceHealthLookup,
    WatermarkMerge
  }

  alias Cadence.Dashboards.Sources.{Events, Limits, OperationalObservables, Telemetry}

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
        source_binding_interval: Provenance.interval(resolved_binding),
        source_selection: Provenance.selection(resolved_binding),
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
    segments = Enum.map(resolved_bindings, &Provenance.segment/1)

    provenance =
      %{
        logical_source: request.logical_source,
        segmented_source_bindings?: true,
        source_binding_segment_count: length(segments),
        source_binding_segments: segments,
        source_selections:
          resolved_bindings
          |> Enum.map(&Provenance.selection/1)
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
        result = source_unavailable(request, resolved_binding, reason)

        ExecutionMonitoring.record_result(
          request,
          resolved_binding,
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
        {:ok, FactsAggregation.merge(request, segment_facts, &Provenance.segment/1)}

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
       |> Provenance.put_facts(resolved_binding, capability_provenance)
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
      case SourceHealthLookup.fetch(request, resolved_binding, opts) do
        {:ok, status} ->
          classification =
            SourceHealth.classify_status(status, resolved_binding.data_source, opts)

          interval = SourceHealthLookup.interval(request, resolved_binding, status, opts)

          HealthMerge.merge_facts(facts, classification, interval)

        {:error, :source_health_status_not_found} ->
          classification =
            SourceHealth.classify_status(nil, resolved_binding.data_source, opts)

          HealthMerge.merge_facts(facts, classification, nil)
      end
    else
      facts
    end
  end

  defp merge_persisted_source_watermark(
         %SourceFacts{} = facts,
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    if SourceWatermarks.enabled?(opts) do
      case SourceWatermarks.fetch_status_for_source(request, resolved_binding) do
        {:ok, status} ->
          WatermarkMerge.merge_facts(facts, status, request)

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
      details: Provenance.details(request, resolved_binding),
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
           &Provenance.segment/1
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
          |> Map.put(:source_binding_segment, Provenance.segment(resolved_binding))
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

    case ExecutionMonitoring.allow(request, resolved_binding, source_policy, opts) do
      {:blocked, status} ->
        result = source_degraded(request, resolved_binding, status, opts)

        ExecutionMonitoring.record_health(
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

        ExecutionMonitoring.record_result(
          request,
          resolved_binding,
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
        |> Provenance.put_result(resolved_binding, request, opts)

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

  defp source_degraded(%PlannedSourceRequest{} = request, resolved_binding, status, opts) do
    source_error(
      request,
      source_degraded_warning(request, resolved_binding, status)
    )
    |> Provenance.put_result(resolved_binding, request, opts)
  end

  defp source_unavailable(%PlannedSourceRequest{} = request, resolved_binding, reason) do
    source_error(
      request,
      source_unavailable_warning(request, resolved_binding, reason)
    )
    |> Provenance.put_result(resolved_binding, request, [])
  end

  defp source_unavailable(%PlannedSourceRequest{} = request, resolved_binding, reason, opts) do
    source_error(
      request,
      source_unavailable_warning(request, resolved_binding, reason)
    )
    |> Provenance.put_result(resolved_binding, request, opts)
  end

  defp source_degraded_warning(%PlannedSourceRequest{} = request, resolved_binding, status) do
    %ResolveWarning{
      code: :source_degraded,
      severity: :error,
      scope: :dashboard,
      message: "Source circuit is open after repeated failures",
      details:
        Provenance.details(request, resolved_binding)
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
        Provenance.details(request, resolved_binding)
        |> Map.put(:reason, inspect_source_failure(reason)),
      links: DataLinks.request_observable_links(request, source: :warning)
    }
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
          WatermarkMerge.merge_result(result, status, request)

        {:error, :source_watermark_status_not_found} ->
          result
      end
    else
      result
    end
  end

  defp merge_persisted_source_result_health(
         %SourceResult{} = result,
         %PlannedSourceRequest{} = request,
         resolved_binding,
         opts
       ) do
    if SourceHealth.enabled?(opts) do
      case SourceHealthLookup.fetch(request, resolved_binding, opts) do
        {:ok, status} ->
          classification =
            SourceHealth.classify_status(status, resolved_binding.data_source, opts)

          interval = SourceHealthLookup.interval(request, resolved_binding, status, opts)

          meta =
            result.meta
            |> HealthMerge.classification_meta(classification, interval)

          evidence =
            DataLinks.source_health_event_evidence_refs([Provenance.status_metadata(meta)]) ++
              DataLinks.operational_interval_evidence_refs([interval],
                source: request.logical_source
              )

          SourceResult.new(%{
            result
            | meta:
                meta
                |> maybe_mark_source_health_degraded()
                |> Provenance.merge_evidence(evidence),
              watermarks: Enum.map(result.watermarks, &HealthMerge.put_watermark(&1, meta)),
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
      |> Provenance.merge_evidence(evidence)

    Frame.new(%{frame | meta: meta})
  end

  defp put_frame_source_health_meta(frame, _source_health_meta, _evidence), do: frame

  defp maybe_mark_source_health_degraded(%{source_health: source_health} = meta)
       when source_health in [:degraded, :unavailable, :unknown],
       do: Map.put(meta, :degraded?, true)

  defp maybe_mark_source_health_degraded(meta), do: meta

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
