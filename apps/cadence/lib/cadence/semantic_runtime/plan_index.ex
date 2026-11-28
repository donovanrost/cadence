defmodule Cadence.SemanticRuntime.PlanIndex do
  @moduledoc """
  What the semantic runtime asks of a compiled plan, by key (#451 T1): the monitoring plans of a
  parameter, the algorithms that read a parameter as an input, the algorithms of an id.

  The runtime used to be handed lists and to scan every monitoring plan and every algorithm for
  each update, after the partition had decoded the whole plan for each batch. An index answers the
  same questions without a scan, in two forms with the same answers:

  - **From a plan map** (`from_plan/1`, `wrap/1`): the lists grouped once into maps. For the
    callers that hold a decoded plan (replay, comparison, tests); the cost is one pass over the plan
    per call, as the scans were.
  - **From the node cache** (`from_cache/2`): a plan id and the node's `MonitoringPlanCache` table;
    every question is one ETS read that copies the plans of that parameter, never the catalog. A
    partition holds only this (the table and the id), whatever the size of the plan.

  Every list answers in the plan's own order, so a result does not depend on which form served it.
  """

  alias Cadence.SemanticRuntime.{AlgorithmPlan, MonitoringPlan}

  @type t :: %__MODULE__{
          monitoring: %{optional(binary()) => [MonitoringPlan.t()]},
          algorithms_by_input: %{optional(binary()) => [AlgorithmPlan.t()]},
          algorithms_by_id: %{optional(binary()) => [AlgorithmPlan.t()]},
          table: :ets.table() | nil,
          plan_id: term(),
          empty?: boolean()
        }

  defstruct monitoring: %{},
            algorithms_by_input: %{},
            algorithms_by_id: %{},
            table: nil,
            plan_id: nil,
            empty?: true

  @doc "An index over an ETS table filled by `MonitoringPlanCache`, for `plan_id`."
  @spec from_cache(:ets.table(), term(), boolean()) :: t()
  def from_cache(table, plan_id, empty? \\ false),
    do: %__MODULE__{table: table, plan_id: plan_id, empty?: empty?}

  @doc "An index over a plan map (`%{algorithms: [...], monitoring: [...]}`) or an index."
  @spec wrap(map() | t()) :: t()
  def wrap(%__MODULE__{} = index), do: index
  def wrap(plan) when is_map(plan), do: from_plan(plan)

  @spec from_plan(map()) :: t()
  def from_plan(plan) when is_map(plan) do
    algorithms = plan |> Map.get(:algorithms, []) |> Enum.map(&algorithm/1)
    monitoring = plan |> Map.get(:monitoring, []) |> Enum.map(&monitoring_plan/1)

    %__MODULE__{
      monitoring: Enum.group_by(monitoring, & &1.parameter_id),
      algorithms_by_input: by_input(algorithms),
      algorithms_by_id: Enum.group_by(algorithms, & &1.algorithm_id),
      empty?: algorithms == [] and monitoring == []
    }
  end

  @doc "True when the plan has no algorithm and no monitoring plan."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{empty?: empty?}), do: empty?

  @doc """
  The monitoring plans of a parameter as `spacecraft_id` runs them: the compiled rule rows resolved
  to that spacecraft's effective rules (`MonitoringPlan.effective/2`); plans without rule rows as
  they are.
  """
  @spec monitoring_for(t(), binary(), binary() | nil) :: [MonitoringPlan.t()]
  def monitoring_for(index, parameter_id, spacecraft_id \\ nil) do
    index
    |> monitoring_rows(parameter_id)
    |> Enum.map(&MonitoringPlan.effective(&1, spacecraft_id))
  end

  defp monitoring_rows(%__MODULE__{table: nil, monitoring: monitoring}, parameter_id),
    do: Map.get(monitoring, parameter_id, [])

  defp monitoring_rows(%__MODULE__{table: table, plan_id: plan_id}, parameter_id),
    do: lookup(table, {plan_id, :monitoring, parameter_id})

  @doc "The algorithms that read `parameter_id` as an input (the caller applies their triggers)."
  @spec algorithms_for_input(t(), binary()) :: [AlgorithmPlan.t()]
  def algorithms_for_input(%__MODULE__{table: nil, algorithms_by_input: by_input}, parameter_id),
    do: Map.get(by_input, parameter_id, [])

  def algorithms_for_input(%__MODULE__{table: table, plan_id: plan_id}, parameter_id),
    do: lookup(table, {plan_id, :algorithms_for, parameter_id})

  @spec algorithms_with_id(t(), binary()) :: [AlgorithmPlan.t()]
  def algorithms_with_id(%__MODULE__{table: nil, algorithms_by_id: by_id}, algorithm_id),
    do: Map.get(by_id, algorithm_id, [])

  def algorithms_with_id(%__MODULE__{table: table, plan_id: plan_id}, algorithm_id),
    do: lookup(table, {plan_id, :algorithm, algorithm_id})

  @doc false
  # The entries a plan contributes to the cache, `{key, list}` under `plan_id`: what `from_cache/3`
  # reads back. One definition of the grouping for both forms.
  @spec entries(term(), [AlgorithmPlan.t()], [MonitoringPlan.t()]) :: [{tuple(), list()}]
  def entries(plan_id, algorithms, monitoring) do
    monitoring_entries =
      for {parameter_id, plans} <- Enum.group_by(monitoring, & &1.parameter_id),
          do: {{plan_id, :monitoring, parameter_id}, plans}

    input_entries =
      for {parameter_id, plans} <- by_input(algorithms),
          do: {{plan_id, :algorithms_for, parameter_id}, plans}

    id_entries =
      for {algorithm_id, plans} <- Enum.group_by(algorithms, & &1.algorithm_id),
          do: {{plan_id, :algorithm, algorithm_id}, plans}

    monitoring_entries ++ input_entries ++ id_entries
  end

  defp by_input(algorithms) do
    algorithms
    |> Enum.flat_map(fn algorithm ->
      algorithm.input_parameter_ids |> Enum.uniq() |> Enum.map(&{&1, algorithm})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{^key, plans}] -> plans
      [] -> []
    end
  end

  defp algorithm(%AlgorithmPlan{} = plan), do: plan
  defp algorithm(attrs), do: AlgorithmPlan.new(attrs)
  defp monitoring_plan(%MonitoringPlan{} = plan), do: plan
  defp monitoring_plan(attrs), do: MonitoringPlan.new(attrs)
end
