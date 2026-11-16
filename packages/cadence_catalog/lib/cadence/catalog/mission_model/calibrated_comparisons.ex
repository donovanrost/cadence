defmodule Cadence.Catalog.MissionModel.CalibratedComparisons do
  @moduledoc """
  A lint on lowered command constraints and verifiers (DECISIONS #92 (c), part A).

  A calibrated comparison (`use_calibrated`, the default) reads the subject's engineering value.
  For a parameter with states that value is the state's label, so a comparison against a number
  never holds as meant: `MM_CALIBRATED_COMPARISON_NUMERIC_ON_STATES` (a warning) asks for the
  label, or for `use_calibrated: false` to compare the raw value. A number that is itself one of
  the labels is left alone. `value_from_argument` comparisons are checked by `ArgumentCriteria`.
  """

  alias Cadence.Catalog.MissionModel.{Diagnostic, Reference}

  @code "MM_CALIBRATED_COMPARISON_NUMERIC_ON_STATES"

  @doc """
  Warnings for `plans` (constraint and verifier plan documents). `model` maps semantic ids to the
  revision's declarations (subjects are telemetry parameters); `index` holds the plan owners.
  """
  @spec warnings([map()], map(), map()) :: [Diagnostic.t()]
  def warnings(plans, model, index) do
    for plan <- plans,
        owner_id = get(plan, :constraint_id) || get(plan, :verifier_id),
        owner = Map.get(index, owner_id),
        criteria <- [
          get(plan, :criteria),
          get(plan, :success_criteria),
          get(plan, :failure_criteria)
        ],
        comparison <- comparisons(criteria),
        states = states(get(comparison, :subject_ref), model),
        numeric_on_states?(comparison, states) do
      warning(owner, comparison, states)
    end
  end

  defp comparisons(criteria) when is_map(criteria) do
    nested =
      [:conditions, :comparisons]
      |> Enum.flat_map(&List.wrap(get(criteria, &1)))
      |> Enum.flat_map(&comparisons/1)

    if is_nil(get(criteria, :subject_ref)), do: nested, else: [criteria | nested]
  end

  defp comparisons(_criteria), do: []

  defp numeric_on_states?(_comparison, []), do: false

  defp numeric_on_states?(comparison, states) do
    value = get(comparison, :value)

    get(comparison, :use_calibrated) != false and is_nil(get(comparison, :value_from_argument)) and
      numeric?(value) and to_string(value) not in states
  end

  defp numeric?(value) when is_number(value), do: true

  defp numeric?(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {_number, ""} -> true
      _other -> false
    end
  end

  defp numeric?(_value), do: false

  # The subject parameter's state labels; [] for anything else.
  defp states(subject_ref, model) do
    with %{kind: :parameter} = parameter <- Map.get(model, subject_ref),
         %Reference{resolved_id: type_id} when is_binary(type_id) <-
           Enum.find(parameter.references, &(&1.role == :type)),
         %{definition: definition} <- Map.get(model, type_id) do
      for state <- List.wrap(get(definition, :enumerations)),
          label = get(state, :label),
          is_binary(label),
          do: label
    else
      _not_a_parameter -> []
    end
  end

  defp warning(owner, comparison, states) do
    Diagnostic.new(%{
      code: @code,
      severity: :warning,
      stage: :target_lowering,
      target: :command,
      semantic_id: owner.semantic_id,
      support: :lossy,
      message:
        "#{owner.name} compares #{inspect(get(comparison, :value))} with a calibrated value, " <>
          "which is a state label (#{Enum.join(Enum.take(states, 4), ", ")}" <>
          if(length(states) > 4, do: ", ...)", else: ")") <>
          "; compare the label, or set use_calibrated: false to compare the raw value",
      provenance: owner.provenance
    })
  end

  defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp get(_value, _key), do: nil
end
