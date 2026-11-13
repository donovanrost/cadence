defmodule Cadence.Dashboards.SourceRegistry.ExecutionMonitoring do
  @moduledoc """
  Applies circuit-breaker and source-health monitoring around source execution.
  """

  alias Cadence.Dashboards.{
    PlannedSourceRequest,
    ResolvedSourceBinding,
    SourceCircuitBreaker,
    SourceExecutionPolicy,
    SourceResult
  }

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  # Sources whose storage is Cadence's own Postgres: a database failure there is the source.
  @postgres_backed_kinds ["postgres", "projection"]

  @doc """
  The failure an exception raised while resolving a source stands for. Cadence's own Postgres
  failing (a pool or connection error) under a source that isn't Postgres-backed is
  `{:platform_store, exception}`: the platform under load, not the source down, so it neither
  trips the source circuit nor records source health. Anything else is `{:exception, exception}`.
  """
  @spec exception_reason(Exception.t(), ResolvedSourceBinding.t()) ::
          {:platform_store | :exception, Exception.t()}
  def exception_reason(exception, %ResolvedSourceBinding{data_source: data_source}) do
    if platform_store_exception?(exception) and
         to_string(data_source.kind) not in @postgres_backed_kinds,
       do: {:platform_store, exception},
       else: {:exception, exception}
  end

  @doc """
  The failure a timed-out or exited source execution stands for: a read task killed while it
  waited on Cadence's own Postgres (`{:platform_store_timeout, ms}`, see `blocked_on/1`) under a
  source that isn't Postgres-backed stays a platform-store failure; under a Postgres-backed one
  it's the source timing out.
  """
  @spec failure_reason(term(), ResolvedSourceBinding.t()) :: term()
  def failure_reason({:platform_store_timeout, ms}, %ResolvedSourceBinding{data_source: source}) do
    if to_string(source.kind) in @postgres_backed_kinds,
      do: {:timeout, ms},
      else: {:platform_store_timeout, ms}
  end

  def failure_reason(reason, _resolved_binding), do: reason

  @doc """
  What a still-running read task is blocked on: `:platform_store` while it waits on a Cadence
  Postgres connection or query (DBConnection/Postgrex on its stack; QuestDB is read over HTTP),
  else `:source`. Read just before the task is killed for its timeout.
  """
  @spec blocked_on(pid()) :: :platform_store | :source
  def blocked_on(pid) when is_pid(pid) do
    case Process.info(pid, :current_stacktrace) do
      {:current_stacktrace, stack} ->
        if Enum.any?(stack, &platform_store_frame?/1), do: :platform_store, else: :source

      nil ->
        :source
    end
  end

  defp platform_store_frame?({module, _fun, _arity, _location}) do
    name = Atom.to_string(module)

    String.starts_with?(name, "Elixir.DBConnection") or
      String.starts_with?(name, "Elixir.Postgrex")
  end

  @doc "Marks a source-unavailable warning's details with the platform-store cause."
  @spec put_cause(map(), term()) :: map()
  def put_cause(details, {kind, _detail}) when kind in [:platform_store, :platform_store_timeout],
    do: Map.put(details, :cause, :platform_store)

  def put_cause(details, _reason), do: details

  defp platform_store_exception?(%DBConnection.ConnectionError{}), do: true
  defp platform_store_exception?(%Postgrex.Error{}), do: true
  defp platform_store_exception?(_exception), do: false

  @spec allow(
          PlannedSourceRequest.t(),
          ResolvedSourceBinding.t(),
          SourceExecutionPolicy.t(),
          keyword()
        ) :: {:allow, map()} | {:blocked, map()}
  def allow(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
        %SourceExecutionPolicy{} = source_policy,
        opts
      )
      when is_list(opts) do
    source_key = SourceCircuitBreaker.source_key(request, resolved_binding)

    case source_circuit_breaker(opts) do
      {:ok, server} ->
        SourceCircuitBreaker.allow?(server, source_key, source_circuit_opts(opts, source_policy))

      :disabled ->
        {:allow, %{}}
    end
  end

  @spec record_result(
          PlannedSourceRequest.t(),
          ResolvedSourceBinding.t(),
          SourceResult.t(),
          SourceExecutionPolicy.t(),
          keyword()
        ) :: :ok
  def record_result(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
        %SourceResult{} = result,
        %SourceExecutionPolicy{} = source_policy,
        opts
      )
      when is_list(opts) do
    case source_failure_reason(result) do
      # Cadence's own Postgres failed, not the source: neither the circuit nor health hears of it.
      :platform_store ->
        :ok

      failure_reason ->
        record(request, resolved_binding, result, failure_reason, source_policy, opts)
    end
  end

  defp record(request, resolved_binding, result, failure_reason, source_policy, opts) do
    source_key = SourceCircuitBreaker.source_key(request, resolved_binding)

    circuit_status =
      case source_circuit_breaker(opts) do
        {:ok, server} ->
          record_circuit_result(server, source_key, failure_reason, source_policy, opts)

        :disabled ->
          nil
      end

    record_health(request, resolved_binding, result, failure_reason, circuit_status, opts)
  end

  @spec record_health(
          PlannedSourceRequest.t(),
          ResolvedSourceBinding.t(),
          SourceResult.t(),
          term(),
          map() | nil,
          keyword()
        ) :: :ok
  def record_health(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
        %SourceResult{} = result,
        failure_reason,
        circuit_status,
        opts
      )
      when is_list(opts) do
    if source_health_recording_enabled?(opts) do
      do_record_source_health(
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

  @spec health_attributes(
          PlannedSourceRequest.t(),
          ResolvedSourceBinding.t(),
          atom(),
          atom()
        ) :: map()
  def health_attributes(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
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

  defp record_circuit_result(server, source_key, nil, source_policy, opts) do
    :ok =
      SourceCircuitBreaker.record_success(
        server,
        source_key,
        source_circuit_opts(opts, source_policy)
      )

    nil
  end

  defp record_circuit_result(server, source_key, reason, source_policy, opts) do
    SourceCircuitBreaker.record_failure(
      server,
      source_key,
      reason,
      source_circuit_opts(opts, source_policy)
    )
  end

  defp source_circuit_breaker(opts) do
    case Keyword.fetch(opts, :source_circuit_breaker?) do
      {:ok, false} ->
        :disabled

      {:ok, true} ->
        case Keyword.get(opts, :source_circuit_breaker) do
          nil -> :disabled
          server -> {:ok, server}
        end

      :error ->
        case Keyword.get(opts, :source_circuit_breaker) do
          nil -> configured_source_circuit_breaker()
          server -> {:ok, server}
        end
    end
  end

  defp configured_source_circuit_breaker do
    if dashboard_source_circuit_breaker_enabled?() and Process.whereis(SourceCircuitBreaker) do
      {:ok, SourceCircuitBreaker}
    else
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
      %{details: %{cause: :platform_store}} -> :platform_store
      warning -> warning.code
    end
  end

  defp do_record_source_health(
         %PlannedSourceRequest{} = request,
         %ResolvedSourceBinding{} = resolved_binding,
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
      |> health_attributes(resolved_binding, source_health, reason)
      |> Map.put(:payload, source_health_payload(result, circuit_status))

    case SourceHealth.maybe_record_source_health(attrs, opts) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp source_health_recording_enabled?(opts) do
    case Keyword.fetch(opts, :record_source_health_events?) do
      {:ok, enabled?} -> enabled?
      :error -> SourceHealth.enabled?(opts)
    end
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
end
