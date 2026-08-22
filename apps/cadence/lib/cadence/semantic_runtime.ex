defmodule Cadence.SemanticRuntime do
  @moduledoc """
  Pure ordered parameter, algorithm, and monitoring execution shared by live
  partitions and replay.
  """

  alias Cadence.Catalog.MissionModel.Canonical

  alias Cadence.SemanticRuntime.{
    AlgorithmPlan,
    ExpressionEvaluator,
    MonitoringEvaluator,
    MonitoringPlan,
    Result,
    Scope,
    State,
    Update
  }

  @quality_rank %{good: 0, suspect: 1, bad: 2, unknown: 3}

  @type plan :: %{
          algorithms: [AlgorithmPlan.t()],
          monitoring: [MonitoringPlan.t()],
          registered_implementations: map()
        }

  @spec new() :: State.t()
  def new, do: %State{}

  @spec process(State.t(), [Update.t()], plan()) :: {:ok, Result.t(), State.t()}
  def process(%State{} = state, updates, plan) when is_list(updates) and is_map(plan) do
    algorithms = Enum.map(Map.get(plan, :algorithms, []), &build_algorithm/1)
    monitoring = Enum.map(Map.get(plan, :monitoring, []), &build_monitoring/1)

    Enum.reduce_while(updates, {:ok, %Result{}, state}, fn update, {:ok, result, acc_state} ->
      case process_update(update, algorithms, monitoring, result, acc_state) do
        {:ok, next_result, next_state} -> {:cont, {:ok, next_result, next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec timer(State.t(), binary(), DateTime.t(), plan()) :: {:ok, Result.t(), State.t()}
  def timer(%State{} = state, algorithm_id, %DateTime{} = at, plan) do
    timer(state, Scope.mission(), algorithm_id, at, plan)
  end

  @spec timer(State.t(), Scope.t(), binary(), DateTime.t(), plan()) ::
          {:ok, Result.t(), State.t()}
  def timer(%State{} = state, scope, algorithm_id, %DateTime{} = at, plan) do
    all_algorithms =
      plan
      |> Map.get(:algorithms, [])
      |> Enum.map(&build_algorithm/1)

    algorithms = Enum.filter(all_algorithms, &(&1.algorithm_id == algorithm_id))

    evaluate_algorithms(
      algorithms,
      all_algorithms,
      %{
        trigger_id: "timer:" <> algorithm_id <> ":" <> DateTime.to_iso8601(at),
        at: at,
        scope: scope
      },
      Enum.map(Map.get(plan, :monitoring, []), &build_monitoring/1),
      %Result{},
      state
    )
  end

  defp process_update(%Update{} = update, algorithms, monitoring, result, state) do
    scope = Scope.from_update(update)
    state = put_update(state, scope, update)
    {result, state} = evaluate_monitoring(update, scope, monitoring, result, state)

    impacted =
      Enum.filter(algorithms, fn algorithm ->
        update.parameter_id in algorithm.input_parameter_ids and input_trigger?(algorithm, update)
      end)

    evaluate_algorithms(
      impacted,
      algorithms,
      %{trigger_id: update.update_id, at: update.receipt_time, scope: scope},
      monitoring,
      append_update(result, update),
      state
    )
  end

  defp evaluate_algorithms(
         selected_algorithms,
         all_algorithms,
         trigger,
         monitoring,
         result,
         state
       ) do
    Enum.reduce_while(selected_algorithms, {:ok, result, state}, fn algorithm,
                                                                    {:ok, acc_result, acc_state} ->
      case evaluate_algorithm(algorithm, trigger, acc_state) do
        {:ok, derived_updates, next_state} ->
          derived_updates
          |> process_derived_updates(
            all_algorithms,
            monitoring,
            acc_result,
            next_state
          )
          |> reduction_step()

        {:skip, next_state} ->
          {:cont, {:ok, acc_result, next_state}}

        {:error, reason} ->
          {:halt, {:error, {algorithm.algorithm_id, reason}}}
      end
    end)
  end

  defp process_derived_updates(updates, algorithms, monitoring, result, state) do
    Enum.reduce_while(updates, {:ok, result, state}, fn update, {:ok, acc_result, acc_state} ->
      case process_update(update, algorithms, monitoring, acc_result, acc_state) do
        {:ok, next_result, next_state} -> {:cont, {:ok, next_result, next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reduction_step({:ok, result, state}), do: {:cont, {:ok, result, state}}
  defp reduction_step({:error, reason}), do: {:halt, {:error, reason}}

  defp evaluate_algorithm(%AlgorithmPlan{} = algorithm, trigger, %State{} = state) do
    state_key = Scope.state_key(trigger.scope, algorithm.algorithm_id)

    with {:ok, inputs} <- fetch_inputs(algorithm, trigger.scope, trigger.at, state.latest),
         {:ok, outputs, algorithm_state} <-
           evaluate_outputs(
             algorithm,
             inputs,
             Map.get(state.algorithm_state, state_key, %{}),
             trigger.at
           ) do
      quality = worst_quality(Map.values(inputs))
      source_update_ids = Enum.map(Map.values(inputs), & &1.update_id)

      updates =
        Enum.map(outputs, fn {output, value} ->
          Update.new(%{
            update_id:
              Canonical.content_id("parameter_update", {
                algorithm.algorithm_id,
                output.parameter_id,
                trigger.trigger_id,
                value
              }),
            parameter_id: output.parameter_id,
            qualified_name: output.qualified_name,
            value: value,
            raw_value: nil,
            quality: quality,
            generation_time: latest_generation_time(Map.values(inputs), trigger.at),
            receipt_time: trigger.at,
            producer_kind: :algorithm,
            producer_id: algorithm.algorithm_id,
            source_update_ids: source_update_ids,
            metadata: derived_metadata(inputs, trigger)
          })
        end)

      {:ok, updates,
       %State{state | algorithm_state: Map.put(state.algorithm_state, state_key, algorithm_state)}}
    else
      :missing when algorithm.missing_input == :skip -> {:skip, state}
      :stale when algorithm.missing_input == :skip -> {:skip, state}
      :missing -> {:error, :missing_input}
      :stale -> {:error, :stale_input}
      {:error, reason} -> {:error, reason}
    end
  end

  defp evaluate_outputs(algorithm, inputs, algorithm_state, at) do
    bindings = Map.new(inputs, fn {id, update} -> {id, update.value} end)

    case implementation_kind(algorithm.implementation) do
      :expression ->
        evaluate_expression_outputs(algorithm, bindings, at, algorithm_state)

      :registered ->
        evaluate_registered_outputs(algorithm, bindings, at, algorithm_state)

      kind ->
        {:error, {:unsupported_algorithm_implementation, kind}}
    end
  end

  defp evaluate_expression_outputs(
         algorithm,
         bindings,
         at,
         current_state
       ) do
    Enum.reduce_while(algorithm.outputs, {:ok, [], current_state}, fn output,
                                                                      {:ok, values, acc_state} ->
      case ExpressionEvaluator.evaluate(output.expression, bindings, acc_state, at: at) do
        {:ok, value, next_state} -> {:cont, {:ok, [{output, value} | values], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values, next_state} ->
        {:ok, Enum.reverse(values), next_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp evaluate_registered_outputs(
         algorithm,
         bindings,
         at,
         current_state
       ) do
    implementation = algorithm.implementation

    with true <- value(implementation, :authorized?, false),
         module when is_atom(module) <- value(implementation, :module),
         {:ok, output_values, next_state} when is_map(output_values) and is_map(next_state) <-
           module.evaluate(bindings, current_state, %{
             algorithm_id: algorithm.algorithm_id,
             at: at
           }),
         {:ok, outputs} <- match_registered_outputs(algorithm.outputs, output_values) do
      {:ok, outputs, next_state}
    else
      false -> {:error, :registered_implementation_not_allowed}
      nil -> {:error, :registered_implementation_not_allowed}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_registered_implementation_result, other}}
    end
  end

  defp match_registered_outputs(outputs, values) do
    Enum.reduce_while(outputs, {:ok, []}, fn output, {:ok, acc} ->
      case Map.fetch(values, output.parameter_id) do
        {:ok, value} -> {:cont, {:ok, [{output, value} | acc]}}
        :error -> {:halt, {:error, {:registered_output_missing, output.parameter_id}}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_inputs(algorithm, scope, at, latest) do
    algorithm.input_parameter_ids
    |> Enum.reduce_while({:ok, %{}}, fn parameter_id, {:ok, inputs} ->
      case fetch_input(latest, scope, parameter_id, algorithm, at) do
        {:ok, update} -> {:cont, {:ok, Map.put(inputs, parameter_id, update)}}
        {:error, reason} -> {:halt, reason}
      end
    end)
  end

  defp fetch_input(latest, scope, parameter_id, algorithm, at) do
    case Map.get(latest, Scope.state_key(scope, parameter_id)) do
      nil -> {:error, :missing}
      update -> validate_input_age(algorithm, update, at)
    end
  end

  defp validate_input_age(algorithm, update, at) do
    if stale?(algorithm, update, at), do: {:error, :stale}, else: {:ok, update}
  end

  defp stale?(%AlgorithmPlan{maximum_age_ms: nil}, _update, _at), do: false

  defp stale?(algorithm, update, at) do
    update_time =
      case algorithm.time_basis do
        :generation_time -> update.generation_time || update.receipt_time
        :receipt_time -> update.receipt_time
      end

    DateTime.diff(at, update_time, :millisecond) > algorithm.maximum_age_ms
  end

  defp evaluate_monitoring(update, scope, monitoring, result, state) do
    scoped_latest = scoped_latest(state.latest, scope)

    monitoring
    |> Enum.filter(&(&1.parameter_id == update.parameter_id))
    |> Enum.reduce({result, state}, fn plan, {%Result{} = acc_result, %State{} = acc_state} ->
      state_key = Scope.state_key(scope, plan.policy_id)
      prior = Map.get(acc_state.monitoring_state, state_key, %{})

      {monitoring_result, next_monitoring_state} =
        MonitoringEvaluator.evaluate(plan, update, scoped_latest, prior)

      next_state = %State{
        acc_state
        | monitoring_state: Map.put(acc_state.monitoring_state, state_key, next_monitoring_state)
      }

      next_result = %Result{
        acc_result
        | monitoring_results: acc_result.monitoring_results ++ [monitoring_result],
          alarm_transitions:
            if(monitoring_result.transition,
              do: acc_result.alarm_transitions ++ [monitoring_result],
              else: acc_result.alarm_transitions
            )
      }

      {next_result, next_state}
    end)
  end

  defp put_update(%State{} = state, scope, update) do
    %State{
      state
      | latest: Map.put(state.latest, Scope.state_key(scope, update.parameter_id), update),
        sequence: state.sequence + 1
    }
  end

  defp scoped_latest(latest, scope) do
    Map.new(latest, fn
      {{^scope, parameter_id}, update} -> {parameter_id, update}
      {key, update} -> {key, update}
    end)
    |> Map.take(
      latest
      |> Enum.flat_map(fn
        {{^scope, parameter_id}, _update} -> [parameter_id]
        _other -> []
      end)
    )
  end

  defp append_update(%Result{} = result, update),
    do: %Result{result | parameter_updates: result.parameter_updates ++ [update]}

  defp input_trigger?(%AlgorithmPlan{triggers: []}, _update), do: true

  defp input_trigger?(algorithm, update) do
    Enum.any?(algorithm.triggers, fn trigger ->
      kind = value(trigger, :kind)
      parameter_id = value(trigger, :parameter_id)
      kind in [:parameter_update, "parameter_update"] and parameter_id == update.parameter_id
    end)
  end

  defp worst_quality([]), do: :unknown

  defp worst_quality(updates) do
    updates
    |> Enum.map(& &1.quality)
    |> Enum.max_by(&Map.get(@quality_rank, &1, 3))
  end

  defp latest_generation_time([], fallback), do: fallback

  defp latest_generation_time(updates, _fallback) do
    updates
    |> Enum.map(&(&1.generation_time || &1.receipt_time))
    |> Enum.reduce(&later_time/2)
  end

  defp derived_metadata(inputs, trigger) do
    source =
      inputs
      |> Map.values()
      |> Enum.sort_by(& &1.update_id)
      |> List.first()

    if source do
      source.metadata
      |> Map.put(:trigger_sample_id, trigger.trigger_id)
    else
      {mission_id, spacecraft_id} = trigger.scope

      %{
        trigger_sample_id: trigger.trigger_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft_id
      }
    end
  end

  defp later_time(left, right) do
    if DateTime.compare(left, right) == :gt, do: left, else: right
  end

  defp build_algorithm(%AlgorithmPlan{} = plan), do: plan
  defp build_algorithm(attrs), do: AlgorithmPlan.new(attrs)
  defp build_monitoring(%MonitoringPlan{} = plan), do: plan
  defp build_monitoring(attrs), do: MonitoringPlan.new(attrs)

  defp implementation_kind(implementation) do
    case value(implementation, :kind, :expression) do
      kind when kind in [:expression, "expression"] -> :expression
      kind when kind in [:registered, "registered"] -> :registered
      kind -> kind
    end
  end

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
