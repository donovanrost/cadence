defmodule Cadence.Dashboards.SourceReadiness do
  @moduledoc """
  Classifies source-health evidence against the dashboard source-selection readiness policy.
  """

  @default_policy %{
    policy_id: :default,
    block_source_health: [:unavailable],
    block_freshness: [:fresh],
    block_connection_test: [:failed, :blocked]
  }
  @known_source_health [:healthy, :degraded, :unavailable, :unknown, :any]
  @known_freshness [:fresh, :stale, :missing, :any]
  @known_connection_test [:succeeded, :failed, :unsupported, :skipped, :blocked, :none, :any]
  @readiness_reasons [
    :source_unavailable,
    :source_degraded,
    :source_health_unknown,
    :connection_test_failed,
    :connection_test_blocked
  ]

  @type policy :: %{
          policy_id: atom() | binary(),
          block_source_health: [atom()],
          block_freshness: [atom()],
          block_connection_test: [atom()]
        }

  @type classification :: %{
          blocked?: boolean(),
          reasons: [atom()],
          policy_id: atom() | binary(),
          source_health: atom(),
          freshness: atom(),
          connection_test_result: atom()
        }

  @spec default_policy() :: policy()
  def default_policy, do: @default_policy

  @spec readiness_reasons() :: [atom()]
  def readiness_reasons, do: @readiness_reasons

  @spec policy(keyword()) :: policy()
  def policy(opts \\ []) when is_list(opts) do
    opts
    |> Keyword.get_lazy(:source_readiness_policy, fn ->
      :cadence
      |> Application.get_env(:dashboard_source_readiness_policy, [])
    end)
    |> normalize_policy()
  end

  @spec normalize_policy(term()) :: policy()
  def normalize_policy(policy) do
    policy = attrs_map(policy)

    %{
      policy_id: normalize_policy_id(get_policy_attr(policy, :policy_id, :default)),
      block_source_health:
        policy
        |> get_policy_attr(:block_source_health, @default_policy.block_source_health)
        |> normalize_policy_values(@known_source_health, @default_policy.block_source_health),
      block_freshness:
        policy
        |> get_policy_attr(:block_freshness, @default_policy.block_freshness)
        |> normalize_policy_values(@known_freshness, @default_policy.block_freshness),
      block_connection_test:
        policy
        |> get_policy_attr(:block_connection_test, @default_policy.block_connection_test)
        |> normalize_policy_values(
          @known_connection_test,
          @default_policy.block_connection_test
        )
    }
  end

  @spec classify(map(), policy()) :: classification()
  def classify(source_health_classification, readiness_policy \\ default_policy())
      when is_map(source_health_classification) and is_map(readiness_policy) do
    source_health = Map.get(source_health_classification, :source_health, :unknown)
    freshness = Map.get(source_health_classification, :freshness, :missing)
    connection_test_result = connection_test_result(source_health_classification)

    reasons =
      rejection_reasons(source_health, freshness, connection_test_result, readiness_policy)

    %{
      blocked?: reasons != [],
      reasons: reasons,
      policy_id: Map.get(readiness_policy, :policy_id, :default),
      source_health: source_health,
      freshness: freshness,
      connection_test_result: connection_test_result
    }
  end

  defp rejection_reasons(source_health, freshness, connection_test_result, readiness_policy) do
    []
    |> maybe_add_source_health_reason(source_health, freshness, readiness_policy)
    |> maybe_add_connection_test_reason(connection_test_result, freshness, readiness_policy)
    |> Enum.reverse()
  end

  defp maybe_add_source_health_reason(reasons, source_health, freshness, readiness_policy) do
    if source_health_policy_blocks?(source_health, freshness, readiness_policy) do
      [source_health_rejection_reason(source_health) | reasons]
    else
      reasons
    end
  end

  defp maybe_add_connection_test_reason(
         reasons,
         connection_test_result,
         freshness,
         readiness_policy
       ) do
    if connection_test_policy_blocks?(connection_test_result, freshness, readiness_policy) do
      [connection_test_rejection_reason(connection_test_result) | reasons]
    else
      reasons
    end
  end

  defp source_health_policy_blocks?(source_health, freshness, readiness_policy) do
    policy_matches_value?(Map.get(readiness_policy, :block_source_health, []), source_health) and
      policy_matches_value?(Map.get(readiness_policy, :block_freshness, []), freshness)
  end

  defp connection_test_policy_blocks?(connection_test_result, freshness, readiness_policy) do
    policy_matches_value?(
      Map.get(readiness_policy, :block_connection_test, []),
      connection_test_result
    ) and policy_matches_value?(Map.get(readiness_policy, :block_freshness, []), freshness)
  end

  defp source_health_rejection_reason(:unavailable), do: :source_unavailable
  defp source_health_rejection_reason(:degraded), do: :source_degraded
  defp source_health_rejection_reason(:unknown), do: :source_health_unknown
  defp source_health_rejection_reason(_source_health), do: :source_health_unknown

  defp connection_test_rejection_reason(:blocked), do: :connection_test_blocked
  defp connection_test_rejection_reason(_connection_test_result), do: :connection_test_failed

  defp connection_test_result(%{connection_test_result: value}),
    do: normalize_connection_test(value)

  defp connection_test_result(%{status: %{payload: payload}}) when is_map(payload) do
    payload
    |> get_policy_attr(:connection_test_result, :none)
    |> normalize_connection_test()
  end

  defp connection_test_result(_classification), do: :none

  defp normalize_connection_test(value) do
    normalize_policy_value(value, @known_connection_test) || :none
  end

  defp normalize_policy_values(values, known_values, default_values) do
    normalized =
      values
      |> List.wrap()
      |> Enum.map(&normalize_policy_value(&1, known_values))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case normalized do
      [] -> default_values
      values -> values
    end
  end

  defp normalize_policy_value(value, known_values) when is_atom(value) do
    if value in known_values, do: value, else: nil
  end

  defp normalize_policy_value(value, known_values) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("-", "_")

    Enum.find(known_values, &(Atom.to_string(&1) == normalized))
  end

  defp normalize_policy_value(_value, _known_values), do: nil

  defp normalize_policy_id(value) when is_atom(value), do: value

  defp normalize_policy_id(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
  end

  defp normalize_policy_id(_value), do: :default

  defp policy_matches_value?(values, value) do
    :any in values or value in values
  end

  defp attrs_map(attrs) when is_map(attrs), do: attrs
  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(_attrs), do: @default_policy

  defp get_policy_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
