defmodule Cadence.Dashboards.SourceRegistry.SampleInspection do
  @moduledoc """
  Executes physical telemetry inspection against a previously resolved binding.

  The caller must authorize the request and obtain this exact binding from source
  resolution. This path never resolves the current default again. Credentials
  remain execution-only, and adapter exceptions become finite error outcomes.
  """

  alias Cadence.Dashboards.{
    DataContext,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceExecutionPolicy,
    SourceResult
  }

  alias Cadence.Dashboards.SourceRegistry.{AdapterOptions, AdapterSelection, ExecutionMonitoring}
  alias Cadence.Dashboards.Sources.Telemetry.PhysicalSampleRequest
  alias Cadence.Telemetry.{PhysicalSampleQuery, Sample}

  @doc "Optional source-adapter contract; implementations must enforce stored tenant identity."
  @callback inspect_sample(PhysicalSampleQuery.t(), keyword()) ::
              {:ok, %{organization_id: binary(), sample: Sample.t()}} | {:error, term()}

  def fetch(request, resolved, selection, opts \\ [])

  def fetch(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved,
        selection,
        opts
      )
      when is_list(opts) do
    with :ok <- binding_context(request, resolved),
         {:ok, query} <- PhysicalSampleRequest.build(request, resolved, selection),
         {:ok, adapter} <- adapter(resolved, opts) do
      policy = SourceExecutionPolicy.resolve(request, resolved, opts)

      case ExecutionMonitoring.allow(request, resolved, policy, opts) do
        {:blocked, _} ->
          {:error, :physical_sample_source_degraded}

        {:allow, _} ->
          result = bounded_fetch(adapter, request, resolved, query, policy, opts)
          record(result, request, resolved, policy, opts)
          result
      end
    end
  rescue
    _ -> {:error, :physical_sample_unavailable}
  catch
    _, _ -> {:error, :physical_sample_unavailable}
  end

  def fetch(_, _, _, _), do: {:error, :invalid_physical_sample_selection}

  @doc "Inspects all captured segments under one request budget; uncertainty is not a unique match."
  def fetch_many(request, resolved, selection, opts \\ [])

  def fetch_many(%PlannedSourceRequest{} = request, resolved, selection, opts)
      when is_list(resolved) and length(resolved) in 1..64 and is_list(opts) do
    policy = SourceExecutionPolicy.resolve(opts)

    bounded(
      fn ->
        Enum.reduce_while(resolved, {:error, :not_found}, fn binding, found ->
          merge_match(found, fetch(request, binding, selection, opts))
        end)
      end,
      policy.timeout_ms
    )
  rescue
    _ -> {:error, :physical_sample_unavailable}
  catch
    _, _ -> {:error, :physical_sample_unavailable}
  end

  def fetch_many(_, _, _, _), do: {:error, :missing_physical_sample_binding}

  defp merge_match(found, {:error, :not_found}), do: {:cont, found}
  defp merge_match({:error, :not_found}, {:ok, sample}), do: {:cont, {:ok, sample}}
  defp merge_match({:ok, sample}, {:ok, sample}), do: {:cont, {:ok, sample}}
  defp merge_match({:ok, _}, {:ok, _}), do: {:halt, {:error, :ambiguous_physical_sample}}
  defp merge_match(_, {:error, _} = error), do: {:halt, error}

  defp binding_context(request, resolved) do
    binding = resolved.binding
    source = resolved.data_source

    valid =
      binding.logical_source == request.logical_source and
        binding.data_source_id == source.data_source_id and
        to_string(binding.realm) == to_string(resolved.realm) and
        binding.dataset == resolved.dataset and
        Enum.all?([binding, source], fn owner ->
          owner.organization_id in [nil, request.organization_id] and
            owner.mission_id in [nil, request.mission_id]
        end) and requested_source?(request, resolved)

    if valid, do: :ok, else: {:error, :physical_sample_context_mismatch}
  end

  defp requested_source?(request, resolved) do
    expected = %{
      realm: resolved.realm,
      data_source_id: resolved.data_source.data_source_id,
      source_binding_id: resolved.binding.binding_id,
      dataset: resolved.dataset
    }

    Enum.all?(expected, fn {key, value} ->
      actual = DataContext.source_value(request.data_context, request.logical_source, key)

      is_nil(actual) or (key == :realm and to_string(actual) == to_string(value)) or
        actual == value
    end)
  end

  defp adapter(resolved, opts) do
    with {:ok, adapter} <- AdapterSelection.for_binding(resolved, opts),
         {:module, ^adapter} <- Code.ensure_loaded(adapter),
         true <- function_exported?(adapter, :inspect_sample, 2) do
      {:ok, adapter}
    else
      _ -> {:error, :unsupported_sample_inspection}
    end
  end

  defp bounded_fetch(adapter, request, resolved, query, policy, opts) do
    bounded(fn -> execute(adapter, request, resolved, query, opts) end, policy.timeout_ms)
  end

  defp bounded(fun, timeout) do
    # A request-owned supervisor keeps even an untrappable adapter kill from
    # killing the caller, and shuts down its worker if the caller disappears.
    {:ok, supervisor} = Task.Supervisor.start_link()

    try do
      task =
        Task.Supervisor.async_nolink(supervisor, fun)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        {:exit, _} -> {:error, :physical_sample_unavailable}
        nil -> {:error, :physical_sample_timeout}
      end
    after
      Supervisor.stop(supervisor)
    end
  end

  defp execute(adapter, request, resolved, query, opts) do
    case AdapterOptions.build(request, resolved, opts, nil) do
      {:ok, adapter_opts} ->
        adapter.inspect_sample(query, adapter_opts)
        |> validate_result(query)

      _ ->
        {:error, :physical_sample_unavailable}
    end
  rescue
    _ -> {:error, :physical_sample_unavailable}
  catch
    _, _ -> {:error, :physical_sample_unavailable}
  end

  defp validate_result(
         {:ok, %{organization_id: organization_id, sample: %Sample{} = sample}},
         query
       ) do
    if PhysicalSampleQuery.matches?(query, sample, organization_id),
      do: {:ok, sample},
      else: {:error, :physical_sample_context_mismatch}
  end

  defp validate_result({:error, reason}, _query)
       when reason in [
              :not_found,
              :ambiguous_physical_sample,
              :physical_sample_context_mismatch,
              :invalid_physical_sample_result,
              :invalid_physical_sample_query,
              :missing_physical_sample_policy,
              :unsupported_sample_inspection
            ],
       do: {:error, reason}

  defp validate_result({:error, {:unsupported_history_capability, _, :fetch_sample}}, _query),
    do: {:error, :unsupported_sample_inspection}

  defp validate_result({:error, _}, _query), do: {:error, :physical_sample_unavailable}
  defp validate_result(_, _query), do: {:error, :invalid_physical_sample_result}

  defp record({:error, reason}, _request, _resolved, _policy, _opts)
       when reason in [:unsupported_sample_inspection, :missing_physical_sample_policy], do: :ok

  defp record(result, request, resolved, policy, opts) do
    warnings =
      case result do
        {:ok, _} ->
          []

        {:error, :not_found} ->
          []

        {:error, reason} ->
          [
            %ResolveWarning{
              code: :source_unavailable,
              severity: :error,
              scope: :dashboard,
              message: "Physical sample inspection failed",
              details: %{reason: reason}
            }
          ]
      end

    ExecutionMonitoring.record_result(
      request,
      resolved,
      SourceResult.new(%{request_id: request.request_id, warnings: warnings}),
      policy,
      opts
    )
  end
end
