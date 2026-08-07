defmodule Cadence.Dashboards.Engine do
  @moduledoc """
  Dashboard engine planner.

  `plan/1` validates the document, expands widget contracts into logical source
  requests, batches equivalent requests, and returns placement request mappings.
  `resolve/2` executes those planned source requests through source adapters and
  fans frames back to placement buckets.
  """

  alias Cadence.Dashboards.{
    AnnotationComposition,
    Contracts,
    DashboardContract,
    DashboardResolveRequest,
    DashboardResolveResult,
    FrameMaterializer,
    LimitSelectedClockAudit,
    Management,
    Placement,
    PlacementExpansion,
    PlacementFrames,
    PlannedRequestValidation,
    PlannedSourceRequest,
    ResolveWarning,
    RuntimeCache,
    RuntimeCacheKey,
    SourceRegistry,
    SourceRequestExecution,
    SourceRequestPlanning,
    ValidationResult,
    WidgetFrameContract,
    WidgetRegistry
  }

  @spec resolve(DashboardResolveRequest.t(), keyword()) :: DashboardResolveResult.t()
  def resolve(%DashboardResolveRequest{} = request, opts \\ []) when is_list(opts) do
    request = DashboardResolveRequest.normalize(request)
    request = resolve_library_document(request)
    plan_result = plan(request, opts)

    request
    |> execute_plan(plan_result, opts)
    |> validate_resolve_contract!(opts)
  end

  @spec plan(DashboardResolveRequest.t(), keyword()) :: DashboardResolveResult.t()
  def plan(%DashboardResolveRequest{} = request, opts \\ []) when is_list(opts) do
    request = DashboardResolveRequest.normalize(request)
    request = resolve_library_document(request)
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

  defp resolve_library_document(
         %DashboardResolveRequest{document: %Cadence.Dashboards.Document{}} = request
       ) do
    %DashboardResolveRequest{
      request
      | document: Management.resolve_document(request.document)
    }
  end

  defp resolve_library_document(%DashboardResolveRequest{} = request), do: request

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
    validation = Contracts.validate_document(request.document)

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
        time: SourceRequestPlanning.time_context_metadata(request),
        snapshot?: SourceRequestPlanning.snapshot_time_context?(request),
        live_append_eligible?: SourceRequestPlanning.live_append_eligible?(request),
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

    {runtime_contexts, context_warnings} =
      SourceRequestPlanning.runtime_contexts(request, placement)

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
              |> SourceRequestPlanning.source_backed_overlay_specs(placement)
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
               [
                 PlannedRequestValidation.unsupported_widget_frame_contract_warning(
                   placement,
                   contract_details
                 )
               ]}
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

    planned_sampling =
      SourceRequestPlanning.sampling(binding, frame_spec, request, placement, widget_type)

    planned_request = %PlannedSourceRequest{
      request_id: source_request_id(placement.placement_id, role, source),
      organization_id: request.organization_id || request.document.organization_id,
      mission_id: request.mission_id || request.document.mission_id,
      logical_source: source,
      observables: Map.get(binding, :observables, []),
      scope_context: runtime_contexts.scope,
      time_context:
        SourceRequestPlanning.source_time_context(runtime_contexts.time, source, planned_sampling),
      data_context: SourceRequestPlanning.overlay_data_context(runtime_contexts.data, source),
      limit_context: runtime_contexts.limit,
      value_type: Map.get(binding, :value_type),
      sampling: planned_sampling,
      source_dependencies: source_dependencies(source, planned_sampling, runtime_contexts.limit),
      overlays: SourceRequestPlanning.unresolved_overlays(binding, widget_type),
      consumers: [
        %{
          placement_id: placement.placement_id,
          role: role,
          widget_type_id: widget_type.widget_type_id,
          annotation_layer_ids: AnnotationComposition.layer_ids(placement.widget_def)
        }
      ]
    }

    PlannedRequestValidation.validate_primary(
      planned_request,
      placement,
      frame_spec,
      SourceRequestPlanning.source_registry_opts(planned_request, opts)
    )
  end

  defp split_planned_requests(results) do
    Enum.reduce(results, {[], []}, fn
      {:ok, request}, {requests, warnings} -> {requests ++ [request], warnings}
      {:warning, warning}, {requests, warnings} -> {requests, warnings ++ [warning]}
    end)
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
      SourceRequestPlanning.overlay_samplings(
        overlay_spec,
        primary_frame_specs,
        request,
        placement,
        widget_type
      )

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
      time_context:
        SourceRequestPlanning.source_time_context(runtime_contexts.time, source, sampling),
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
          widget_type_id: widget_type.widget_type_id,
          annotation_layer_ids: AnnotationComposition.layer_ids(placement.widget_def)
        }
      ]
    }

    PlannedRequestValidation.validate_capability(
      planned_request,
      placement,
      overlay_spec,
      SourceRequestPlanning.source_registry_opts(planned_request, opts)
    )
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
    execution = SourceRequestExecution.run(request, plan_result, opts)
    source_results = execution.source_results

    limit_selected_clock_audit =
      maybe_persist_limit_selected_clock_audit_events(request, source_results, opts)

    source_result_cache_entries = execution.source_result_cache_entries
    source_keys = execution.source_keys

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
          |> Map.put(:source_execution_policy, execution.source_execution_policy)
          |> Map.put(
            :source_execution_policies_by_request_id,
            execution.source_execution_policies_by_request_id
          )
          |> Map.put(:executed_source_request_count, length(source_results))
          |> Map.put(
            :skipped_source_request_count,
            length(plan_result.planned_source_requests) - length(source_results)
          )
          |> Map.put(
            :source_selection_by_request_id,
            execution.source_selection_by_request_id
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

  defp cache_provenance(source_keys, source_result_cache_entries, frame_cache_entries) do
    %{
      source_result_keys_by_request_id: source_keys,
      source_result_cache_by_request_id: source_result_cache_entries,
      frame_keys_by_placement: frame_keys_by_placement(frame_cache_entries),
      frame_cache_by_placement: frame_cache_entries
    }
  end

  defp frame_keys_by_placement(frame_cache_entries) do
    Map.new(frame_cache_entries, fn {placement_id, entries_by_request_id} ->
      {placement_id,
       Map.new(entries_by_request_id, fn {request_id, cache_entry} ->
         {request_id, cache_entry.key}
       end)}
    end)
  end

  defp put_cache_provenance(plan_metadata, cache_provenance) do
    Map.update(plan_metadata, :cache, cache_provenance, &Map.merge(&1, cache_provenance))
  end

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
          placement_size: SourceRequestPlanning.placement_size(resolve_request, placement_id),
          limit_context: source_request.limit_context
        )

      {frames, cache_entry} =
        materialized_frames(materialized, frame_cache, source_result_cache_entry)

      placement_frames = Map.get(placement_acc, placement_id, %PlacementFrames{})

      placement_frames =
        placement_frames
        |> append_role_frames(materialized.role, frames)
        |> append_annotations(
          AnnotationComposition.select(
            materialized.annotations,
            Map.get(consumer, :annotation_layer_ids, [])
          )
        )
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

  defp append_annotations(%PlacementFrames{} = placement_frames, annotations)
       when is_list(annotations) do
    %{
      placement_frames
      | annotations: Enum.uniq_by(placement_frames.annotations ++ annotations, & &1.annotation_id)
    }
  end

  defp append_annotations(%PlacementFrames{} = placement_frames, _annotations),
    do: placement_frames

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

  defp get_attr(%_{} = attrs, key) when is_atom(key) do
    Map.get(Map.from_struct(attrs), key)
  end

  defp get_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, to_string(key)))
  end

  defp get_attr(_attrs, _key), do: nil
end
