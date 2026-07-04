defmodule Cadence.Dashboards.SourceExecutionPolicy do
  @moduledoc """
  Bounded execution policy for dashboard source requests.

  This policy sits above individual adapters: it caps how many planned source
  requests a dashboard resolve may execute concurrently and how long one source
  request may run before it is converted into a structured degradation result.
  """

  alias Cadence.Dashboards.{PlannedSourceRequest, ResolvedSourceBinding}

  @type source_timeout :: non_neg_integer() | :infinity

  @type t :: %__MODULE__{
          max_concurrency: pos_integer(),
          timeout_ms: source_timeout(),
          circuit_failure_threshold: pos_integer(),
          circuit_backoff_ms: non_neg_integer(),
          provenance: map()
        }

  defstruct max_concurrency: 4,
            timeout_ms: 5_000,
            circuit_failure_threshold: 3,
            circuit_backoff_ms: 30_000,
            provenance: %{}

  @default_max_concurrency 4
  @default_timeout_ms 5_000
  @default_circuit_failure_threshold 3
  @default_circuit_backoff_ms 30_000
  @missing :__cadence_dashboard_policy_missing__

  @spec resolve(keyword()) :: t()
  def resolve(opts \\ []) when is_list(opts) do
    config = app_policy() |> Map.merge(explicit_policy(opts))

    %__MODULE__{
      max_concurrency:
        config
        |> Map.get(:max_concurrency)
        |> positive_integer(@default_max_concurrency),
      timeout_ms:
        config
        |> Map.get(:timeout_ms)
        |> timeout(@default_timeout_ms),
      circuit_failure_threshold:
        config
        |> Map.get(:circuit_failure_threshold)
        |> positive_integer(@default_circuit_failure_threshold),
      circuit_backoff_ms:
        config
        |> Map.get(:circuit_backoff_ms)
        |> non_negative_integer(@default_circuit_backoff_ms),
      provenance: %{
        app_defaults?: true,
        explicit_opts?: explicit_policy(opts) != %{}
      }
    }
  end

  @spec resolve(PlannedSourceRequest.t(), ResolvedSourceBinding.t(), keyword()) :: t()
  def resolve(
        %PlannedSourceRequest{} = request,
        %ResolvedSourceBinding{} = resolved_binding,
        opts
      )
      when is_list(opts) do
    app_policy = app_policy()
    data_source_policy = metadata_policy(resolved_binding.data_source.metadata)
    binding_policy = metadata_policy(resolved_binding.binding.metadata)
    explicit_policy = explicit_policy(opts)

    config =
      app_policy
      |> Map.merge(data_source_policy)
      |> Map.merge(binding_policy)
      |> Map.merge(explicit_policy)

    %__MODULE__{
      max_concurrency:
        config
        |> Map.get(:max_concurrency)
        |> positive_integer(@default_max_concurrency),
      timeout_ms:
        config
        |> Map.get(:timeout_ms)
        |> timeout(@default_timeout_ms),
      circuit_failure_threshold:
        config
        |> Map.get(:circuit_failure_threshold)
        |> positive_integer(@default_circuit_failure_threshold),
      circuit_backoff_ms:
        config
        |> Map.get(:circuit_backoff_ms)
        |> non_negative_integer(@default_circuit_backoff_ms),
      provenance: %{
        app_defaults?: true,
        data_source_policy?: data_source_policy != %{},
        binding_policy?: binding_policy != %{},
        explicit_opts?: explicit_policy != %{},
        organization_id: request.organization_id,
        mission_id: request.mission_id,
        logical_source: request.logical_source,
        data_source_id: resolved_binding.data_source.data_source_id,
        source_binding_id: resolved_binding.binding.binding_id,
        realm: resolved_binding.realm,
        dataset: resolved_binding.dataset
      }
    }
  end

  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{} = policy) do
    %{
      max_concurrency: policy.max_concurrency,
      timeout_ms: policy.timeout_ms
    }
  end

  @spec source_metadata(t()) :: map()
  def source_metadata(%__MODULE__{} = policy) do
    %{
      timeout_ms: policy.timeout_ms,
      circuit_failure_threshold: policy.circuit_failure_threshold,
      circuit_backoff_ms: policy.circuit_backoff_ms,
      provenance: policy.provenance
    }
  end

  @spec stream_timeout([t()] | map(), t()) :: source_timeout()
  def stream_timeout(source_policies, %__MODULE__{} = fallback_policy) do
    source_policies
    |> source_policy_values()
    |> case do
      [] -> [fallback_policy]
      policies -> policies
    end
    |> Enum.map(& &1.timeout_ms)
    |> outer_timeout()
  end

  @spec validate_metadata_policy(map() | nil) :: :ok | {:error, [binary()]}
  def validate_metadata_policy(nil), do: :ok

  def validate_metadata_policy(metadata) when is_map(metadata) do
    case get_attr(metadata, :dashboard_policy, @missing) do
      @missing -> :ok
      policy when is_map(policy) -> validate_dashboard_policy(policy)
      _other -> {:error, ["dashboard_policy must be a map"]}
    end
  end

  def validate_metadata_policy(_metadata), do: {:error, ["metadata must be a map"]}

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp timeout(:infinity, _default), do: :infinity
  defp timeout("infinity", _default), do: :infinity
  defp timeout(value, _default) when is_integer(value) and value >= 0, do: value
  defp timeout(_value, default), do: default

  defp app_policy do
    execution_config =
      :cadence
      |> Application.get_env(:dashboard_source_execution, [])
      |> Map.new()
      |> normalize_policy()

    circuit_config =
      :cadence
      |> Application.get_env(:dashboard_source_circuit_breaker, [])
      |> Map.new()
      |> normalize_policy()

    %{
      max_concurrency: @default_max_concurrency,
      timeout_ms: @default_timeout_ms,
      circuit_failure_threshold: @default_circuit_failure_threshold,
      circuit_backoff_ms: @default_circuit_backoff_ms
    }
    |> Map.merge(execution_config)
    |> Map.merge(circuit_config)
  end

  defp explicit_policy(opts) do
    case Keyword.get(opts, :source_execution_policy) do
      %__MODULE__{} = policy ->
        policy_values(policy)

      _other ->
        opts
        |> Map.new()
        |> normalize_policy()
    end
  end

  defp policy_values(%__MODULE__{} = policy) do
    %{
      max_concurrency: policy.max_concurrency,
      timeout_ms: policy.timeout_ms,
      circuit_failure_threshold: policy.circuit_failure_threshold,
      circuit_backoff_ms: policy.circuit_backoff_ms
    }
  end

  defp metadata_policy(metadata) when is_map(metadata) do
    metadata
    |> get_attr(:dashboard_policy, %{})
    |> normalize_policy()
  end

  defp metadata_policy(_metadata), do: %{}

  defp normalize_policy(policy), do: normalize_policy(policy, true)

  defp normalize_policy(policy, include_nested?) when is_map(policy) do
    normalized =
      %{}
      |> maybe_put(
        :max_concurrency,
        first(policy, [:source_execution_max_concurrency, :max_concurrency])
      )
      |> maybe_put(:timeout_ms, first(policy, [:source_execution_timeout_ms, :timeout_ms]))
      |> maybe_put(
        :circuit_failure_threshold,
        first(policy, [
          :source_circuit_failure_threshold,
          :circuit_failure_threshold,
          :failure_threshold
        ])
      )
      |> maybe_put(
        :circuit_backoff_ms,
        first(policy, [:source_circuit_backoff_ms, :circuit_backoff_ms, :backoff_ms])
      )

    if include_nested? do
      normalized
      |> Map.merge(nested_execution_policy(policy))
      |> Map.merge(nested_circuit_policy(policy))
    else
      normalized
    end
  end

  defp normalize_policy(_policy, _include_nested?), do: %{}

  defp nested_execution_policy(policy) do
    policy
    |> get_attr(:execution, %{})
    |> normalize_policy(false)
    |> Map.take([:max_concurrency, :timeout_ms])
  end

  defp nested_circuit_policy(policy) do
    policy
    |> get_attr(:circuit_breaker, %{})
    |> normalize_policy(false)
    |> Map.take([:circuit_failure_threshold, :circuit_backoff_ms])
  end

  defp first(policy, keys) do
    Enum.find_value(keys, &get_attr(policy, &1))
  end

  defp get_attr(attrs, key, default \\ nil) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp maybe_put(policy, _key, nil), do: policy
  defp maybe_put(policy, key, value), do: Map.put(policy, key, value)

  defp validate_dashboard_policy(policy) do
    errors =
      []
      |> validate_execution_fields(policy, "dashboard_policy")
      |> validate_circuit_fields(policy, "dashboard_policy")
      |> validate_nested_policy(
        policy,
        :execution,
        "dashboard_policy.execution",
        &validate_execution_fields/3
      )
      |> validate_nested_policy(
        policy,
        :circuit_breaker,
        "dashboard_policy.circuit_breaker",
        &validate_circuit_fields/3
      )
      |> Enum.reverse()

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp validate_execution_fields(errors, policy, path) do
    errors
    |> validate_value(
      policy,
      :source_execution_max_concurrency,
      "#{path}.source_execution_max_concurrency",
      &valid_positive_integer?/1,
      "must be a positive integer"
    )
    |> validate_value(
      policy,
      :max_concurrency,
      "#{path}.max_concurrency",
      &valid_positive_integer?/1,
      "must be a positive integer"
    )
    |> validate_value(
      policy,
      :source_execution_timeout_ms,
      "#{path}.source_execution_timeout_ms",
      &valid_timeout?/1,
      "must be a non-negative integer or \"infinity\""
    )
    |> validate_value(
      policy,
      :timeout_ms,
      "#{path}.timeout_ms",
      &valid_timeout?/1,
      "must be a non-negative integer or \"infinity\""
    )
  end

  defp validate_circuit_fields(errors, policy, path) do
    errors
    |> validate_value(
      policy,
      :source_circuit_failure_threshold,
      "#{path}.source_circuit_failure_threshold",
      &valid_positive_integer?/1,
      "must be a positive integer"
    )
    |> validate_value(
      policy,
      :circuit_failure_threshold,
      "#{path}.circuit_failure_threshold",
      &valid_positive_integer?/1,
      "must be a positive integer"
    )
    |> validate_value(
      policy,
      :failure_threshold,
      "#{path}.failure_threshold",
      &valid_positive_integer?/1,
      "must be a positive integer"
    )
    |> validate_value(
      policy,
      :source_circuit_backoff_ms,
      "#{path}.source_circuit_backoff_ms",
      &valid_non_negative_integer?/1,
      "must be a non-negative integer"
    )
    |> validate_value(
      policy,
      :circuit_backoff_ms,
      "#{path}.circuit_backoff_ms",
      &valid_non_negative_integer?/1,
      "must be a non-negative integer"
    )
    |> validate_value(
      policy,
      :backoff_ms,
      "#{path}.backoff_ms",
      &valid_non_negative_integer?/1,
      "must be a non-negative integer"
    )
  end

  defp validate_nested_policy(errors, policy, key, path, validator) do
    case get_attr(policy, key, @missing) do
      @missing -> errors
      nested_policy when is_map(nested_policy) -> validator.(errors, nested_policy, path)
      _other -> ["#{path} must be a map" | errors]
    end
  end

  defp validate_value(errors, policy, key, path, validator, message) do
    case get_attr(policy, key, @missing) do
      @missing ->
        errors

      value ->
        if validator.(value), do: errors, else: ["#{path} #{message}" | errors]
    end
  end

  defp valid_positive_integer?(value), do: is_integer(value) and value > 0
  defp valid_non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp valid_timeout?(:infinity), do: true
  defp valid_timeout?("infinity"), do: true
  defp valid_timeout?(value), do: valid_non_negative_integer?(value)

  defp source_policy_values(source_policies) when is_map(source_policies),
    do: Map.values(source_policies)

  defp source_policy_values(source_policies) when is_list(source_policies),
    do: source_policies

  defp outer_timeout(timeouts) do
    if Enum.any?(timeouts, &(&1 == :infinity)) do
      :infinity
    else
      timeouts
      |> Enum.max(fn -> @default_timeout_ms end)
      |> Kernel.+(1_000)
    end
  end
end
