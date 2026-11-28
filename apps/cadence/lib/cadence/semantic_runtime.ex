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
    PlanIndex,
    Result,
    Scope,
    State,
    Update
  }

  @quality_rank %{good: 0, suspect: 1, bad: 2, unknown: 3}

  # The plan to run: the decoded lists (every existing caller), or an index of the node's plan cache
  # (a partition, #451 T1).
  @type plan ::
          %{
            algorithms: [AlgorithmPlan.t()],
            monitoring: [MonitoringPlan.t()],
            registered_implementations: map()
          }
          | PlanIndex.t()

  @spec new() :: State.t()
  def new, do: %State{}

  @doc """
  Seeds monitoring policies' effective states on an empty start (director 11-15): each
  `{scope, policy_id, effective_state}` becomes the policy's prior, with its counts at 0, so a
  parameter that cleared while the partition was down clears its alarm on the first normal sample,
  and one still in alarm doesn't raise again. A policy already in the state is left as it is.
  """
  @spec seed_monitoring(State.t(), [{Scope.t(), binary(), atom()}]) :: State.t()
  def seed_monitoring(%State{} = state, entries) when is_list(entries) do
    seeded =
      Map.new(entries, fn {scope, policy_id, effective_state} ->
        {Scope.state_key(scope, policy_id),
         %{
           effective_state: effective_state,
           candidate_state: effective_state,
           violation_count: 0,
           conformance_count: 0
         }}
      end)

    %State{state | monitoring_state: Map.merge(seeded, state.monitoring_state)}
  end

  @spec process(State.t(), [Update.t()], plan()) :: {:ok, Result.t(), State.t()}
  def process(%State{} = state, updates, plan) when is_list(updates) and is_map(plan) do
    index = PlanIndex.wrap(plan)

    Enum.reduce_while(updates, {:ok, %Result{}, state}, fn update, {:ok, result, acc_state} ->
      case process_update(update, index, result, acc_state) do
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
    index = PlanIndex.wrap(plan)

    evaluate_algorithms(
      PlanIndex.algorithms_with_id(index, algorithm_id),
      index,
      %{
        trigger_id: "timer:" <> algorithm_id <> ":" <> DateTime.to_iso8601(at),
        at: at,
        scope: scope,
        effect_source: ["timer:" <> algorithm_id, 0, DateTime.to_unix(at, :microsecond)]
      },
      %Result{},
      state
    )
  end

  defp process_update(%Update{} = update, index, result, state) do
    scope = Scope.from_update(update)
    state = put_update(state, scope, update)
    {result, state} = evaluate_monitoring(update, scope, index, result, state)

    impacted =
      index
      |> PlanIndex.algorithms_for_input(update.parameter_id)
      |> Enum.filter(&input_trigger?(&1, update))

    evaluate_algorithms(
      impacted,
      index,
      %{
        trigger_id: update.update_id,
        at: update.receipt_time,
        scope: scope,
        effect_source: effect_source(update.metadata)
      },
      append_update(result, update),
      state
    )
  end

  defp evaluate_algorithms(selected_algorithms, index, trigger, result, state) do
    Enum.reduce_while(selected_algorithms, {:ok, result, state}, fn algorithm,
                                                                    {:ok, acc_result, acc_state} ->
      case evaluate_algorithm(algorithm, trigger, acc_state) do
        {:ok, derived_updates, next_state} ->
          derived_updates
          |> process_derived_updates(index, acc_result, next_state)
          |> reduction_step()

        {:skip, next_state} ->
          {:cont, {:ok, acc_result, next_state}}

        {:error, reason} ->
          {:halt, {:error, {algorithm.algorithm_id, reason}}}
      end
    end)
  end

  defp process_derived_updates(updates, index, result, state) do
    Enum.reduce_while(updates, {:ok, result, state}, fn update, {:ok, acc_result, acc_state} ->
      case process_update(update, index, acc_result, acc_state) do
        {:ok, next_result, next_state} -> {:cont, {:ok, next_result, next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reduction_step({:ok, result, state}), do: {:cont, {:ok, result, state}}
  defp reduction_step({:error, reason}), do: {:halt, {:error, reason}}

  defp evaluate_algorithm(%AlgorithmPlan{} = algorithm, trigger, %State{} = state) do
    state_key = Scope.state_key(trigger.scope, algorithm.algorithm_id)

    with {:ok, inputs, stale?} <-
           fetch_inputs(algorithm, trigger.scope, trigger.at, state.latest),
         {:ok, outputs, algorithm_state} <-
           evaluate_outputs(
             algorithm,
             inputs,
             Map.get(state.algorithm_state, state_key, %{}),
             trigger.at
           ) do
      quality = if stale?, do: :bad, else: worst_quality(Map.values(inputs))
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
      # A missing input leaves nothing to compute, whatever the policy. Erroring here failed the
      # whole evidence, so nothing committed, `latest` never filled, and the journal retried the
      # batch forever: a wedge on every empty start (director 11-15).
      :missing -> {:skip, state}
      :stale -> {:skip, state}
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
             at: at,
             input_parameter_ids: algorithm.input_parameter_ids,
             inputs_in_order: Enum.map(algorithm.input_parameter_ids, &Map.fetch!(bindings, &1))
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

  # `missing_input: :bad_quality` computes from stale inputs and marks the output `:bad`; `:skip`
  # skips. A missing input skips under both.
  defp fetch_inputs(algorithm, scope, at, latest) do
    algorithm.input_parameter_ids
    |> Enum.reduce_while({:ok, %{}, false}, fn parameter_id, {:ok, inputs, stale?} ->
      case fetch_input(latest, scope, parameter_id, algorithm, at) do
        {:ok, update} ->
          {:cont, {:ok, Map.put(inputs, parameter_id, update), stale?}}

        {:error, :stale, update} when algorithm.missing_input == :bad_quality ->
          {:cont, {:ok, Map.put(inputs, parameter_id, update), true}}

        {:error, :stale, _update} ->
          {:halt, :stale}

        {:error, :missing} ->
          {:halt, :missing}
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
    if stale?(algorithm, update, at), do: {:error, :stale, update}, else: {:ok, update}
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

  defp evaluate_monitoring(update, scope, index, result, state) do
    scoped_latest = scoped_latest(state.latest, scope)

    index
    |> PlanIndex.monitoring_for(update.parameter_id, Scope.spacecraft_id(scope))
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
      |> put_trigger_frame(trigger)
    else
      {mission_id, spacecraft_id} = trigger.scope

      put_trigger_frame(
        %{
          trigger_sample_id: trigger.trigger_id,
          mission_id: mission_id,
          spacecraft_id: spacecraft_id
        },
        trigger
      )
    end
  end

  # A derived update's effects are keyed on its TRIGGER (DECISIONS #99): the trigger's journal
  # frame, or for a timer the algorithm's timer stream and fire time. Never on the frame of
  # whichever input's metadata it copies: that may be an older frame, whose effect ids are taken.
  defp put_trigger_frame(metadata, trigger) do
    metadata = Map.drop(metadata, [:effect_source, "effect_source"])

    case Map.get(trigger, :effect_source) do
      nil -> metadata
      source -> Map.put(metadata, :effect_source, source)
    end
  end

  defp effect_source(metadata),
    do: Map.get(metadata, :effect_source, Map.get(metadata, "effect_source"))

  defp later_time(left, right) do
    if DateTime.compare(left, right) == :gt, do: left, else: right
  end

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
