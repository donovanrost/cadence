defmodule Cadence.SemanticRuntime.PlanDecoder do
  @moduledoc "Decodes immutable Mission Model algorithm and monitoring plans for execution."

  alias Cadence.Catalog.MissionModel.RuntimePlan
  alias Cadence.SemanticRuntime.{AlgorithmPlan, MonitoringPlan, RegisteredRegistry}

  @spec decode(%{optional(atom()) => RuntimePlan.t()}, map()) :: map()
  def decode(plans, registry \\ RegisteredRegistry.configured()) when is_map(plans) do
    %{
      algorithms:
        plans
        |> Map.get(:algorithm)
        |> plan_items("algorithms", :algorithms)
        |> Enum.map(&decode_algorithm(&1, registry)),
      monitoring:
        plans
        |> Map.get(:monitoring)
        |> plan_items("policies", :policies)
        |> Enum.map(&MonitoringPlan.new/1)
    }
  end

  @spec validate(%{optional(atom()) => RuntimePlan.t()}, map()) :: :ok | {:error, term()}
  def validate(plans, registry \\ RegisteredRegistry.configured()) do
    invalid =
      plans
      |> decode(registry)
      |> Map.fetch!(:algorithms)
      |> Enum.find(fn algorithm ->
        is_map(algorithm.implementation) and
          not is_nil(value(algorithm.implementation, :authorization_error))
      end)

    case invalid do
      nil -> :ok
      algorithm -> {:error, {algorithm.algorithm_id, :registered_implementation_not_allowed}}
    end
  end

  @spec registered_execution_basis(%{optional(atom()) => RuntimePlan.t()}, map()) :: [map()]
  def registered_execution_basis(plans, registry \\ RegisteredRegistry.configured()) do
    plans
    |> decode(registry)
    |> Map.fetch!(:algorithms)
    |> Enum.flat_map(fn algorithm ->
      implementation = algorithm.implementation

      if value(implementation, :kind) in [:registered, "registered"] do
        [
          %{
            algorithm_id: algorithm.algorithm_id,
            key: value(implementation, :key),
            version: value(implementation, :version),
            artifact_sha256: value(implementation, :artifact_sha256),
            authorization_error: value(implementation, :authorization_error)
          }
        ]
      else
        []
      end
    end)
    |> Enum.sort_by(& &1.algorithm_id)
  end

  defp plan_items(nil, _string_key, _atom_key), do: []

  defp plan_items(%RuntimePlan{status: :ready, plan: plan}, string_key, atom_key),
    do: Map.get(plan, string_key, Map.get(plan, atom_key, []))

  defp plan_items(%RuntimePlan{}, _string_key, _atom_key), do: []

  defp decode_algorithm(attrs, registry) do
    plan = AlgorithmPlan.new(attrs)

    %AlgorithmPlan{
      plan
      | implementation: RegisteredRegistry.bind(plan.implementation, registry)
    }
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
