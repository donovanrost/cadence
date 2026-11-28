defmodule Cadence.SemanticRuntime.MonitoringPlan do
  @moduledoc "Executable monitoring policy for one semantic parameter."

  alias Cadence.SemanticRuntime.EffectiveRules

  @type t :: %__MODULE__{
          policy_id: binary(),
          parameter_id: binary(),
          contexts: [map()],
          default_rules: [map()],
          minimum_violations: pos_integer(),
          minimum_conformance: pos_integer(),
          missing_state: atom(),
          invalid_state: atom(),
          disabled: boolean(),
          rule_digest: binary() | nil,
          rules: [map()]
        }

  @enforce_keys [:policy_id, :parameter_id]
  defstruct @enforce_keys ++
              [
                contexts: [],
                default_rules: [],
                minimum_violations: 1,
                minimum_conformance: 1,
                missing_state: :unknown,
                invalid_state: :unknown,
                disabled: false,
                # The digest of the rules in force for this parameter (#451 T2): when it changes the
                # persistence counters reset and the result says so. nil (a plan without digests)
                # never resets anything.
                rule_digest: nil,
                # The compiled rule rows of this parameter, every scope (#451 T2): see
                # `effective/2`. Empty for a plan whose rules are all in `default_rules`.
                rules: []
              ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      policy_id: value(attrs, :policy_id),
      parameter_id: value(attrs, :parameter_id),
      contexts: value(attrs, :contexts, []),
      default_rules: value(attrs, :default_rules, []),
      minimum_violations: value(attrs, :minimum_violations, 1),
      minimum_conformance: value(attrs, :minimum_conformance, 1),
      missing_state: attrs |> value(:missing_state, :unknown) |> normalize_atom(),
      invalid_state: attrs |> value(:invalid_state, :unknown) |> normalize_atom(),
      disabled: value(attrs, :disabled, false),
      rule_digest: value(attrs, :rule_digest),
      rules: value(attrs, :rules, [])
    }
  end

  @doc """
  The plan as one spacecraft runs it: its compiled rule rows resolved to the spacecraft's
  effective set (`EffectiveRules`), added to the plan's own `default_rules`, with the digest of what
  is in force. A plan with no rule rows is returned as it is.
  """
  @spec effective(t(), binary() | nil) :: t()
  def effective(%__MODULE__{rules: []} = plan, _spacecraft_id), do: plan

  def effective(%__MODULE__{rules: rules} = plan, spacecraft_id) do
    in_force = EffectiveRules.for_spacecraft(rules, spacecraft_id)

    %__MODULE__{
      plan
      | default_rules: plan.default_rules ++ Enum.map(in_force, &EffectiveRules.evaluator_rule/1),
        rule_digest: EffectiveRules.digest(in_force, plan.rule_digest),
        rules: []
    }
  end

  defp normalize_atom(value) when is_atom(value), do: value
  defp normalize_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end
