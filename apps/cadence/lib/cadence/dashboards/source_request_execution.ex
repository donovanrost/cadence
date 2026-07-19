defmodule Cadence.Dashboards.SourceRequestExecution do
  @moduledoc """
  Executes planned dashboard source requests and manages source-result caching.

  The dashboard engine owns the overall resolve lifecycle. This module owns the
  provider execution policy, failure conversion, freshness annotation, and
  cache identity needed to return source results for frame materialization.
  """

  alias Cadence.Dashboards.{
    DashboardContract,
    DashboardResolveRequest,
    DashboardResolveResult,
    DataSourceRegistry,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    RuntimeCache,
    RuntimeCacheKey,
    SourceExecutionPolicy,
    SourceFacts,
    SourceRegistry,
    SourceRequestPlanning,
    SourceResult,
    SourceResultAnnotation,
    SourceResultPreflight
  }

  @type execution_result :: %{
          source_results: [{PlannedSourceRequest.t(), SourceResult.t()}],
          source_result_cache_entries: map(),
          source_keys: map(),
          source_execution_policy: map(),
          source_execution_policies_by_request_id: map(),
          source_selection_by_request_id: map()
        }

  @spec run(DashboardResolveRequest.t(), DashboardResolveResult.t(), keyword()) ::
          execution_result()
  def run(
        %DashboardResolveRequest{} = resolve_request,
        %DashboardResolveResult{} = plan_result,
        opts
      )
      when is_list(opts) do
    source_requests = executable_source_requests(plan_result)
    freshness_now = Keyword.get_lazy(opts, :freshness_now, &DateTime.utc_now/0)
    execution_policy = SourceExecutionPolicy.resolve(opts)
    execution_policies = source_execution_policies(source_requests, opts)

    source_executions =
      execute_source_requests(
        source_requests,
        resolve_request,
        plan_result,
        freshness_now,
        execution_policy,
        execution_policies,
        opts
      )

    source_results =
      Enum.map(source_executions, fn {source_request, source_result, _cache_entry} ->
        {source_request, source_result}
      end)

    source_result_cache_entries =
      Map.new(source_executions, fn {source_request, _source_result, cache_entry} ->
        {source_request.request_id,
         SourceResultAnnotation.put_cache_entry_capability_provenance(
           cache_entry,
           source_request
         )}
      end)

    %{
      source_results: source_results,
      source_result_cache_entries: source_result_cache_entries,
      source_keys:
        source_result_keys_by_request_id(
          resolve_request,
          plan_result,
          source_results,
          source_result_cache_entries,
          opts
        ),
      source_execution_policy: SourceExecutionPolicy.metadata(execution_policy),
      source_execution_policies_by_request_id:
        source_execution_policy_metadata(execution_policies),
      source_selection_by_request_id: source_selection_by_request_id(source_results)
    }
  end

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
       SourceRegistry.execution_policy(
         source_request,
         SourceRequestPlanning.source_registry_opts(source_request, opts)
       )}
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
      |> SourceRegistry.unavailable(
        reason,
        SourceRequestPlanning.source_registry_opts(source_request, opts)
      )
      |> then(
        &SourceResultAnnotation.annotate_result(
          resolve_request,
          plan_result,
          source_request,
          &1,
          freshness_now,
          SourceRequestPlanning.source_registry_opts(source_request, opts)
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
    Enum.filter(requests, &SourceRequestPlanning.live_tick_refreshable?/1)
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
        cached_result = SourceResultAnnotation.annotate_provenance(cached_result, source_request)

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
    facts_meta = if is_map(facts.meta), do: facts.meta, else: %{}

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
    freshness_policy =
      SourceResultAnnotation.freshness_policy(
        resolve_request,
        plan_result,
        source_request,
        opts
      )

    registry_opts =
      source_request
      |> SourceRequestPlanning.source_registry_opts(opts)
      |> Keyword.put(:freshness_policy, freshness_policy)
      |> Keyword.put(:freshness_now, freshness_now)

    source_request
    |> SourceRegistry.resolve(registry_opts)
    |> validate_source_result_contract!(opts)
    |> then(
      &SourceResultAnnotation.annotate_result(
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
    freshness_policy =
      SourceResultAnnotation.freshness_policy(
        resolve_request,
        plan_result,
        source_request,
        opts
      )

    registry_opts = SourceRequestPlanning.source_registry_opts(source_request, opts)

    with {:ok, %SourceFacts{} = source_facts} <-
           SourceRegistry.facts(source_request, registry_opts) do
      source_facts =
        SourceResultAnnotation.annotate_facts(
          source_facts,
          source_request,
          freshness_policy,
          freshness_now
        )

      {:ok,
       SourceFacts.runtime_cache_key(source_request, source_facts,
         cache_policy: source_result_cache_policy(source_request),
         freshness_policy: freshness_policy
       ), source_facts}
    end
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
    registry_opts = SourceRequestPlanning.source_registry_opts(source_request, opts)
    resolved_binding = resolved_source_binding(source_request, registry_opts)

    RuntimeCacheKey.source_result(source_request,
      cache_policy: source_result_cache_policy(source_request),
      source_binding: resolved_binding && resolved_binding.binding,
      source_binding_segments:
        get_in(source_result_meta(source_result), [:source_binding_segments]),
      data_source: resolved_binding && resolved_binding.data_source,
      freshness_policy:
        SourceResultAnnotation.freshness_policy(
          resolve_request,
          plan_result,
          source_request,
          opts
        ),
      watermark: List.first(source_result.watermarks)
    )
  end

  defp source_result_meta(%{meta: meta}) when is_map(meta), do: meta
  defp source_result_meta(_source_result), do: %{}

  defp source_result_cache_policy(%PlannedSourceRequest{} = source_request) do
    if SourceRequestPlanning.source_request_snapshot?(source_request),
      do: :snapshot,
      else: :live
  end

  defp resolved_source_binding(%PlannedSourceRequest{} = source_request, opts) do
    case DataSourceRegistry.resolve(source_request, opts) do
      {:ok, %ResolvedSourceBinding{} = resolved_binding} -> resolved_binding
      {:error, _warning} -> nil
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

  defp dashboard_runtime_cache_enabled? do
    :cadence
    |> Application.get_env(:dashboard_runtime_cache, [])
    |> Keyword.get(:enabled?, true)
  end

  defp validate_source_result_contract!(%SourceResult{} = result, opts) do
    result = SourceResult.normalize(result)

    if Keyword.get(opts, :validate_dashboard_contract?, false) == true do
      result
      |> DashboardContract.validate_source_result()
      |> raise_contract_violations!(:source_result)
    end

    result
  end

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
end
