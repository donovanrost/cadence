defmodule Cadence.SemanticRuntime.Carry do
  @moduledoc """
  What a partition's state keeps across a runtime basis change (#443, DECISIONS #92 phase 1b).

  A new model revision gives the partition a new runtime basis, but most of what the partition
  remembers (an alarm's candidate state and counts, an algorithm's memory, a parameter's latest
  value, a timer's last firing) belongs to an identity the revision did not touch. `fingerprints/2`
  names each identity's definition by its content: a monitoring policy's and an algorithm's decoded
  plan (an algorithm's includes the registered implementation bound to it), and a parameter's
  telemetry type and the algorithm output that derives it. The state carries the fingerprints it
  was evolved under (`State.fingerprints`); `carry/2` keeps an entry only when its identity is in
  the new plan with the same fingerprint. Anything else starts fresh: a changed threshold, a new
  implementation, a parameter whose type changed, a renamed declaration (its id changed), and
  everything new. The check is the content, so a policy edited and edited back still starts fresh
  once, never carries state evolved under a definition it no longer has.
  """

  alias Cadence.Platform.ContentHash
  alias Cadence.SemanticRuntime.{AlgorithmPlan, MonitoringPlan, State}

  @type fingerprints :: %{
          algorithms: %{binary() => binary()},
          monitoring: %{binary() => binary()},
          parameters: %{binary() => binary()}
        }

  @type report :: %{
          kept: non_neg_integer(),
          dropped: non_neg_integer()
        }

  @doc """
  The fingerprints of what `runtime_plans` (the activation's plans by target) and their decoded
  `plan` (`PlanDecoder.decode/1`) define.
  """
  @spec fingerprints(map(), map()) :: fingerprints()
  def fingerprints(runtime_plans, %{algorithms: algorithms, monitoring: monitoring})
      when is_map(runtime_plans) do
    %{
      algorithms: Map.new(algorithms, &{&1.algorithm_id, digest(&1)}),
      monitoring: Map.new(monitoring, &{&1.policy_id, digest(&1)}),
      parameters: parameters(runtime_plans, algorithms)
    }
  end

  @spec empty() :: fingerprints()
  def empty, do: %{algorithms: %{}, monitoring: %{}, parameters: %{}}

  @doc """
  The state to run `fingerprints` with: `state`'s entries whose identity and fingerprint still
  match, stamped with `fingerprints`. `report` counts the entries kept and dropped.
  """
  @spec carry(State.t(), fingerprints()) :: {State.t(), report()}
  def carry(%State{} = state, fingerprints) do
    before = entries(state)

    kept = %State{
      state
      | latest: keep(state.latest, state.fingerprints, fingerprints, :parameters),
        algorithm_state:
          keep(state.algorithm_state, state.fingerprints, fingerprints, :algorithms),
        monitoring_state:
          keep(state.monitoring_state, state.fingerprints, fingerprints, :monitoring),
        timer_cursors: keep_timers(state, fingerprints),
        fingerprints: fingerprints
    }

    after_ = entries(kept)
    {kept, %{kept: after_, dropped: before - after_}}
  end

  defp keep(entries, old, new, kind) do
    stable = stable_ids(Map.get(old, kind, %{}), Map.fetch!(new, kind))
    Map.filter(entries, fn {{_scope, id}, _value} -> MapSet.member?(stable, id) end)
  end

  # A timer's key is "semantic:<algorithm id>:<trigger index>": it follows its algorithm.
  defp keep_timers(%State{timer_cursors: cursors, fingerprints: old}, new) do
    stable = stable_ids(Map.get(old, :algorithms, %{}), new.algorithms)

    Map.filter(cursors, fn {key, _at} ->
      Enum.any?(stable, &String.starts_with?(key, "semantic:" <> &1 <> ":"))
    end)
  end

  defp stable_ids(old, new) do
    for {id, fingerprint} <- new, Map.get(old, id) == fingerprint, into: MapSet.new(), do: id
  end

  defp entries(%State{} = state),
    do:
      map_size(state.latest) + map_size(state.algorithm_state) + map_size(state.monitoring_state) +
        map_size(state.timer_cursors)

  # A parameter is what telemetry fields of that id say its type is, plus the algorithm output
  # that derives it, if any. A parameter neither reads nor derives has no fingerprint, so its
  # latest value is not carried.
  defp parameters(runtime_plans, algorithms) do
    telemetry = telemetry_fields(Map.get(runtime_plans, :telemetry))

    derived =
      for %AlgorithmPlan{outputs: outputs} <- algorithms, output <- outputs do
        {output.parameter_id, {:derived, digest(output)}}
      end

    (telemetry ++ derived)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {id, facts} -> {id, digest(Enum.sort(facts))} end)
  end

  defp telemetry_fields(nil), do: []

  defp telemetry_fields(%{status: :ready, plan: plan}) do
    for definition <- list(plan, "packet_definitions"),
        field <- list(definition, "fields"),
        id = value(field, "parameter_id"),
        is_binary(id) do
      {id,
       {:telemetry, value(field, "data_type"), value(field, "engineering_unit"),
        value(field, "size_bits"), value(field, "byte_order")}}
    end
  end

  defp telemetry_fields(_plan), do: []

  defp list(map, key), do: value(map, key) || []

  defp value(map, key) when is_map(map),
    do: Map.get(map, key)

  # Where a definition lives (its system, its qualified name) is not what it evaluates: moving it
  # between systems keeps its state.
  defp digest(%MonitoringPlan{} = plan),
    do: ContentHash.term_sha256({:monitoring_plan, placed(plan)})

  defp digest(%AlgorithmPlan{} = plan),
    do: ContentHash.term_sha256({:algorithm_plan, placed(plan)})

  defp digest(term), do: ContentHash.term_sha256(term)

  defp placed(plan), do: %{plan | space_system_id: nil, runtime_name: nil}
end
