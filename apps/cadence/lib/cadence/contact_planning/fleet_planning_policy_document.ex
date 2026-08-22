defmodule Cadence.ContactPlanning.FleetPlanningPolicyDocument do
  @moduledoc "Strict normalization for deterministic fleet-planning policy documents."

  alias Cadence.Persistence.JsonDocument

  @maximum_horizon_seconds 31 * 24 * 60 * 60
  @maximum_concurrency 64
  @maximum_weight 10_000
  @maximum_cost_micros 9_000_000_000_000_000

  @horizon_fields ~w(
    max_horizon_seconds requirement_concurrency provider_search_concurrency
    reuse_freshness_seconds
  )
  @scoring_fields ~w(
    priority_weight deadline_weight scarcity_weight preferred_duration_weight
    volume_weight confidence_weight cost_efficiency_weight diversity_weight
    fragmentation_penalty expiry_risk_penalty local_improvement_limit
    local_improvement_width
  )
  @resource_fields ~w(default_exclusive_capacity capacities)
  @budget_fields ~w(
    max_contacts max_estimated_cost_micros currency per_provider
    critical_contact_reserve critical_cost_reserve_micros
  )
  @redundancy_fields ~w(
    distinct_provider_required distinct_station_required distinct_service_pool_required
  )
  @automation_fields ~w(
    mode execution_concurrency max_repair_attempts repair_horizon_seconds
    automatic_submission
  )
  @provider_budget_fields ~w(max_contacts max_estimated_cost_micros)

  @spec normalize_horizon(map()) :: {:ok, map()} | {:error, term()}
  def normalize_horizon(document) do
    with {:ok, document} <- object(document, :horizon),
         :ok <- reject_unknown(document, @horizon_fields, :horizon),
         {:ok, max_horizon} <-
           bounded_positive(
             document,
             "max_horizon_seconds",
             7 * 24 * 60 * 60,
             60,
             @maximum_horizon_seconds
           ),
         {:ok, requirement_concurrency} <-
           bounded_positive(document, "requirement_concurrency", 8, 1, @maximum_concurrency),
         {:ok, provider_concurrency} <-
           bounded_positive(
             document,
             "provider_search_concurrency",
             4,
             1,
             @maximum_concurrency
           ),
         {:ok, freshness} <-
           bounded_non_negative(
             document,
             "reuse_freshness_seconds",
             0,
             @maximum_horizon_seconds
           ) do
      {:ok,
       %{
         "max_horizon_seconds" => max_horizon,
         "requirement_concurrency" => requirement_concurrency,
         "provider_search_concurrency" => provider_concurrency,
         "reuse_freshness_seconds" => freshness
       }}
    end
  end

  @spec normalize_scoring(map()) :: {:ok, map()} | {:error, term()}
  def normalize_scoring(document) do
    defaults = %{
      "priority_weight" => 1_000,
      "deadline_weight" => 800,
      "scarcity_weight" => 600,
      "preferred_duration_weight" => 300,
      "volume_weight" => 300,
      "confidence_weight" => 200,
      "cost_efficiency_weight" => 100,
      "diversity_weight" => 200,
      "fragmentation_penalty" => 100,
      "expiry_risk_penalty" => 200
    }

    with {:ok, document} <- object(document, :scoring),
         :ok <- reject_unknown(document, @scoring_fields, :scoring),
         {:ok, weights} <- normalize_weights(document, defaults),
         {:ok, improvement_limit} <-
           bounded_non_negative(document, "local_improvement_limit", 100, 10_000),
         {:ok, improvement_width} <-
           bounded_positive(document, "local_improvement_width", 3, 1, 8) do
      {:ok,
       weights
       |> Map.put("local_improvement_limit", improvement_limit)
       |> Map.put("local_improvement_width", improvement_width)}
    end
  end

  @spec normalize_resources(map()) :: {:ok, map()} | {:error, term()}
  def normalize_resources(document) do
    with {:ok, document} <- object(document, :resources),
         :ok <- reject_unknown(document, @resource_fields, :resources),
         {:ok, default_capacity} <-
           bounded_positive(document, "default_exclusive_capacity", 1, 1, 1_000),
         {:ok, capacities} <- capacities(Map.get(document, "capacities", %{})) do
      {:ok,
       %{
         "default_exclusive_capacity" => default_capacity,
         "capacities" => capacities
       }}
    end
  end

  @spec normalize_budgets(map()) :: {:ok, map()} | {:error, term()}
  def normalize_budgets(document) do
    with {:ok, document} <- object(document, :budgets),
         :ok <- reject_unknown(document, @budget_fields, :budgets),
         {:ok, max_contacts} <- optional_positive(document, "max_contacts", 1_000_000),
         {:ok, max_cost} <-
           optional_non_negative(
             document,
             "max_estimated_cost_micros",
             @maximum_cost_micros
           ),
         {:ok, currency} <- currency(Map.get(document, "currency")),
         :ok <- cost_currency_consistent(max_cost, currency),
         {:ok, critical_contacts} <-
           bounded_non_negative(document, "critical_contact_reserve", 0, 1_000_000),
         {:ok, critical_cost} <-
           bounded_non_negative(
             document,
             "critical_cost_reserve_micros",
             0,
             @maximum_cost_micros
           ),
         :ok <- reserve_consistent(critical_contacts, max_contacts, "critical_contact_reserve"),
         :ok <-
           reserve_consistent(
             critical_cost,
             max_cost,
             "critical_cost_reserve_micros"
           ),
         {:ok, providers} <- provider_budgets(Map.get(document, "per_provider", %{}), currency) do
      {:ok,
       %{
         "max_contacts" => max_contacts,
         "max_estimated_cost_micros" => max_cost,
         "currency" => currency,
         "per_provider" => providers,
         "critical_contact_reserve" => critical_contacts,
         "critical_cost_reserve_micros" => critical_cost
       }}
    end
  end

  @spec normalize_redundancy(map()) :: {:ok, map()} | {:error, term()}
  def normalize_redundancy(document) do
    with {:ok, document} <- object(document, :redundancy),
         :ok <- reject_unknown(document, @redundancy_fields, :redundancy),
         {:ok, provider} <- boolean(document, "distinct_provider_required", false),
         {:ok, station} <- boolean(document, "distinct_station_required", false),
         {:ok, service_pool} <-
           boolean(document, "distinct_service_pool_required", false) do
      {:ok,
       %{
         "distinct_provider_required" => provider,
         "distinct_station_required" => station,
         "distinct_service_pool_required" => service_pool
       }}
    end
  end

  @spec normalize_automation(map()) :: {:ok, map()} | {:error, term()}
  def normalize_automation(document) do
    with {:ok, document} <- object(document, :automation),
         :ok <- reject_unknown(document, @automation_fields, :automation),
         {:ok, mode} <-
           member(
             document,
             "mode",
             ~w(advisory approval_required bounded_automatic),
             "advisory"
           ),
         {:ok, execution_concurrency} <-
           bounded_positive(document, "execution_concurrency", 4, 1, @maximum_concurrency),
         {:ok, repair_attempts} <-
           bounded_non_negative(document, "max_repair_attempts", 3, 100),
         {:ok, repair_horizon} <-
           bounded_positive(
             document,
             "repair_horizon_seconds",
             24 * 60 * 60,
             60,
             @maximum_horizon_seconds
           ),
         {:ok, automatic_submission} <-
           boolean(document, "automatic_submission", false),
         :ok <- validate_automatic_submission(mode, automatic_submission) do
      {:ok,
       %{
         "mode" => mode,
         "execution_concurrency" => execution_concurrency,
         "max_repair_attempts" => repair_attempts,
         "repair_horizon_seconds" => repair_horizon,
         "automatic_submission" => automatic_submission
       }}
    end
  end

  defp normalize_weights(document, defaults) do
    Enum.reduce_while(defaults, {:ok, %{}}, fn {field, default}, {:ok, result} ->
      case bounded_non_negative(document, field, default, @maximum_weight) do
        {:ok, value} -> {:cont, {:ok, Map.put(result, field, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp capacities(value) when is_map(value) do
    value
    |> JsonDocument.encode()
    |> Enum.reduce_while({:ok, %{}}, fn {key, capacity}, {:ok, result} ->
      if key != "" and is_integer(capacity) and capacity > 0 and capacity <= 1_000 do
        {:cont, {:ok, Map.put(result, key, capacity)}}
      else
        {:halt, invalid(:resources, "capacities")}
      end
    end)
  end

  defp capacities(_value), do: invalid(:resources, "capacities")

  defp provider_budgets(value, currency) when is_map(value) do
    value
    |> JsonDocument.encode()
    |> Enum.reduce_while({:ok, %{}}, fn {provider_id, budget}, {:ok, result} ->
      case normalize_provider_budget(provider_id, budget, currency) do
        {:ok, normalized} -> {:cont, {:ok, Map.put(result, provider_id, normalized)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp provider_budgets(_value, _currency), do: invalid(:budgets, "per_provider")

  defp normalize_provider_budget(provider_id, budget, currency)
       when is_binary(provider_id) and provider_id != "" and is_map(budget) do
    budget = JsonDocument.encode(budget)

    with :ok <- reject_unknown(budget, @provider_budget_fields, :budgets),
         {:ok, max_contacts} <- optional_positive(budget, "max_contacts", 1_000_000),
         {:ok, max_cost} <-
           optional_non_negative(budget, "max_estimated_cost_micros", @maximum_cost_micros),
         :ok <- cost_currency_consistent(max_cost, currency) do
      {:ok,
       %{
         "max_contacts" => max_contacts,
         "max_estimated_cost_micros" => max_cost
       }}
    end
  end

  defp normalize_provider_budget(_provider_id, _budget, _currency),
    do: invalid(:budgets, "per_provider")

  defp reject_unknown(document, known, section) do
    case Map.keys(document) -- known do
      [] -> :ok
      [field | _rest] -> {:error, {:unknown_fleet_planning_policy_field, section, field}}
    end
  end

  defp object(value, _section) when is_map(value), do: {:ok, JsonDocument.encode(value)}
  defp object(_value, section), do: {:error, {:invalid_fleet_planning_policy_section, section}}

  defp bounded_positive(document, key, default, minimum, maximum) do
    case Map.get(document, key, default) do
      value when is_integer(value) and value >= minimum and value <= maximum -> {:ok, value}
      _value -> invalid(:value, key)
    end
  end

  defp bounded_non_negative(document, key, default, maximum) do
    case Map.get(document, key, default) do
      value when is_integer(value) and value >= 0 and value <= maximum -> {:ok, value}
      _value -> invalid(:value, key)
    end
  end

  defp optional_positive(document, key, maximum) do
    case Map.get(document, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value > 0 and value <= maximum -> {:ok, value}
      _value -> invalid(:value, key)
    end
  end

  defp optional_non_negative(document, key, maximum) do
    case Map.get(document, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= 0 and value <= maximum -> {:ok, value}
      _value -> invalid(:value, key)
    end
  end

  defp boolean(document, key, default) do
    case Map.get(document, key, default) do
      value when is_boolean(value) -> {:ok, value}
      _value -> invalid(:value, key)
    end
  end

  defp member(document, key, allowed, default) do
    value = Map.get(document, key, default)
    if value in allowed, do: {:ok, value}, else: invalid(:value, key)
  end

  defp currency(nil), do: {:ok, nil}

  defp currency(value) when is_binary(value) do
    normalized = String.upcase(value)

    if normalized =~ ~r/\A[A-Z]{3}\z/,
      do: {:ok, normalized},
      else: invalid(:budgets, "currency")
  end

  defp currency(_value), do: invalid(:budgets, "currency")

  defp cost_currency_consistent(nil, _currency), do: :ok
  defp cost_currency_consistent(_cost, currency) when is_binary(currency), do: :ok
  defp cost_currency_consistent(_cost, nil), do: invalid(:budgets, "currency")

  defp reserve_consistent(0, _maximum, _field), do: :ok

  defp reserve_consistent(reserve, maximum, _field)
       when is_integer(maximum) and reserve <= maximum,
       do: :ok

  defp reserve_consistent(_reserve, _maximum, field), do: invalid(:budgets, field)

  defp validate_automatic_submission("advisory", true),
    do: {:error, :advisory_policy_cannot_submit_automatically}

  defp validate_automatic_submission(_mode, _automatic_submission), do: :ok

  defp invalid(section, key),
    do: {:error, {:invalid_fleet_planning_policy_field, section, key}}
end
