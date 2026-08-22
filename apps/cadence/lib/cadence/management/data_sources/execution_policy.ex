defmodule Cadence.Management.DataSources.ExecutionPolicy do
  @moduledoc false

  @missing :__cadence_dashboard_policy_missing__

  @spec validate_metadata(map() | nil) :: :ok | {:error, [binary()]}
  def validate_metadata(nil), do: :ok

  def validate_metadata(metadata) when is_map(metadata) do
    case get_attr(metadata, :dashboard_policy, @missing) do
      @missing -> :ok
      policy when is_map(policy) -> validate_dashboard_policy(policy)
      _other -> {:error, ["dashboard_policy must be a map"]}
    end
  end

  def validate_metadata(_metadata), do: {:error, ["metadata must be a map"]}

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
      @missing -> errors
      value -> if validator.(value), do: errors, else: ["#{path} #{message}" | errors]
    end
  end

  defp valid_positive_integer?(value), do: is_integer(value) and value > 0
  defp valid_non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp valid_timeout?(:infinity), do: true
  defp valid_timeout?("infinity"), do: true
  defp valid_timeout?(value), do: valid_non_negative_integer?(value)

  defp get_attr(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
