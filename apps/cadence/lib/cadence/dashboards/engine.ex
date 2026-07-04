defmodule Cadence.Dashboards.Engine do
  @moduledoc """
  Dashboard engine planner.

  `plan/1` validates the document, expands widget contracts into logical source
  requests, batches equivalent requests, and returns placement request mappings.
  `resolve/2` executes those planned source requests through source adapters and
  fans frames back to placement buckets.
  """

  alias Cadence.Dashboards.{
    DashboardContract,
    DashboardResolveRequest,
    DashboardResolveResult,
    DataContext,
    DataLinks,
    DataSourceRegistry,
    FrameMaterializer,
    LimitContext,
    LimitSelectedClockAudit,
    Placement,
    PlacementExpansion,
    PlacementFrames,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    RuntimeCache,
    RuntimeCacheKey,
    ScopeContext,
    SourceCapabilities,
    SourceExecutionPolicy,
    SourceFacts,
    SourceFreshness,
    SourceRegistry,
    SourceResult,
    SourceResultPreflight,
    TimeContext,
    ValidationResult,
    WidgetFrameContract,
    WidgetRegistry
  }

  @spec resolve(DashboardResolveRequest.t(), keyword()) :: DashboardResolveResult.t()
  def resolve(%DashboardResolveRequest{} = request, opts \\ []) when is_list(opts) do
    request = DashboardResolveRequest.normalize(request)
    plan_result = plan(request, opts)

    request
    |> execute_plan(plan_result, opts)
    |> validate_resolve_contract!(opts)
  end

  @spec plan(DashboardResolveRequest.t(), keyword()) :: DashboardResolveResult.t()
  def plan(%DashboardResolveRequest{} = request, opts \\ []) when is_list(opts) do
    request = DashboardResolveRequest.normalize(request)
    validate_request_contract!(request, opts)

    opts = plan_dependency_opts(opts)
    plan_key = RuntimeCacheKey.plan(request, opts)

    plan_key
    |> fetch_plan_cache(opts)
    |> case do
      {:hit, %DashboardResolveResult{} = cached_result} ->
        mark_plan_cache(cached_result, :hit, plan_key)

      :miss ->
        request
        |> plan_uncached(opts, plan_key)
        |> tap(&put_plan_cache(plan_key, &1, opts))
        |> mark_plan_cache(:miss, plan_key)

      :disabled ->
        request
        |> plan_uncached(opts, plan_key)
        |> mark_plan_cache(:disabled, plan_key)
    end
    |> validate_plan_contract!(opts)
  end

  defp validate_request_contract!(%DashboardResolveRequest{} = request, opts) do
    if validate_dashboard_contract?(opts) do
      request
      |> DashboardContract.validate_request()
      |> raise_contract_violations!(:request)
    end

    request
  end

  defp validate_plan_contract!(%DashboardResolveResult{} = result, opts) do
    result = DashboardResolveResult.normalize(result)

    if validate_dashboard_contract?(opts) do
      result
      |> DashboardContract.validate_plan_result()
      |> raise_contract_violations!(:plan_result)
    end

    result
  end

  defp validate_resolve_contract!(%DashboardResolveResult{} = result, opts) do
    result = DashboardResolveResult.normalize(result)

    if validate_dashboard_contract?(opts) do
      result
      |> DashboardContract.validate_resolve_result()
      |> raise_contract_violations!(:resolve_result)
    end

    result
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

  defp validate_planned_source_requests_contract!(requests, opts) when is_list(requests) do
    if validate_dashboard_contract?(opts) do
      violations =
        requests
        |> Enum.with_index()
        |> Enum.flat_map(&planned_source_request_violations/1)

      raise_contract_violations!(contract_result(violations), :planned_source_request)
    end

    requests
  end

  defp planned_source_request_violations({%PlannedSourceRequest{} = request, index}) do
    request
    |> DashboardContract.validate_planned_source_request()
    |> planned_source_request_violations(index)
  end

  defp planned_source_request_violations({request, index}) do
    [
      %{
        path: [index],
        code: :invalid_planned_source_request,
        message: "expected %PlannedSourceRequest{}, got #{inspect(request)}"
      }
    ]
  end

  defp planned_source_request_violations(:ok, _index), do: []

  defp planned_source_request_violations({:error, errors}, index) do
    Enum.map(errors, &prefix_violation_path(&1, [index]))
  end

  defp validate_dashboard_contract?(opts),
    do: Keyword.get(opts, :validate_dashboard_contract?, false) == true

  defp raise_contract_violations!(:ok, _boundary), do: :ok

  defp raise_contract_violations!({:error, violations}, boundary) do
    raise ArgumentError,
          "dashboard #{boundary} contract violated: " <> format_contract_violations(violations)
  end

  defp contract_result([]), do: :ok
  defp contract_result(violations), do: {:error, violations}

  defp prefix_violation_path(violation, prefix) do
    Map.update(violation, :path, prefix, &(prefix ++ &1))
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

  defp plan_uncached(%DashboardResolveRequest{} = request, opts, %RuntimeCacheKey{} = plan_key) do
    validation = Cadence.Dashboards.validate_document(request.document)

    {planned_requests, frames_by_placement, placement_warnings} =
      PlacementExpansion.expand(request.document, request.scope_context)
      |> Enum.reduce({[], %{}, []}, fn placement, {requests, frames, warnings} ->
        case plan_placement(request, placement, opts) do
          {:ok, placement_requests, request_warnings} ->
            placement_frames = %PlacementFrames{
              planned_request_ids: Enum.map(placement_requests, & &1.request_id),
              warnings: request_warnings
            }

            {requests ++ placement_requests,
             Map.put(frames, placement.placement_id, placement_frames),
             warnings ++ request_warnings}

          {:warning, warning} ->
            placement_frames = %PlacementFrames{warnings: [warning]}

            {requests, Map.put(frames, placement.placement_id, placement_frames),
             warnings ++ [warning]}
        end
      end)

    {batched_requests, request_id_rewrites} = batch_requests(planned_requests)
    batched_requests = validate_planned_source_requests_contract!(batched_requests, opts)

    %DashboardResolveResult{
      dashboard_id: request.dashboard_id || request.document.dashboard_id,
      resolve_mode: request.resolve_mode,
      frames_by_placement:
        rewrite_placement_request_ids(frames_by_placement, request_id_rewrites),
      dashboard_warnings: validation_warnings(validation) ++ placement_warnings,
      planned_source_requests: batched_requests,
      plan_metadata: %{
        cache: %{
          plan_key: plan_key,
          dependencies: plan_cache_dependencies(plan_key)
        },
        time: time_context_metadata(request),
        snapshot?: snapshot_time_context?(request),
        live_append_eligible?: live_append_eligible?(request),
        source_request_count: length(batched_requests),
        unbatched_source_request_count: length(planned_requests),
        batched_consumer_count:
          batched_requests
          |> Enum.flat_map(& &1.consumers)
          |> length(),
        degraded?: validation_has_errors?(validation) or placement_warnings != []
      }
    }
  end

  defp plan_dependency_opts(opts) do
    opts
    |> Keyword.put_new_lazy(:widget_registry_version, &WidgetRegistry.version/0)
    |> Keyword.put_new_lazy(:source_capability_version, fn ->
      SourceRegistry.capability_fingerprint(opts)
    end)
  end

  defp plan_cache_dependencies(%RuntimeCacheKey{parts: parts}) do
    %{
      document_schema_version: get_in(parts, [:document, :schema_version]),
      widget_registry_version: Map.get(parts, :widget_registry_version),
      source_capability_version: Map.get(parts, :source_capability_version)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp fetch_plan_cache(%RuntimeCacheKey{} = plan_key, opts) do
    case runtime_cache_server(opts) do
      {:ok, server} ->
        case RuntimeCache.get_plan(plan_key, server) do
          {:ok, result} -> {:hit, result}
          :miss -> :miss
        end

      :disabled ->
        :disabled
    end
  end

  defp put_plan_cache(%RuntimeCacheKey{} = plan_key, %DashboardResolveResult{} = result, opts) do
    case runtime_cache_server(opts) do
      {:ok, server} -> RuntimeCache.put_plan(plan_key, result, server)
      :disabled -> :ok
    end
  end

  defp mark_plan_cache(%DashboardResolveResult{} = result, status, %RuntimeCacheKey{} = plan_key)
       when status in [:hit, :miss, :disabled] do
    plan_cache = %{status: status, key: plan_key}

    %DashboardResolveResult{
      result
      | plan_metadata:
          update_in(result.plan_metadata, [Access.key(:cache, %{})], fn cache ->
            cache
            |> Map.put(:plan_key, plan_key)
            |> Map.put(:plan_cache, plan_cache)
          end)
    }
  end

  defp runtime_cache_server(opts) do
    cond do
      Keyword.get(opts, :plan_cache?, true) == false ->
        :disabled

      Keyword.get(opts, :runtime_cache) == false ->
        :disabled

      server = Keyword.get(opts, :runtime_cache) ->
        {:ok, server}

      dashboard_runtime_cache_enabled?() and Process.whereis(RuntimeCache) ->
        {:ok, RuntimeCache}

      true ->
        :disabled
    end
  end

  defp source_result_cache_server(opts) do
    cond do
      Keyword.get(opts, :source_result_cache?, false) != true ->
        :disabled

      Keyword.get(opts, :runtime_cache) == false ->
        :disabled

      server = Keyword.get(opts, :runtime_cache) ->
        {:ok, server}

      dashboard_runtime_cache_enabled?() and Process.whereis(RuntimeCache) ->
        {:ok, RuntimeCache}

      true ->
        :disabled
    end
  end

  defp frame_cache_server(opts) do
    cond do
      Keyword.get(opts, :frame_cache?, false) != true ->
        :disabled

      Keyword.get(opts, :runtime_cache) == false ->
        :disabled

      server = Keyword.get(opts, :runtime_cache) ->
        {:ok, server}

      dashboard_runtime_cache_enabled?() and Process.whereis(RuntimeCache) ->
        {:ok, RuntimeCache}

      true ->
        :disabled
    end
  end

  defp dashboard_runtime_cache_enabled? do
    :cadence
    |> Application.get_env(:dashboard_runtime_cache, [])
    |> Keyword.get(:enabled?, true)
  end

  defp plan_placement(%DashboardResolveRequest{} = request, %Placement{} = placement, opts) do
    widget_def = placement.widget_def
    {runtime_contexts, context_warnings} = placement_runtime_contexts(request, placement)

    case WidgetRegistry.fetch_type(widget_def.widget_type_id, widget_def.widget_type_version) do
      {:ok, widget_type} ->
        case WidgetFrameContract.primary_frame_specs(widget_type, widget_def.binding) do
          {:ok, primary_frame_specs} ->
            {primary_source_requests, capability_warnings} =
              primary_frame_specs
              |> Enum.map(
                &plan_frame_request(request, placement, widget_type, &1, runtime_contexts, opts)
              )
              |> split_planned_requests()

            {overlay_source_requests, overlay_warnings} =
              widget_type
              |> source_backed_overlay_specs(placement)
              |> Enum.flat_map(
                &plan_overlay_requests(
                  request,
                  placement,
                  widget_type,
                  &1,
                  primary_frame_specs,
                  runtime_contexts,
                  opts
                )
              )
              |> split_planned_requests()

            source_requests = primary_source_requests ++ overlay_source_requests

            {:ok, source_requests, context_warnings ++ capability_warnings ++ overlay_warnings}

          {:error, contract_details} ->
            {:ok, [],
             context_warnings ++
               [unsupported_widget_frame_contract_warning(placement, contract_details)]}
        end

      {:error, reason} ->
        {:warning,
         %ResolveWarning{
           code: reason,
           severity: :warning,
           scope: :placement,
           placement_id: placement.placement_id,
           message: "Widget type is not available",
           details: %{
             widget_type_id: widget_def.widget_type_id,
             widget_type_version: widget_def.widget_type_version
           }
         }}
    end
  end

  defp plan_frame_request(request, placement, widget_type, frame_spec, runtime_contexts, opts) do
    binding = placement.widget_def.binding
    role = Map.get(frame_spec, :role, :primary)
    source = Map.fetch!(frame_spec, :source)

    planned_sampling = sampling(binding, frame_spec, request, placement, widget_type)

    planned_request = %PlannedSourceRequest{
      request_id: source_request_id(placement.placement_id, role, source),
      organization_id: request.organization_id || request.document.organization_id,
      mission_id: request.mission_id || request.document.mission_id,
      logical_source: source,
      observables: Map.get(binding, :observables, []),
      scope_context: runtime_contexts.scope,
      time_context: source_time_context(runtime_contexts.time, source, planned_sampling),
      data_context: overlay_data_context(runtime_contexts.data, source),
      limit_context: runtime_contexts.limit,
      value_type: Map.get(binding, :value_type),
      sampling: planned_sampling,
      source_dependencies: source_dependencies(source, planned_sampling, runtime_contexts.limit),
      overlays: unresolved_overlays(binding, widget_type),
      consumers: [
        %{
          placement_id: placement.placement_id,
          role: role,
          widget_type_id: widget_type.widget_type_id
        }
      ]
    }

    case validate_planned_request_observable_scope(planned_request, placement, frame_spec) do
      {:ok, planned_request} ->
        validate_planned_request_capability(planned_request, placement, frame_spec, opts)

      {:warning, warning} ->
        {:warning, warning}
    end
  end

  defp split_planned_requests(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, request}, {requests, warnings} -> {requests ++ [request], warnings}
      {:warning, warning}, {requests, warnings} -> {requests, warnings ++ [warning]}
    end)
  end

  defp validate_planned_request_observable_scope(
         %PlannedSourceRequest{logical_source: :operational_observables} = request,
         %Placement{} = placement,
         frame_spec
       ) do
    scope_kind = normalized_primary_scope_kind(request.scope_context)
    scope_ids = ScopeContext.primary_ids(request.scope_context)
    observables = List.wrap(request.observables)

    unsupported =
      WidgetFrameContract.unsupported_operational_observable_scope_ids(observables, scope_kind)

    if unsupported == [] do
      {:ok, request}
    else
      {:warning,
       unsupported_observable_scope_warning(
         request,
         placement,
         frame_spec,
         scope_kind,
         scope_ids,
         unsupported
       )}
    end
  end

  defp validate_planned_request_observable_scope(
         %PlannedSourceRequest{} = request,
         %Placement{},
         _frame_spec
       ),
       do: {:ok, request}

  defp unsupported_observable_scope_warning(
         %PlannedSourceRequest{} = request,
         %Placement{} = placement,
         frame_spec,
         scope_kind,
         scope_ids,
         unsupported
       ) do
    %ResolveWarning{
      code: :unsupported_observable_scope,
      severity: :warning,
      scope: :placement,
      placement_id: placement.placement_id,
      message: "Widget observables do not support selected runtime scope",
      details: %{
        source_request_id: request.request_id,
        logical_source: request.logical_source,
        requested_scope_kind: scope_kind,
        requested_scope_ids: scope_ids,
        unsupported_observables: unsupported,
        supported_scopes:
          WidgetFrameContract.supported_operational_observable_scopes(
            List.wrap(request.observables)
          ),
        accepted_shapes: Map.get(frame_spec, :accepted_shapes, []),
        fallback: :none
      },
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp validate_planned_request_capability(
         %PlannedSourceRequest{} = request,
         %Placement{} = placement,
         frame_spec,
         opts
       ) do
    requested_sampling = Map.get(request.sampling, :mode)

    case SourceRegistry.capability_context(request, source_registry_opts(request, opts)) do
      {:ok, %{capabilities: %SourceCapabilities{} = capabilities, provenance: provenance}} ->
        request = put_capability_provenance(request, provenance)

        requested_source_products = requested_source_products(request, capabilities)

        if SourceCapabilities.supports_sampling?(capabilities, requested_sampling) and
             supports_source_products?(capabilities, requested_source_products) do
          {:ok, request}
        else
          {:warning,
           unsupported_source_capability_warning(
             request,
             placement,
             frame_spec,
             capabilities,
             provenance,
             requested_sampling,
             requested_source_products
           )}
        end

      {:error, %ResolveWarning{} = warning} ->
        {:warning, placement_warning(warning, placement)}
    end
  end

  defp unsupported_source_capability_warning(
         %PlannedSourceRequest{} = request,
         %Placement{} = placement,
         frame_spec,
         %SourceCapabilities{} = capabilities,
         provenance,
         requested_sampling,
         requested_source_products
       ) do
    %ResolveWarning{
      code: :unsupported_source_capability,
      severity: :warning,
      scope: :placement,
      placement_id: placement.placement_id,
      message: "Source cannot satisfy requested capability",
      details: %{
        source_request_id: request.request_id,
        logical_source: request.logical_source,
        requested_observables: request.observables,
        unsupported_observables: request.observables,
        requested_sampling: requested_sampling,
        supported_sampling: capabilities.supported_sampling,
        requested_products: Map.get(request.sampling, :products, []),
        requested_source_products: requested_source_products,
        supported_products: capabilities.supported_products,
        requested_product_families: requested_product_families(request, capabilities),
        supported_product_families: supported_product_families(capabilities),
        requested_value_kinds: Map.get(frame_spec, :observable_value_kinds, []),
        supported_value_kinds: Map.get(frame_spec, :observable_value_kinds, []),
        accepted_shapes: Map.get(frame_spec, :accepted_shapes, []),
        supported_shapes: capabilities.supported_shapes,
        fallback: :none,
        capability_provenance: provenance,
        source_binding_id: Map.get(provenance, :binding_id),
        data_source_id: Map.get(provenance, :data_source_id),
        realm: Map.get(provenance, :realm),
        dataset: Map.get(provenance, :dataset),
        capability_fingerprint: Map.get(provenance, :capability_fingerprint)
      },
      links: DataLinks.request_observable_links(request, source: :warning)
    }
  end

  defp supports_source_products?(_capabilities, []), do: true

  defp supports_source_products?(%SourceCapabilities{} = capabilities, requested_products) do
    supported_products = MapSet.new(supported_source_products(capabilities))

    Enum.all?(requested_products, &MapSet.member?(supported_products, &1))
  end

  defp supported_source_products(%SourceCapabilities{} = capabilities) do
    capabilities.supported_products
    |> Kernel.++(supported_source_backing_products(capabilities))
    |> Enum.uniq()
  end

  defp supported_source_backing_products(%SourceCapabilities{} = capabilities) do
    capabilities
    |> source_backing_contracts()
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&source_backing_product_supported?(capabilities, &1))
    |> Enum.uniq()
  end

  defp supported_product_families(%SourceCapabilities{} = capabilities) do
    capabilities
    |> source_backing_contracts()
    |> Enum.filter(fn contract ->
      source_backing_product_supported?(capabilities, Map.get(contract, :product))
    end)
    |> Enum.map(&Map.get(&1, :product_family))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp requested_source_products(
         %PlannedSourceRequest{logical_source: :operational_observables} = request,
         %SourceCapabilities{} = capabilities
       ) do
    request
    |> source_backing_contracts_for_request(capabilities)
    |> Enum.map(&Map.get(&1, :product))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp requested_source_products(%PlannedSourceRequest{} = request, _capabilities) do
    Map.get(request.sampling, :products, [])
  end

  defp requested_product_families(
         %PlannedSourceRequest{logical_source: :operational_observables} = request,
         %SourceCapabilities{} = capabilities
       ) do
    request
    |> source_backing_contracts_for_request(capabilities)
    |> Enum.map(&Map.get(&1, :product_family))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp requested_product_families(%PlannedSourceRequest{} = request, _capabilities) do
    Map.get(request.sampling, :families, [])
  end

  defp source_backing_contracts_for_request(%PlannedSourceRequest{} = request, capabilities) do
    requested_observables = List.wrap(request.observables)
    requested_sampling = Map.get(request.sampling || %{}, :mode)

    capabilities
    |> source_backing_contracts()
    |> Enum.filter(fn contract ->
      observables = Map.get(contract, :observables, [])

      Map.get(contract, :sampling) == requested_sampling and
        requested_observables != [] and
        Enum.all?(requested_observables, &(&1 in observables))
    end)
    |> Enum.sort_by(fn contract -> contract |> Map.get(:observables, []) |> length() end)
    |> case do
      [contract | _rest] -> [contract]
      [] -> []
    end
  end

  defp source_backing_contracts(%SourceCapabilities{} = capabilities) do
    capabilities.metadata
    |> Map.get(:source_backing_contracts, [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
  end

  defp source_backing_product_supported?(%SourceCapabilities{} = capabilities, product) do
    products = capabilities.supported_products

    product in products or
      (product in supported_source_products_for_aggregate(:operational_latest, capabilities) and
         :operational_latest in products) or
      (product in supported_source_products_for_aggregate(
         :operational_state_history,
         capabilities
       ) and
         :operational_state_history in products) or
      (product in supported_source_products_for_aggregate(
         :operational_metric_history,
         capabilities
       ) and
         :operational_metric_history in products)
  end

  defp supported_source_products_for_aggregate(
         aggregate_product,
         %SourceCapabilities{} = capabilities
       ) do
    capabilities
    |> source_backing_contracts()
    |> Enum.filter(&(Map.get(&1, :product) == aggregate_product))
    |> Enum.flat_map(fn aggregate_contract ->
      aggregate_observables = Map.get(aggregate_contract, :observables, [])
      aggregate_sampling = Map.get(aggregate_contract, :sampling)

      capabilities
      |> source_backing_contracts()
      |> Enum.filter(fn contract ->
        Map.get(contract, :sampling) == aggregate_sampling and
          Enum.all?(Map.get(contract, :observables, []), &(&1 in aggregate_observables))
      end)
      |> Enum.map(&Map.get(&1, :product))
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp put_capability_provenance(%PlannedSourceRequest{} = request, provenance) do
    metadata = if is_map(request.metadata), do: request.metadata, else: %{}

    %PlannedSourceRequest{
      request
      | metadata:
          metadata
          |> Map.put(:capability_provenance, provenance)
    }
  end

  defp placement_warning(%ResolveWarning{} = warning, %Placement{} = placement) do
    %ResolveWarning{warning | scope: :placement, placement_id: placement.placement_id}
  end

  defp normalized_primary_scope_kind(scope_context) do
    case ScopeContext.primary_kind(scope_context) do
      scope_kind when is_atom(scope_kind) ->
        scope_kind

      scope_kind when is_binary(scope_kind) ->
        scope_kind
        |> String.trim()
        |> String.downcase()
        |> String.replace("-", "_")
        |> normalize_known_atom([
          :mission,
          :spacecraft,
          :contact,
          :ground_station,
          :source_endpoint,
          :transport,
          :link
        ])

      _scope_kind ->
        nil
    end
  end

  defp unsupported_widget_frame_contract_warning(%Placement{} = placement, details) do
    %ResolveWarning{
      code: :unsupported_widget_frame_contract,
      severity: :warning,
      scope: :placement,
      placement_id: placement.placement_id,
      message: "Widget cannot consume requested source",
      details:
        details
        |> Map.put(:placement_id, placement.placement_id)
        |> Map.put(:widget_id, placement.placement_id)
        |> Map.put(:fallback, :none)
    }
  end

  defp plan_overlay_requests(
         request,
         placement,
         widget_type,
         overlay_spec,
         primary_frame_specs,
         runtime_contexts,
         opts
       ) do
    samplings =
      overlay_samplings(overlay_spec, primary_frame_specs, request, placement, widget_type)

    multi_product? = length(samplings) > 1

    Enum.map(samplings, fn sampling ->
      plan_overlay_request(
        request,
        placement,
        widget_type,
        overlay_spec,
        runtime_contexts,
        opts,
        sampling,
        multi_product?
      )
    end)
  end

  defp plan_overlay_request(
         request,
         placement,
         widget_type,
         overlay_spec,
         runtime_contexts,
         opts,
         sampling,
         multi_product?
       ) do
    binding = placement.widget_def.binding
    role = Map.fetch!(overlay_spec, :role)
    source = Map.fetch!(overlay_spec, :source)

    planned_request = %PlannedSourceRequest{
      request_id:
        overlay_source_request_id(placement.placement_id, role, source, sampling, multi_product?),
      organization_id: request.organization_id || request.document.organization_id,
      mission_id: request.mission_id || request.document.mission_id,
      logical_source: source,
      observables: Map.get(binding, :observables, []),
      scope_context: runtime_contexts.scope,
      time_context: source_time_context(runtime_contexts.time, source, sampling),
      data_context: runtime_contexts.data,
      limit_context: runtime_contexts.limit,
      value_type: Map.get(binding, :value_type),
      sampling: sampling,
      source_dependencies: source_dependencies(source, sampling, runtime_contexts.limit),
      overlays: [],
      consumers: [
        %{
          placement_id: placement.placement_id,
          role: role,
          widget_type_id: widget_type.widget_type_id
        }
      ]
    }

    validate_planned_request_capability(planned_request, placement, overlay_spec, opts)
  end

  defp source_time_context(time_context, :events, _sampling) do
    put_time_axis(time_context, :occurred_at)
  end

  defp source_time_context(time_context, :limits, sampling) do
    if Map.get(sampling, :temporal?, false) do
      put_time_axis(time_context, :receipt_time)
    else
      time_context
    end
  end

  defp source_time_context(time_context, :telemetry, _sampling), do: time_context

  defp source_time_context(time_context, _source, _sampling), do: time_context

  defp put_time_axis(%TimeContext{} = time_context, axis),
    do: %TimeContext{time_context | axis: axis}

  defp put_time_axis(time_context, axis) when is_map(time_context),
    do: Map.put(time_context, :axis, axis)

  defp put_time_axis(time_context, _axis), do: time_context

  defp source_backed_overlay_specs(widget_type, placement) do
    requested_overlays = Map.get(placement.widget_def.binding, :overlays, [])

    widget_type.data_contract
    |> Map.get(:overlays, [])
    |> Enum.filter(fn overlay_spec ->
      source_backed_overlay?(overlay_spec) and
        (Map.get(overlay_spec, :required?, false) or
           Map.get(overlay_spec, :role) in requested_overlays)
    end)
  end

  defp source_backed_overlay?(%{source: :limits}), do: true
  defp source_backed_overlay?(%{source: :events}), do: true
  defp source_backed_overlay?(_overlay_spec), do: false

  defp unresolved_overlays(binding, widget_type) do
    source_backed_roles =
      widget_type
      |> Map.get(:data_contract, %{})
      |> Map.get(:overlays, [])
      |> Enum.filter(&source_backed_overlay?/1)
      |> Enum.map(&Map.get(&1, :role))

    binding
    |> Map.get(:overlays, [])
    |> Enum.reject(&(&1 in source_backed_roles))
  end

  defp sampling(binding, frame_spec, request, placement, widget_type) do
    poll_latest? = poll_latest_live_request?(request, widget_type, frame_spec)

    mode =
      if poll_latest? do
        :latest
      else
        Map.get(binding, :sampling) || Map.get(frame_spec, :sampling)
      end

    %{
      mode: mode,
      target_points: target_points(placement_size(request, placement.placement_id)),
      max_raw_points: 10_000,
      temporal?: if(poll_latest?, do: false, else: Map.get(frame_spec, :temporal?, false))
    }
    |> maybe_put_sampling_products(frame_spec)
    |> maybe_put_sampling_families(frame_spec)
  end

  defp maybe_put_sampling_products(sampling, %{products: products})
       when is_list(products) and products != [] do
    Map.put(sampling, :products, products)
  end

  defp maybe_put_sampling_products(sampling, _frame_spec), do: sampling

  defp maybe_put_sampling_families(sampling, %{families: families})
       when is_list(families) and families != [] do
    Map.put(sampling, :families, families)
  end

  defp maybe_put_sampling_families(sampling, _frame_spec), do: sampling

  defp overlay_samplings(
         %{source: :limits},
         primary_frame_specs,
         request,
         _placement,
         widget_type
       ) do
    if poll_latest_live_request?(request, widget_type) do
      [latest_limit_overlay_sampling()]
    else
      temporal? = Enum.any?(primary_frame_specs, &Map.get(&1, :temporal?, false))

      decimated? =
        Enum.any?(primary_frame_specs, &(Map.get(&1, :sampling) == :decimated_envelope))

      cond do
        temporal? and decimated? ->
          [
            limit_analysis_buckets_overlay_sampling(),
            limit_definition_intervals_overlay_sampling()
          ]

        temporal? ->
          [limit_event_history_overlay_sampling(), limit_definition_intervals_overlay_sampling()]

        true ->
          [latest_limit_overlay_sampling()]
      end
    end
  end

  defp overlay_samplings(
         %{source: :events},
         primary_frame_specs,
         request,
         placement,
         _widget_type
       ) do
    temporal? = Enum.any?(primary_frame_specs, &Map.get(&1, :temporal?, false))

    source_watermark_context =
      source_watermark_overlay_context(primary_frame_specs, request, placement)

    [
      %{
        mode: :event_history,
        products: [
          :contact_intervals,
          :mission_timeline,
          :source_health_transitions,
          :source_watermark_events,
          :source_capability_postures,
          :telemetry_backfill_lifecycle,
          :telemetry_revision_decisions
        ],
        families: [
          :contacts,
          :mission_timeline,
          :source_health,
          :source_watermarks,
          :source_capabilities,
          :telemetry_backfills,
          :telemetry_revisions
        ],
        temporal?: temporal?,
        source_watermark: source_watermark_context,
        limit: 500
      }
      |> drop_empty_map_value(:source_watermark)
    ]
  end

  defp source_watermark_overlay_context(primary_frame_specs, request, placement) do
    logical_source = primary_logical_source(primary_frame_specs, placement)
    data_context = placement_data_context(request, placement)

    %{
      logical_source: logical_source,
      data_source_id: data_context_value(data_context, logical_source, :data_source_id),
      source_binding_id: data_context_value(data_context, logical_source, :source_binding_id),
      dataset: data_context_value(data_context, logical_source, :dataset)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
    |> non_empty_map()
  end

  defp primary_logical_source(primary_frame_specs, placement) do
    binding = placement.widget_def.binding || %{}

    Map.get(binding, :source) ||
      primary_frame_specs
      |> List.wrap()
      |> Enum.find_value(&Map.get(&1, :source))
  end

  defp placement_data_context(%DashboardResolveRequest{} = request, %Placement{} = placement) do
    defaults = request.document.defaults || %{}

    time_context =
      TimeContext.resolve(request.time_context, Map.get(defaults, "time") || %{}, nil)

    request.data_context
    |> DataContext.resolve(Map.get(defaults, "data") || %{}, placement.data_override)
    |> default_replay_realm_if_implicit(
      time_context,
      request.data_context,
      placement.data_override
    )
  end

  defp data_context_value(%DataContext{} = data_context, nil, key),
    do: Map.get(data_context, key)

  defp data_context_value(%DataContext{} = data_context, logical_source, key),
    do: DataContext.source_value(data_context, logical_source, key)

  defp overlay_data_context(%DataContext{} = data_context, _source) do
    %DataContext{data_context | data_source_id: nil, source_binding_id: nil, dataset: nil}
  end

  defp overlay_data_context(data_context, _source), do: data_context

  defp non_empty_map(map) when map == %{}, do: nil
  defp non_empty_map(map), do: map

  defp drop_empty_map_value(map, key) do
    case Map.get(map, key) do
      nil -> Map.delete(map, key)
      %{} = value when map_size(value) == 0 -> Map.delete(map, key)
      _value -> map
    end
  end

  defp latest_limit_overlay_sampling do
    %{
      mode: :latest_state,
      products: [:latest_state],
      semantics_mode: :observed,
      temporal?: false
    }
  end

  defp limit_event_history_overlay_sampling do
    %{
      mode: :event_history,
      products: [:event_history],
      semantics_mode: :observed,
      temporal?: true,
      limit: 1_000
    }
  end

  defp limit_analysis_buckets_overlay_sampling do
    %{
      mode: :analysis_buckets,
      products: [:analysis_buckets],
      semantics_mode: :observed,
      temporal?: true,
      limit: 1_000
    }
  end

  defp limit_definition_intervals_overlay_sampling do
    %{
      mode: :definition_intervals,
      products: [:definition_intervals],
      semantics_mode: :observed,
      temporal?: true
    }
  end

  defp poll_latest_live_request?(request, widget_type, frame_spec) do
    poll_latest_live_request?(request, widget_type) and Map.get(frame_spec, :temporal?, false)
  end

  defp poll_latest_live_request?(%DashboardResolveRequest{} = request, widget_type) do
    request.resolve_mode in [:live_tick, :stream_append] and
      live_append_eligible?(request) and
      get_in(widget_type.data_contract, [:live_mode]) == :poll_latest
  end

  defp live_append_eligible?(%DashboardResolveRequest{} = request) do
    not snapshot_time_context?(request)
  end

  defp snapshot_time_context?(%DashboardResolveRequest{} = request) do
    time_context_mode(request) in [:archive, :range, :replay_run]
  end

  defp time_context_metadata(%DashboardResolveRequest{} = request) do
    time_context =
      TimeContext.resolve(request.time_context, request_document_time_defaults(request), nil)

    %{
      mode: normalized_time_mode(time_context.mode),
      axis: normalized_time_axis(time_context.axis),
      from: time_context.from || time_context.start || time_context.start_time,
      to: time_context.to || time_context.end || time_context.end_time,
      replay_run_id: time_context.replay_run_id
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp time_context_mode(%DashboardResolveRequest{} = request) do
    request
    |> time_context_metadata()
    |> Map.get(:mode)
  end

  defp request_document_time_defaults(%DashboardResolveRequest{document: %{defaults: defaults}})
       when is_map(defaults) do
    Map.get(defaults, "time") || Map.get(defaults, :time) || %{}
  end

  defp request_document_time_defaults(%DashboardResolveRequest{}), do: %{}

  defp normalized_time_mode(value),
    do: normalize_known_atom(value, [:live, :archive, :range, :replay_run])

  defp normalized_time_axis(value),
    do: normalize_known_atom(value, [:generation_time, :receipt_time])

  defp normalize_known_atom(value, known_values) when is_atom(value) do
    if value in known_values, do: value, else: value
  end

  defp normalize_known_atom(value, known_values) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(known_values, &(Atom.to_string(&1) == normalized)) || value
  end

  defp normalize_known_atom(value, _known_values), do: value

  defp target_points(%{width_px: width}) when is_integer(width) and width > 0, do: width
  defp target_points(%{"width_px" => width}) when is_integer(width) and width > 0, do: width
  defp target_points(_placement_size), do: 1200

  defp placement_runtime_contexts(%DashboardResolveRequest{} = request, %Placement{} = placement) do
    defaults = request.document.defaults || %{}

    time_context =
      TimeContext.resolve(request.time_context, Map.get(defaults, "time") || %{}, nil)

    data_context =
      request.data_context
      |> DataContext.resolve(Map.get(defaults, "data") || %{}, placement.data_override)
      |> default_replay_realm_if_implicit(
        time_context,
        request.data_context,
        placement.data_override
      )

    contexts = %{
      time: time_context,
      scope:
        ScopeContext.resolve(
          request.scope_context,
          Map.get(defaults, "scope") || %{},
          placement.scope_override
        ),
      data: data_context,
      limit:
        LimitContext.resolve(
          request.limit_context,
          Map.get(defaults, "limits") || %{},
          placement.limit_override
        )
    }

    {contexts, context_warnings(contexts, placement)}
  end

  defp default_replay_realm_if_implicit(
         %DataContext{} = data_context,
         %TimeContext{} = time_context,
         runtime_data_context,
         placement_data_override
       ) do
    cond do
      normalized_time_mode(time_context.mode) != :replay_run ->
        data_context

      explicit_data_realm?(runtime_data_context) or explicit_data_realm?(placement_data_override) ->
        data_context

      data_context.realm in [nil, :flight, "flight"] ->
        %DataContext{data_context | realm: :replay}

      true ->
        data_context
    end
  end

  defp explicit_data_realm?(%DataContext{realm: realm}), do: present_context_value?(realm)

  defp explicit_data_realm?(attrs) when is_map(attrs),
    do: present_context_value?(get_attr(attrs, :realm))

  defp explicit_data_realm?(_attrs), do: false

  defp present_context_value?(nil), do: false
  defp present_context_value?(""), do: false
  defp present_context_value?(_value), do: true

  defp context_warnings(contexts, %Placement{} = placement) do
    [
      {:time, TimeContext.validate(contexts.time)},
      {:scope, ScopeContext.validate(contexts.scope)},
      {:data, DataContext.validate(contexts.data)},
      {:limit, LimitContext.validate(contexts.limit)}
    ]
    |> Enum.reject(fn {_context, errors} -> errors == [] end)
    |> Enum.map(fn {context, errors} ->
      %ResolveWarning{
        code: :invalid_runtime_context,
        severity: :warning,
        scope: :placement,
        placement_id: placement.placement_id,
        message: "Dashboard runtime context contains unsupported values",
        details: %{context: context, errors: errors}
      }
    end)
  end

  defp batch_requests(requests) do
    batches =
      requests
      |> Enum.group_by(&batch_key/1)
      |> Enum.map(fn {_key, grouped_requests} -> build_batch(grouped_requests) end)
      |> Enum.sort_by(fn {request, _rewrites} -> request.request_id end)

    {
      Enum.map(batches, fn {request, _rewrites} -> request end),
      batches
      |> Enum.flat_map(fn {_request, rewrites} -> rewrites end)
      |> Map.new()
    }
  end

  defp build_batch([%PlannedSourceRequest{} = first | rest]) do
    batched_id = batched_request_id(first)
    grouped_requests = [first | rest]

    request = %PlannedSourceRequest{
      first
      | request_id: batched_id,
        consumers: Enum.flat_map(grouped_requests, & &1.consumers)
    }

    rewrites = Enum.map(grouped_requests, &{&1.request_id, batched_id})

    {request, rewrites}
  end

  defp batch_key(%PlannedSourceRequest{} = request) do
    {
      request.logical_source,
      request.organization_id,
      request.mission_id,
      request.observables,
      request.scope_context,
      request.time_context,
      request.data_context,
      request.limit_context,
      request.value_type,
      request.sampling,
      request.source_dependencies,
      request.overlays
    }
  end

  defp batched_request_id(%PlannedSourceRequest{} = request) do
    fingerprint =
      request
      |> batch_key()
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 12)

    "source_req_" <> Atom.to_string(request.logical_source) <> "_" <> fingerprint
  end

  defp rewrite_placement_request_ids(frames_by_placement, rewrites) do
    Map.new(frames_by_placement, fn {placement_id, frames} ->
      request_ids = Enum.map(frames.planned_request_ids, &Map.get(rewrites, &1, &1))
      {placement_id, %{frames | planned_request_ids: Enum.uniq(request_ids)}}
    end)
  end

  defp execute_plan(
         %DashboardResolveRequest{} = request,
         %DashboardResolveResult{} = plan_result,
         opts
       ) do
    requests_to_execute = executable_source_requests(plan_result)
    freshness_now = Keyword.get_lazy(opts, :freshness_now, &DateTime.utc_now/0)
    source_execution_policy = SourceExecutionPolicy.resolve(opts)
    source_execution_policies = source_execution_policies(requests_to_execute, opts)

    source_executions =
      execute_source_requests(
        requests_to_execute,
        request,
        plan_result,
        freshness_now,
        source_execution_policy,
        source_execution_policies,
        opts
      )

    source_results =
      Enum.map(source_executions, fn {source_request, source_result, _cache_entry} ->
        {source_request, source_result}
      end)

    limit_selected_clock_audit =
      maybe_persist_limit_selected_clock_audit_events(request, source_results, opts)

    source_result_cache_entries =
      Map.new(source_executions, fn {source_request, _source_result, cache_entry} ->
        {source_request.request_id,
         put_cache_entry_capability_provenance(cache_entry, source_request)}
      end)

    source_keys =
      source_result_keys_by_request_id(
        request,
        plan_result,
        source_results,
        source_result_cache_entries,
        opts
      )

    {frames_by_placement, frame_cache_entries} =
      materialize_source_results(
        request,
        plan_result.frames_by_placement,
        source_results,
        source_keys,
        source_result_cache_entries,
        opts
      )

    source_warnings =
      source_results
      |> Enum.flat_map(fn {_request, source_result} -> source_result.warnings end)

    cache_provenance =
      cache_provenance(source_keys, source_result_cache_entries, frame_cache_entries)

    %DashboardResolveResult{
      plan_result
      | frames_by_placement: frames_by_placement,
        dashboard_warnings: plan_result.dashboard_warnings ++ source_warnings,
        watermarks: Enum.flat_map(source_results, fn {_request, result} -> result.watermarks end),
        plan_metadata:
          plan_result.plan_metadata
          |> Map.put(
            :source_execution_policy,
            SourceExecutionPolicy.metadata(source_execution_policy)
          )
          |> Map.put(
            :source_execution_policies_by_request_id,
            source_execution_policy_metadata(source_execution_policies)
          )
          |> Map.put(:executed_source_request_count, length(source_results))
          |> Map.put(
            :skipped_source_request_count,
            length(plan_result.planned_source_requests) - length(source_results)
          )
          |> Map.put(
            :source_selection_by_request_id,
            source_selection_by_request_id(source_results)
          )
          |> Map.put(:returned_frame_count, returned_frame_count(source_results))
          |> Map.put(:degraded?, plan_result.plan_metadata.degraded? or degraded?(source_results))
          |> put_limit_selected_clock_audit(limit_selected_clock_audit)
          |> put_cache_provenance(cache_provenance)
    }
  end

  defp maybe_persist_limit_selected_clock_audit_events(
         %DashboardResolveRequest{} = resolve_request,
         source_results,
         opts
       ) do
    if Keyword.get(opts, :persist_limit_selected_clock_audit_events?, false) do
      LimitSelectedClockAudit.persist_source_results(resolve_request, source_results)
    else
      %{event_ids: [], errors: []}
    end
  end

  defp put_limit_selected_clock_audit(plan_metadata, %{event_ids: [], errors: []}),
    do: plan_metadata

  defp put_limit_selected_clock_audit(plan_metadata, audit) when is_map(audit),
    do: Map.put(plan_metadata, :limit_selected_clock_audit, audit)

  defp execute_source_requests(
         [],
         %DashboardResolveRequest{},
         %DashboardResolveResult{},
         %DateTime{},
         %SourceExecutionPolicy{},
         _source_execution_policies,
         _opts
       ),
       do: []

  defp execute_source_requests(
         source_requests,
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %DateTime{} = freshness_now,
         %SourceExecutionPolicy{max_concurrency: 1} = policy,
         source_execution_policies,
         opts
       ) do
    Enum.map(source_requests, fn %PlannedSourceRequest{} = source_request ->
      source_policy =
        Map.get(source_execution_policies, source_request.request_id, policy)

      execute_source_request_with_policy(
        resolve_request,
        plan_result,
        source_request,
        freshness_now,
        source_policy,
        opts
      )
    end)
  end

  defp execute_source_requests(
         source_requests,
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %DateTime{} = freshness_now,
         %SourceExecutionPolicy{} = policy,
         source_execution_policies,
         opts
       ) do
    source_requests
    |> Task.async_stream(
      fn %PlannedSourceRequest{} = source_request ->
        source_policy =
          Map.get(source_execution_policies, source_request.request_id, policy)

        execute_source_request_with_policy(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          source_policy,
          opts
        )
      end,
      max_concurrency: policy.max_concurrency,
      timeout: SourceExecutionPolicy.stream_timeout(source_execution_policies, policy),
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(source_requests)
    |> Enum.map(fn
      {{:ok, source_execution}, _source_request} ->
        source_execution

      {{:exit, :timeout}, source_request} ->
        failed_source_execution(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          opts,
          {:timeout, source_timeout(source_execution_policies, source_request, policy)}
        )

      {{:exit, reason}, source_request} ->
        failed_source_execution(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          opts,
          {:source_execution_exit, reason}
        )
    end)
  end

  defp source_execution_policies(source_requests, opts) do
    Map.new(source_requests, fn %PlannedSourceRequest{} = source_request ->
      {source_request.request_id,
       SourceRegistry.execution_policy(source_request, source_registry_opts(source_request, opts))}
    end)
  end

  defp source_execution_policy_metadata(source_execution_policies) do
    Map.new(source_execution_policies, fn {request_id, policy} ->
      {request_id, SourceExecutionPolicy.source_metadata(policy)}
    end)
  end

  defp execute_source_request_with_policy(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         %SourceExecutionPolicy{timeout_ms: :infinity} = source_policy,
         opts
       ) do
    execute_source_request(
      resolve_request,
      plan_result,
      source_request,
      freshness_now,
      source_policy_opts(opts, source_policy)
    )
  end

  defp execute_source_request_with_policy(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         %SourceExecutionPolicy{} = source_policy,
         opts
       ) do
    opts = source_policy_opts(opts, source_policy)

    task =
      Task.async(fn ->
        execute_source_request(resolve_request, plan_result, source_request, freshness_now, opts)
      end)

    case Task.yield(task, source_policy.timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, source_execution} ->
        source_execution

      {:exit, reason} ->
        failed_source_execution(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          opts,
          {:source_execution_exit, reason}
        )

      nil ->
        failed_source_execution(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          opts,
          {:timeout, source_policy.timeout_ms}
        )
    end
  end

  defp source_timeout(
         source_execution_policies,
         %PlannedSourceRequest{} = source_request,
         fallback
       ) do
    source_execution_policies
    |> Map.get(source_request.request_id, fallback)
    |> Map.fetch!(:timeout_ms)
  end

  defp source_policy_opts(opts, %SourceExecutionPolicy{} = source_policy) do
    Keyword.put(opts, :source_execution_policy, source_policy)
  end

  defp failed_source_execution(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         opts,
         reason
       ) do
    source_result =
      source_request
      |> SourceRegistry.unavailable(reason, source_registry_opts(source_request, opts))
      |> then(
        &annotate_source_freshness(
          resolve_request,
          plan_result,
          source_request,
          &1,
          freshness_now,
          source_registry_opts(source_request, opts)
        )
      )

    cache_key =
      source_result_cache_key(
        resolve_request,
        plan_result,
        source_request,
        source_result,
        opts
      )

    {source_request, source_result,
     %{
       status: :source_execution_failed,
       key: cache_key,
       reason: source_execution_failure_reason(reason)
     }}
  end

  defp source_execution_failure_reason({:timeout, _timeout_ms}), do: :timeout

  defp source_execution_failure_reason({:source_execution_exit, _reason}),
    do: :source_execution_exit

  defp source_execution_failure_reason(_reason), do: :source_execution_failed

  defp executable_source_requests(%DashboardResolveResult{
         resolve_mode: :live_tick,
         plan_metadata: %{live_append_eligible?: false}
       }) do
    []
  end

  defp executable_source_requests(%DashboardResolveResult{
         resolve_mode: :stream_append,
         plan_metadata: %{live_append_eligible?: false}
       }) do
    []
  end

  defp executable_source_requests(%DashboardResolveResult{
         resolve_mode: :live_tick,
         planned_source_requests: requests
       }) do
    Enum.filter(requests, &live_tick_refreshable?/1)
  end

  defp executable_source_requests(%DashboardResolveResult{planned_source_requests: requests}) do
    requests
  end

  defp execute_source_request(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         opts
       ) do
    case source_result_cache_server(opts) do
      {:ok, server} ->
        execute_source_request_with_cache(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          opts,
          server
        )

      :disabled ->
        source_result =
          resolve_source_request(
            resolve_request,
            plan_result,
            source_request,
            freshness_now,
            opts
          )

        cache_key =
          source_result_cache_key(
            resolve_request,
            plan_result,
            source_request,
            source_result,
            opts
          )

        {source_request, source_result, %{status: :disabled, key: cache_key}}
    end
  end

  defp execute_source_request_with_cache(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         opts,
         server
       ) do
    case current_source_result_cache_key(
           resolve_request,
           plan_result,
           source_request,
           freshness_now,
           opts
         ) do
      {:ok, cache_key, %SourceFacts{} = source_facts} ->
        fetch_or_resolve_source_result(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          opts,
          server,
          cache_key,
          source_facts
        )

      {:error, %ResolveWarning{} = warning} ->
        source_result =
          resolve_source_request(
            resolve_request,
            plan_result,
            source_request,
            freshness_now,
            opts
          )

        cache_key =
          source_result_cache_key(
            resolve_request,
            plan_result,
            source_request,
            source_result,
            opts
          )

        {source_request, source_result,
         %{status: :facts_error, key: cache_key, reason: warning.code, details: warning.details}}
    end
  end

  defp fetch_or_resolve_source_result(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         opts,
         server,
         %RuntimeCacheKey{} = cache_key,
         %SourceFacts{} = source_facts
       ) do
    case RuntimeCache.get_source_result(cache_key, server) do
      {:ok, cached_result} ->
        cached_result = annotate_source_result_provenance(cached_result, source_request)

        preflight =
          SourceResultPreflight.evaluate(cache_key, cached_result, cache_key,
            source_health: source_facts.source_health
          )

        if preflight.status == :usable do
          {source_request, cached_result,
           %{status: :hit, key: cache_key, reasons: []}
           |> put_source_facts_cache_metadata(source_facts)}
        else
          resolve_and_store_source_result(
            resolve_request,
            plan_result,
            source_request,
            freshness_now,
            opts,
            server,
            cache_key,
            %{status: :stale, reasons: preflight.reasons, details: preflight.details}
            |> put_source_facts_cache_metadata(source_facts)
          )
        end

      :miss ->
        resolve_and_store_source_result(
          resolve_request,
          plan_result,
          source_request,
          freshness_now,
          opts,
          server,
          cache_key,
          %{status: :miss, reasons: []}
          |> put_source_facts_cache_metadata(source_facts)
        )
    end
  end

  defp resolve_and_store_source_result(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         opts,
         server,
         %RuntimeCacheKey{} = cache_key,
         cache_entry
       ) do
    source_result =
      resolve_source_request(resolve_request, plan_result, source_request, freshness_now, opts)

    :ok = RuntimeCache.put_source_result(cache_key, source_result, server)

    {source_request, source_result, Map.put(cache_entry, :key, cache_key)}
  end

  defp put_source_facts_cache_metadata(cache_entry, %SourceFacts{} = facts)
       when is_map(cache_entry) do
    facts_meta = ensure_map(facts.meta)

    cache_entry
    |> maybe_put_cache_metadata(
      :capability_provenance,
      Map.get(facts_meta, :capability_provenance)
    )
    |> maybe_put_cache_metadata(:capability_posture, Map.get(facts_meta, :capability_posture))
  end

  defp maybe_put_cache_metadata(cache_entry, _key, nil), do: cache_entry
  defp maybe_put_cache_metadata(cache_entry, key, value), do: Map.put(cache_entry, key, value)

  defp resolve_source_request(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         opts
       ) do
    freshness_policy = freshness_policy(resolve_request, plan_result, source_request, opts)

    registry_opts =
      source_request
      |> source_registry_opts(opts)
      |> Keyword.put(:freshness_policy, freshness_policy)
      |> Keyword.put(:freshness_now, freshness_now)

    source_request
    |> SourceRegistry.resolve(registry_opts)
    |> validate_source_result_contract!(opts)
    |> then(
      &annotate_source_freshness(
        resolve_request,
        plan_result,
        source_request,
        &1,
        freshness_now,
        registry_opts
      )
    )
  end

  defp current_source_result_cache_key(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         %DateTime{} = freshness_now,
         opts
       ) do
    freshness_policy = freshness_policy(resolve_request, plan_result, source_request, opts)

    registry_opts = source_registry_opts(source_request, opts)

    with {:ok, %SourceFacts{} = source_facts} <-
           SourceRegistry.facts(source_request, registry_opts) do
      source_facts =
        annotate_source_facts(source_facts, source_request, freshness_policy, freshness_now)

      {:ok,
       SourceFacts.runtime_cache_key(source_request, source_facts,
         cache_policy: source_result_cache_policy(source_request),
         freshness_policy: freshness_policy
       ), source_facts}
    end
  end

  defp annotate_source_facts(
         %SourceFacts{watermark: nil, watermarks: []} = source_facts,
         %PlannedSourceRequest{},
         _freshness_policy,
         %DateTime{}
       ) do
    source_facts
  end

  defp annotate_source_facts(
         %SourceFacts{} = source_facts,
         %PlannedSourceRequest{} = source_request,
         freshness_policy,
         %DateTime{} = freshness_now
       ) do
    %SourceFacts{
      source_facts
      | watermark:
          annotate_source_watermark(
            source_facts.watermark,
            source_request,
            freshness_policy,
            freshness_now
          ),
        watermarks:
          Enum.map(source_facts.watermarks, fn watermark ->
            annotate_source_watermark(watermark, source_request, freshness_policy, freshness_now)
          end)
    }
  end

  defp annotate_source_watermark(nil, %PlannedSourceRequest{}, _freshness_policy, %DateTime{}),
    do: nil

  defp annotate_source_watermark(
         watermark,
         %PlannedSourceRequest{} = source_request,
         freshness_policy,
         %DateTime{} = freshness_now
       ) do
    SourceFreshness.annotate(
      watermark,
      source_request,
      freshness_policy,
      freshness_now
    )
  end

  defp annotate_source_freshness(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         source_result,
         %DateTime{} = now,
         opts
       ) do
    freshness_policy = freshness_policy(resolve_request, plan_result, source_request, opts)

    watermarks =
      Enum.map(source_result.watermarks, fn watermark ->
        SourceFreshness.annotate(watermark, source_request, freshness_policy, now)
      end)

    freshness_warnings =
      watermarks
      |> Enum.map(&SourceFreshness.warning(&1, source_request))
      |> Enum.reject(&is_nil/1)

    %{
      source_result
      | watermarks: watermarks,
        warnings: source_result.warnings ++ freshness_warnings
    }
    |> annotate_source_result_provenance(source_request)
  end

  defp annotate_source_result_provenance(source_result, %PlannedSourceRequest{} = source_request) do
    provenance = capability_provenance(source_request)

    %{
      source_result
      | meta:
          source_result.meta
          |> ensure_map()
          |> maybe_put_capability_provenance(provenance)
          |> maybe_put_source_dependencies(source_request.source_dependencies)
    }
  end

  defp freshness_policy(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         opts
       ) do
    SourceFreshness.resolve_policy(
      [
        source_freshness_policy(source_request.logical_source, opts),
        dashboard_freshness_policy(resolve_request),
        request_freshness_policy(source_request),
        consumer_freshness_policy(resolve_request.document, plan_result, source_request)
      ]
      |> List.flatten()
    )
  end

  defp source_freshness_policy(logical_source, opts) do
    opts
    |> Keyword.get(:source_freshness_policies, %{})
    |> get_attr(logical_source)
  end

  defp dashboard_freshness_policy(%DashboardResolveRequest{document: document}) do
    defaults = document.defaults || %{}
    health_defaults = get_attr(defaults, :health) || %{}

    [
      get_attr(defaults, :freshness_policy),
      get_attr(health_defaults, :freshness_policy)
    ]
  end

  defp request_freshness_policy(%PlannedSourceRequest{} = request) do
    [
      get_attr(request.sampling, :freshness_policy),
      get_attr(request.data_context, :freshness_policy),
      get_attr(request.limit_context, :freshness_policy)
    ]
  end

  defp consumer_freshness_policy(
         document,
         %DashboardResolveResult{} = plan_result,
         source_request
       ) do
    placement_by_id = Map.new(document.placements, &{&1.placement_id, &1})
    planned_request_ids = MapSet.new([source_request.request_id])

    plan_result.frames_by_placement
    |> Enum.filter(fn {_placement_id, frames} ->
      Enum.any?(frames.planned_request_ids, &MapSet.member?(planned_request_ids, &1))
    end)
    |> Enum.flat_map(fn {placement_id, _frames} ->
      case Map.get(placement_by_id, placement_id) do
        nil -> []
        placement -> placement_freshness_policies(placement)
      end
    end)
  end

  defp placement_freshness_policies(%Placement{} = placement) do
    widget_options =
      case placement.widget_def do
        %{options: options} when is_map(options) -> options
        _other -> %{}
      end

    widget_health = get_attr(widget_options, :health) || %{}
    overrides = placement.overrides || %{}
    override_health = get_attr(overrides, :health) || %{}

    [
      get_attr(widget_options, :freshness_policy),
      get_attr(widget_health, :freshness_policy),
      get_attr(overrides, :freshness_policy),
      get_attr(override_health, :freshness_policy)
    ]
  end

  defp source_result_keys_by_request_id(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         source_results,
         source_result_cache_entries,
         opts
       ) do
    Map.new(source_results, fn {%PlannedSourceRequest{} = source_request, source_result} ->
      {
        source_request.request_id,
        source_result_cache_key(
          resolve_request,
          plan_result,
          source_request,
          source_result,
          source_result_cache_entries,
          opts
        )
      }
    end)
  end

  defp cache_provenance(source_keys, source_result_cache_entries, frame_cache_entries) do
    %{
      source_result_keys_by_request_id: source_keys,
      source_result_cache_by_request_id: source_result_cache_entries,
      frame_keys_by_placement: frame_keys_by_placement(frame_cache_entries),
      frame_cache_by_placement: frame_cache_entries
    }
  end

  defp source_selection_by_request_id(source_results) do
    source_results
    |> Enum.reduce(%{}, fn {%PlannedSourceRequest{} = source_request, source_result}, acc ->
      case source_result_meta(source_result) |> Map.get(:source_selection) do
        selection when is_map(selection) and map_size(selection) > 0 ->
          Map.put(acc, source_request.request_id, selection)

        _other ->
          acc
      end
    end)
  end

  defp frame_keys_by_placement(frame_cache_entries) do
    Map.new(frame_cache_entries, fn {placement_id, entries_by_request_id} ->
      {placement_id,
       Map.new(entries_by_request_id, fn {request_id, cache_entry} ->
         {request_id, cache_entry.key}
       end)}
    end)
  end

  defp source_result_cache_key(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         source_result,
         source_result_cache_entries,
         opts
       ) do
    case get_in(source_result_cache_entries, [source_request.request_id, :key]) do
      %RuntimeCacheKey{} = cache_key ->
        cache_key

      _missing ->
        source_result_cache_key(resolve_request, plan_result, source_request, source_result, opts)
    end
  end

  defp source_result_cache_key(
         %DashboardResolveRequest{} = resolve_request,
         %DashboardResolveResult{} = plan_result,
         %PlannedSourceRequest{} = source_request,
         source_result,
         opts
       ) do
    registry_opts = source_registry_opts(source_request, opts)
    resolved_binding = resolved_source_binding(source_request, registry_opts)

    RuntimeCacheKey.source_result(source_request,
      cache_policy: source_result_cache_policy(source_request),
      source_binding: resolved_binding && resolved_binding.binding,
      source_binding_segments:
        get_in(source_result_meta(source_result), [:source_binding_segments]),
      data_source: resolved_binding && resolved_binding.data_source,
      freshness_policy: freshness_policy(resolve_request, plan_result, source_request, opts),
      watermark: List.first(source_result.watermarks)
    )
  end

  defp source_result_meta(%{meta: meta}) when is_map(meta), do: meta
  defp source_result_meta(_source_result), do: %{}

  defp source_result_cache_policy(%PlannedSourceRequest{} = source_request) do
    if source_request_snapshot?(source_request), do: :snapshot, else: :live
  end

  defp source_request_snapshot?(%PlannedSourceRequest{} = source_request) do
    source_request
    |> source_request_time_mode()
    |> Kernel.in([:archive, :range, :replay_run])
  end

  defp source_registry_opts(%PlannedSourceRequest{} = source_request, opts) do
    opts = maybe_put_replay_operational_interval_at(opts, source_request)

    case source_binding_time_window(source_request) do
      %{at: %DateTime{} = at} = window ->
        opts
        |> Keyword.put_new(:source_binding_at, at)
        |> maybe_put_source_binding_range(Map.get(window, :range))

      nil ->
        opts
    end
  end

  defp maybe_put_replay_operational_interval_at(opts, %PlannedSourceRequest{} = source_request) do
    if source_request_time_mode(source_request) == :replay_run do
      case source_binding_range_window(source_request) do
        %{at: %DateTime{} = at} -> Keyword.put_new(opts, :operational_interval_at, at)
        _missing -> opts
      end
    else
      opts
    end
  end

  defp source_binding_time_window(%PlannedSourceRequest{} = source_request) do
    case source_request_time_mode(source_request) do
      :range -> source_binding_range_window(source_request)
      :archive -> source_binding_archive_window(source_request)
      _other -> nil
    end
  end

  defp source_binding_archive_window(%PlannedSourceRequest{} = source_request) do
    if source_request.logical_source == :telemetry and
         source_request_sampling_mode(source_request) in [
           :raw_series,
           :bounded_history,
           :bounded_raw_series
         ] do
      source_binding_range_window(source_request)
    else
      source_binding_point_window(source_request)
    end
  end

  defp source_binding_range_window(%PlannedSourceRequest{} = source_request) do
    {from, to} = source_request_time_bounds(source_request)

    cond do
      datetime?(from) and datetime?(to) and DateTime.compare(from, to) == :lt ->
        %{at: from, range: %{from: from, to: to}}

      datetime?(from) ->
        %{at: from}

      datetime?(to) ->
        %{at: to}

      true ->
        nil
    end
  end

  defp source_binding_point_window(%PlannedSourceRequest{} = source_request) do
    {from, to} = source_request_time_bounds(source_request)

    cond do
      datetime?(to) -> %{at: to}
      datetime?(from) -> %{at: from}
      true -> nil
    end
  end

  defp source_request_time_bounds(%PlannedSourceRequest{time_context: time_context}) do
    {
      get_attr(time_context, :from) || get_attr(time_context, :start) ||
        get_attr(time_context, :start_time),
      get_attr(time_context, :to) || get_attr(time_context, :end) ||
        get_attr(time_context, :end_time)
    }
  end

  defp maybe_put_source_binding_range(opts, nil), do: opts

  defp maybe_put_source_binding_range(opts, range) when is_map(range) do
    Keyword.put_new(opts, :source_binding_range, range)
  end

  defp datetime?(%DateTime{}), do: true
  defp datetime?(_value), do: false

  defp source_request_time_mode(%PlannedSourceRequest{time_context: time_context}) do
    time_context
    |> get_attr(:mode)
    |> normalized_time_mode()
  end

  defp source_request_sampling_mode(%PlannedSourceRequest{sampling: sampling}) do
    sampling
    |> get_attr(:mode)
    |> normalize_known_atom([:latest, :raw_series, :bounded_history, :bounded_raw_series])
  end

  defp resolved_source_binding(%PlannedSourceRequest{} = source_request, opts) do
    case DataSourceRegistry.resolve(source_request, opts) do
      {:ok, %ResolvedSourceBinding{} = resolved_binding} -> resolved_binding
      {:error, _warning} -> nil
    end
  end

  defp placement_size(
         %DashboardResolveRequest{interaction_context: interaction_context},
         placement_id
       ) do
    placement_sizes =
      Map.get(
        interaction_context,
        :placement_sizes,
        Map.get(interaction_context, "placement_sizes", %{})
      )

    Map.get(placement_sizes, placement_id) ||
      Map.get(placement_sizes, PlacementExpansion.authored_placement_id(placement_id), %{})
  end

  defp put_cache_provenance(plan_metadata, cache_provenance) do
    Map.update(plan_metadata, :cache, cache_provenance, &Map.merge(&1, cache_provenance))
  end

  defp live_tick_refreshable?(%PlannedSourceRequest{
         logical_source: :telemetry,
         sampling: %{mode: :latest}
       }),
       do: true

  defp live_tick_refreshable?(%PlannedSourceRequest{
         logical_source: :limits,
         sampling: %{mode: mode}
       })
       when mode in [:latest, :latest_state],
       do: true

  defp live_tick_refreshable?(%PlannedSourceRequest{
         logical_source: :operational_observables,
         sampling: %{mode: :latest}
       }),
       do: true

  defp live_tick_refreshable?(%PlannedSourceRequest{}), do: false

  defp materialize_source_results(
         %DashboardResolveRequest{} = resolve_request,
         frames_by_placement,
         source_results,
         source_keys,
         source_result_cache_entries,
         opts
       ) do
    frame_cache = frame_cache_server(opts)

    Enum.reduce(source_results, {frames_by_placement, %{}}, fn {source_request, source_result},
                                                               acc ->
      materialize_source_result(
        resolve_request,
        source_request,
        source_result,
        Map.fetch!(source_keys, source_request.request_id),
        Map.get(source_result_cache_entries, source_request.request_id, %{}),
        frame_cache,
        acc
      )
    end)
  end

  defp materialize_source_result(
         %DashboardResolveRequest{} = resolve_request,
         %PlannedSourceRequest{} = source_request,
         source_result,
         %RuntimeCacheKey{} = source_key,
         source_result_cache_entry,
         frame_cache,
         {frames_acc, cache_acc}
       ) do
    Enum.reduce(source_request.consumers, {frames_acc, cache_acc}, fn consumer,
                                                                      {placement_acc,
                                                                       cache_entry_acc} ->
      placement_id = Map.fetch!(consumer, :placement_id)

      materialized =
        FrameMaterializer.materialize(source_request, source_result, consumer,
          source_result_key: source_key,
          placement_size: placement_size(resolve_request, placement_id),
          limit_context: source_request.limit_context
        )

      {frames, cache_entry} =
        materialized_frames(materialized, frame_cache, source_result_cache_entry)

      placement_frames = Map.get(placement_acc, placement_id, %PlacementFrames{})

      placement_frames =
        placement_frames
        |> append_role_frames(materialized.role, frames)
        |> append_warnings(materialized.warnings)

      {
        Map.put(placement_acc, placement_id, placement_frames),
        put_frame_cache_entry(cache_entry_acc, materialized, cache_entry)
      }
    end)
  end

  defp materialized_frames(materialized, :disabled, _source_result_cache_entry) do
    {materialized.frames,
     %{status: :disabled, key: materialized.frame_key}
     |> Map.merge(materialized_cache_provenance(materialized))}
  end

  defp materialized_frames(materialized, {:ok, server}, %{status: status})
       when status in [:stale, :facts_error] do
    :ok = RuntimeCache.put_frame(materialized.frame_key, materialized.frames, server)

    {materialized.frames,
     %{status: :refresh, key: materialized.frame_key, source_result_cache_status: status}
     |> Map.merge(materialized_cache_provenance(materialized))}
  end

  defp materialized_frames(materialized, {:ok, server}, _source_result_cache_entry) do
    case RuntimeCache.get_frame(materialized.frame_key, server) do
      {:ok, frames} ->
        {frames,
         %{status: :hit, key: materialized.frame_key}
         |> Map.merge(materialized_cache_provenance(materialized))}

      :miss ->
        :ok = RuntimeCache.put_frame(materialized.frame_key, materialized.frames, server)

        {materialized.frames,
         %{status: :miss, key: materialized.frame_key}
         |> Map.merge(materialized_cache_provenance(materialized))}
    end
  end

  defp materialized_cache_provenance(materialized) do
    %{
      capability_provenance: Map.get(materialized, :capability_provenance)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp put_cache_entry_capability_provenance(
         cache_entry,
         %PlannedSourceRequest{} = source_request
       )
       when is_map(cache_entry) do
    case capability_provenance(source_request) do
      nil -> cache_entry
      provenance -> Map.put(cache_entry, :capability_provenance, provenance)
    end
  end

  defp capability_provenance(%PlannedSourceRequest{} = source_request) do
    source_request.metadata
    |> ensure_map()
    |> Map.get(:capability_provenance)
  end

  defp maybe_put_capability_provenance(meta, nil), do: meta

  defp maybe_put_capability_provenance(meta, provenance) do
    Map.put(meta, :capability_provenance, provenance)
  end

  defp maybe_put_source_dependencies(meta, []), do: meta

  defp maybe_put_source_dependencies(meta, dependencies),
    do: Map.put(meta, :source_dependencies, dependencies)

  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_value), do: %{}

  defp put_frame_cache_entry(cache_entries, materialized, cache_entry) do
    update_in(
      cache_entries,
      [Access.key(materialized.placement_id, %{})],
      &Map.put(&1, materialized.request_id, Map.put(cache_entry, :role, materialized.role))
    )
  end

  defp append_role_frames(%PlacementFrames{} = placement_frames, :primary, frames) do
    %{placement_frames | primary: placement_frames.primary ++ frames}
  end

  defp append_role_frames(%PlacementFrames{} = placement_frames, role, frames)
       when is_atom(role) do
    overlays = Map.update(placement_frames.overlays, role, frames, &(&1 ++ frames))
    %{placement_frames | overlays: overlays}
  end

  defp source_dependencies(:limits, sampling, limit_context) do
    case limit_semantics_mode(limit_context) do
      semantics_mode when semantics_mode in [:current, :recomputed, :compare] ->
        [
          %{
            logical_source: :telemetry,
            reason: telemetry_dependency_reason(sampling),
            products: telemetry_dependency_products(sampling),
            sampling: telemetry_dependency_sampling(sampling)
          }
        ]

      _semantics_mode ->
        []
    end
  end

  defp source_dependencies(_source, _sampling, _limit_context), do: []

  defp telemetry_dependency_reason(sampling) do
    case sampling_mode(sampling) do
      mode when mode in [:latest, :latest_state] -> :limit_latest_sample_input
      _mode -> :limit_sample_history_input
    end
  end

  defp telemetry_dependency_products(sampling) do
    case sampling_mode(sampling) do
      mode when mode in [:latest, :latest_state] -> [:latest_sample]
      _mode -> [:sample_history]
    end
  end

  defp telemetry_dependency_sampling(sampling) when is_map(sampling) do
    sampling
    |> Map.take([
      :mode,
      :bucket_width_ms,
      :target_points,
      "mode",
      "bucket_width_ms",
      "target_points"
    ])
    |> put_dependency_sampling_mode(sampling_mode(sampling))
  end

  defp telemetry_dependency_sampling(_sampling), do: %{mode: :history}

  defp put_dependency_sampling_mode(sampling, mode) when mode in [:latest, :latest_state],
    do: Map.put(sampling, :mode, :latest)

  defp put_dependency_sampling_mode(sampling, _mode), do: Map.put(sampling, :mode, :history)

  defp sampling_mode(sampling) when is_map(sampling) do
    sampling
    |> get_attr(:mode)
    |> normalize_known_atom([
      :latest,
      :latest_state,
      :event_history,
      :definition_intervals,
      :analysis_buckets,
      :bounded_history,
      :raw_series,
      :bounded_raw_series
    ])
  end

  defp sampling_mode(_sampling), do: nil

  defp limit_semantics_mode(limit_context) do
    limit_context
    |> get_attr(:semantics_mode)
    |> normalize_known_atom([:observed, :current, :recomputed, :compare])
    |> case do
      nil -> :observed
      mode -> mode
    end
  end

  defp append_warnings(%PlacementFrames{} = placement_frames, warnings) do
    %{placement_frames | warnings: placement_frames.warnings ++ warnings}
  end

  defp returned_frame_count(source_results) do
    source_results
    |> Enum.map(fn {_request, result} -> length(result.frames) end)
    |> Enum.sum()
  end

  defp degraded?(source_results) do
    Enum.any?(source_results, fn {_request, result} ->
      result.meta[:degraded?] || Enum.any?(result.warnings, &(&1.severity != :info))
    end)
  end

  defp validation_warnings(%ValidationResult{} = validation) do
    errors =
      Enum.map(validation.errors, fn issue ->
        %ResolveWarning{
          code: issue.code,
          severity: :error,
          scope: :dashboard,
          details: issue.details
        }
      end)

    warnings =
      Enum.map(validation.warnings, fn issue ->
        %ResolveWarning{
          code: issue.code,
          severity: :warning,
          scope: :dashboard,
          details: issue.details
        }
      end)

    errors ++ warnings
  end

  defp validation_has_errors?(%ValidationResult{errors: errors}), do: errors != []

  defp source_request_id(placement_id, role, source) do
    Enum.join(["source_req", placement_id, Atom.to_string(role), Atom.to_string(source)], "_")
  end

  defp overlay_source_request_id(placement_id, role, source, sampling, true) do
    product =
      sampling
      |> Map.get(:products, [])
      |> List.wrap()
      |> List.first()
      |> Atom.to_string()

    Enum.join(
      ["source_req", placement_id, Atom.to_string(role), Atom.to_string(source), product],
      "_"
    )
  end

  defp overlay_source_request_id(placement_id, role, source, _sampling, false) do
    source_request_id(placement_id, role, source)
  end

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    Map.get(Map.from_struct(attrs), key)
  end

  defp get_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
